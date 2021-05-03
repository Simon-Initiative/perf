defmodule Perf.Scenarios.Utils do
  import Chaperon.Session
  import Chaperon.Timing

  def decode_testing_metadata(key, content) do
    String.split(content, key)
    |> Enum.at(1)
    |> Base.decode64!()
    |> Jason.decode!()
  end

  @doc """
  Visits every page in the course outline sequentially, with a random pause in between visits.
  For each page it sequentially requests all available hints for all activities present in the page,
  with a random delay in between each hint request.
  """
  def exercise_all_pages(session, with_result, exercises, delay \\ 3) do
    case session.assigned.pages do
      [] ->
        session

      [next | remaining] ->
        session
        |> assign(pages: remaining)
        |> delay({:random, delay |> seconds})
        |> get(next,
          headers: %{"accept" => "text/html", "content-type" => "text/html"},
          decode: fn response ->
            {:ok, Perf.Scenarios.Utils.decode_testing_metadata("__ACTIVITY_ATTEMPTS__", response)}
          end,
          with_result: with_result,
          metrics_url: "/page"
        )
        |> exercises.()
        |> exercise_all_pages(with_result, exercises, delay)
    end
  end

  @doc """
  Exhaust all hints for all activities in a page, sequentially. This works via the "hints"
  assign serving as a work queue. This function will get called recursively to process items
  from that queue.
  """
  def exhaust_all_hints(session, delay \\ 3) do
    case session.assigned.hints do
      [] ->
        session

      [next | rest] ->
        session
        |> get(next,
          decode: :json,
          with_result: fn s, hint ->
            # If this part has another hint available, do not remove its URL from
            # the queue, allowing it to be requested.
            if hint["hasMoreHints"] do
              s
            else
              # No more hints for this part, so update the assign in a way that pops it
              # off of the queue.
              assign(s, hints: rest)
            end
          end,
          metrics_url: "/hint"
        )
        |> delay({:random, delay |> seconds})
        |> exhaust_all_hints()
    end
  end

  # Construct a list of URLs that will retrieve each hint from all parts and activities.
  def seed_hints(slug, attempts) do
    Enum.reduce(attempts, [], fn a, all ->
      Enum.reduce(a["parts"], all, fn p, all ->
        if p["hasMoreHints"] do
          [
            "/api/v1/state/course/#{slug}/activity_attempt/#{a["attemptGuid"]}/part_attempt/#{
              p["attemptGuid"]
            }/hint"
            | all
          ]
        else
          all
        end
      end)
    end)
  end

  @doc """
  Retrieves the collection of available open and free sections and in conjunction with select_random/2,
  randomly chooses one, adding that section as the "section" assign.
  """
  def pick_random_section(session) do
    session
    |> get("/api/v1/testing/openfree", decode: :json, with_result: &select_random(&1, &2))
  end

  @doc """
  This post simulates the user answering the recaptcha and clicking "Enroll".
  """
  def login(session) do
    session
    |> post("/sections/#{session.assigned.section.slug}/create_user",
      headers: %{"accept" => "text/html"},
      json: %{
        "g-recaptcha-response" => ""
      }
    )
  end

  @doc """
  Retrieves the "Overview" page of the course section and decodes the load testing metadata present there,
  storing that as the "pages" assign.
  """
  def visit_overview(session) do
    session
    |> get(session.assigned.section.url,
      headers: %{"accept" => "text/html", "content-type" => "text/html"},
      decode: fn response ->
        {:ok, Perf.Scenarios.Utils.decode_testing_metadata("__OVERVIEW_PAGES__", response)}
      end,
      with_result: fn s, pages -> assign(s, pages: pages) end
    )
  end

  def select_random(session, result) do
    session
    |> assign(section: Enum.random(result))
  end

  def submit_all_activities(session, delay \\ 3) do
    case session.assigned.attempts do
      [] ->
        session

      [next | rest] ->
        case length(Map.get(next, "answers") |> Map.keys()) do
          0 ->
            assign(session, attempts: rest)
            |> submit_all_activities()

          _ ->
            delay(session, {:random, delay |> seconds})
            |> assign(attempts: rest)
            |> put(
              "/api/v1/state/course/#{session.assigned.section.slug}/activity_attempt/#{
                next["attemptGuid"]
              }",
              metrics_url: "/submission",
              json: %{
                "partInputs" =>
                  Enum.map(next["parts"], fn p ->
                    %{
                      "attemptGuid" => p["attemptGuid"],
                      "response" => next["answers"][p["partId"]]
                    }
                  end)
              }
            )
            |> submit_all_activities()
        end
    end
  end
end
