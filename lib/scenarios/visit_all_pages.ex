defmodule Perf.Scenarios.VisitAllPages do
  use Chaperon.Scenario

  import Perf.Scenarios.Utils

  @moduledoc """
  A scenario that will pick a random available open and free section, login, and then
  visit every practice page in the course outline. For each page it requests every hint available for
  every activity on the page and submits an answer for every activity.

  This scenario can be configured to run any number of iterations.
  """

  def init(session) do
    session
    |> ok
  end

  def run(session) do
    session
    |> pick_section()
    |> repeat(:visit, session.config.iterations)
  end

  def visit(session) do
    session
    |> delete_cookies()
    |> login()
    |> view_section_overview()
    |> seed_queue_from(:pages, :practice_pages, fn p -> !p["graded"] end)
    |> for_each(
      :practice_pages,
      fn session, page ->
        session
        |> view_page(page)
        |> for_each(
          :activity_attempts,
          fn session, activity_attempt ->
            exhaust_hints(session, activity_attempt)
            |> submit_activity(activity_attempt)
          end
        )
      end
    )
  end
end
