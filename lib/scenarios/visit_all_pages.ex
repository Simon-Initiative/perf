defmodule Perf.Scenarios.VisitAllPages do
  use Chaperon.Scenario

  @moduledoc """
  A scenario that will pick a random available open and free section, login, and then
  visit every page in the course outline. For each page it requests every hint available for
  every activity on the page.
  """

  def init(session) do
    session
    |> assign(section: nil, pages: nil, attempts: nil, hints: nil)
    |> ok
  end

  def run(session) do
    session
    |> pick_random_section()
    |> login()
    |> visit_overview()
    |> exercise_all_pages()
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
    |> post("/course/users",
      headers: %{"accept" => "text/html"},
      json: %{
        "user_details" => %{"redirect_to" => session.assigned.section.url},
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

  @doc """
  Visits every page in the course outline sequentially, with a random pause in between visits.
  For each page it sequentially requests all available hints for all activities present in the page,
  with a random delay in between each hint request.
  """
  def exercise_all_pages(session) do
    case session.assigned.pages do
      [] ->
        session

      [next | remaining] ->
        session
        |> assign(pages: remaining)
        |> delay({:random, 3 |> seconds})
        |> get(next,
          headers: %{"accept" => "text/html", "content-type" => "text/html"},
          decode: fn response ->
            {:ok, Perf.Scenarios.Utils.decode_testing_metadata("__ACTIVITY_ATTEMPTS__", response)}
          end,
          with_result: fn s, attempts ->
            assign(s, attempts: attempts, hints: seed_hints(s.assigned.section.slug, attempts))
          end,
          metrics_url: "/page"
        )
        |> exhaust_all_hints()
        |> exercise_all_pages()
    end
  end

  @doc """
  Exhaust all hints for all activities in a page, sequentially. This works via the "hints"
  assign serving as a work queue. This function will get called recursively to process items
  from that queue.
  """
  def exhaust_all_hints(session) do
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
        |> delay({:random, 3 |> seconds})
        |> exhaust_all_hints()
    end
  end

  defp select_random(session, result) do
    session
    |> assign(section: Enum.random(result))
  end

  # Construct a list of URLs that will retrieve each hint from all parts and activities.
  defp seed_hints(slug, attempts) do
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
end
