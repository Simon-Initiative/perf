defmodule Perf.Scenarios.Utils do
  import Chaperon.Session
  import Chaperon.Timing

  @random_queue_names 1..1000
                      |> Enum.map(fn v -> "_queue_" <> Integer.to_string(v) end)
                      |> Enum.map(fn s -> String.to_atom(s) end)

  @doc """
  Decodes testing meta-data from the contents of a server rendered HTML page.

  An example of server-encoded meta-data would appear in an HTML comment and look like this:

  ```
  <html>
  <body>
  <p>The actual content of the page</p>
  <!--
  __OVERVIEW_PAGES__2023092309230923ASLDKJ24092UALKJASD902U43JKASD09U23LADS09U__OVERVIEW_PAGES__
  -->
  </body>
  </html>
  ```

  With the above HTML content, calling `decode_testing_metadata("__OVERVIEW_PAGES__", content)` results
  in the decoded list returned.

  """
  def decode_testing_metadata(key, content) do
    parts = String.split(content, key)

    case length(parts) do
      3 ->
        Enum.at(parts, 1)
        |> Base.decode64!()
        |> Jason.decode!()

      _ ->
        []
    end
  end

  @doc """
  Simulates a student viewing a page in a course section.  If present, will decode
  meta-data for the attempts for the activities on the page, and the URL to use to
  finalized the page attempt.
  """
  def view_page(session, page) do
    session
    |> get(page["url"],
      headers: %{"accept" => "text/html", "content-type" => "text/html"},
      decode: fn response ->
        {:ok,
         {decode_testing_metadata("__ACTIVITY_ATTEMPTS__", response),
          decode_testing_metadata("__FINALIZATION_URL__", response)}}
      end,
      with_result: fn s, {attempts, finalize_url} ->
        url =
          case finalize_url do
            %{"url" => url} -> url
            _ -> nil
          end

        assign(s, activity_attempts: attempts, finalize_url: url)
      end,
      metrics_url: "/page"
    )
  end

  @doc """
  Simulates a student submitting an active graded page attempt.
  """
  def submit_assessment(session) do
    session
    |> get(session.assigned.finalize_url,
      metrics_url: "/finalize_attempt"
    )
  end

  @doc """
  Simulates a student starting a graded page attempt.
  """
  def start_graded_page_attempt(session, page) do
    session
    |> get(page["url"] <> "/attempt",
      metrics_url: "/start_attempt"
    )
  end

  @doc """
  Applies a session aware task function sequentially to the members of
  a list based assign, effectively treating the assign as a work queue.  Does not
  exhaust the queue, instead copying it first, which allows subsequent for_each
  invocations on the queue in the same session.

  Intersperses a configurable, random delay between task function invocations.
  """
  def for_each(session, original_queue, task_fn, delay \\ 3) do
    random_queue = random_queue()

    session
    |> seed_queue_from(original_queue, random_queue)
    |> for_each_impl(random_queue, task_fn, delay)
  end

  defp for_each_impl(session, queue, task_fn, delay) do
    case session.assigned[queue] do
      [] ->
        session

      [next | remaining] ->
        session
        |> assign(Keyword.new() |> Keyword.put(queue, remaining))
        |> delay({:random, delay |> seconds})
        |> task_fn.(next)
        |> for_each_impl(queue, task_fn, delay)
    end
  end

  defp random_queue() do
    Enum.random(@random_queue_names)
  end

  @doc """
  Creates a new assign by copying the contents of an existing assign, optionally filtering
  that source list.
  """
  def seed_queue_from(session, source, destination, filter_fn \\ fn _ -> true end) do
    results = Enum.filter(session.assigned[source], filter_fn)
    assign(session, Keyword.new() |> Keyword.put(destination, results))
  end

  @doc """
  Exhaust all hints for all activities in an activity, sequentially. This works via the "hints"
  assign serving as a work queue. This function will get called recursively to process items
  from that queue.
  """
  def exhaust_hints(session, activity_attempt, delay \\ 3) do
    case session.assigned[:hints] do
      nil ->
        session
        |> seed_hints(activity_attempt)
        |> exhaust_hints(activity_attempt)

      [] ->
        session
        |> assign(hints: nil)

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
        |> exhaust_hints(activity_attempt, delay)
    end
  end

  # Construct a list of URLs that will retrieve each hint from all parts and activities.
  defp seed_hints(session, activity_attempt) do
    session
    |> assign(
      hints:
        Enum.reduce(activity_attempt["parts"], [], fn p, all ->
          if p["hasMoreHints"] do
            [
              "/api/v1/state/course/#{session.assigned.section.slug}/activity_attempt/#{activity_attempt["attemptGuid"]}/part_attempt/#{p["attemptGuid"]}/hint"
              | all
            ]
          else
            all
          end
        end)
    )
  end

  @doc """
  Retrieves the collection of available open and free sections and either selects the
  section specified by the section_slug argument.  If argument omitted, selects a random
  section. The selection is placed into the `section` assign.
  """
  def pick_section(session, section_slug \\ nil) do
    session
    |> get("/api/v1/testing/openfree",
      decode: :json,
      with_result: fn s, results ->
        case section_slug do
          nil ->
            assign(s, section: Enum.random(results))

          _ ->
            assign(s,
              section: Enum.find(results, fn section -> section.slug == section_slug end)
            )
        end
      end
    )
  end

  @doc """
  Simulates the user answering the recaptcha and clicking "Enroll".
  """
  def login(session) do
    session
    |> post("/sections/#{session.assigned.section.slug}/enroll",
      headers: %{"accept" => "text/html"},
      json: %{
        "g-recaptcha-response" => ""
      }
    )
  end

  @doc """
  Retrieves the "Overview" page of the course section and decodes the load testing metadata present there,
  storing that as the `pages` assign.
  """
  def view_section_overview(session) do
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
  Simulates the student submitting an answer for all parts of an activity. Whether or not
  an activity is supported is driven from the `answers` map present in the activity_attempt. The
  `answers` map is a server constructed map of part ids to the JSON that represents a valid
  (but not necessarily correct) answer for that part.
  """
  def submit_activity(session, activity_attempt) do
    case length(Map.get(activity_attempt, "answers") |> Map.keys()) do
      0 ->
        session

      _ ->
        session
        |> put(
          "/api/v1/state/course/#{session.assigned.section.slug}/activity_attempt/#{activity_attempt["attemptGuid"]}",
          metrics_url: "/submission",
          json: %{
            "partInputs" =>
              Enum.map(activity_attempt["parts"], fn p ->
                %{
                  "attemptGuid" => p["attemptGuid"],
                  "response" => activity_attempt["answers"][p["partId"]]
                }
              end)
          }
        )
    end
  end
end
