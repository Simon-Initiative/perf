defmodule Perf.Scenarios.VisitAllPages do
  use Chaperon.Scenario

  import Perf.Scenarios.Utils

  @moduledoc """
  A scenario that will pick a random available open and free section, login, and then
  visit every practice page in the course outline. For each page it requests every hint available for
  every activity on the page and finally submits an answer for every activity.
  """

  def init(session) do
    session
    |> ok
  end

  def run(session) do
    session
    |> pick_random_section()
    |> login()
    |> visit_overview()
    |> seed_queue_from(:pages, :practice_pages, fn p -> !p["graded"] end)
    |> exercise_pages(
      fn s, attempts ->
        assign(s, attempts: attempts, hints: seed_hints(s.assigned.section.slug, attempts))
      end,
      fn session ->
        exhaust_all_hints(session)
        |> submit_all_activities()
      end,
      :practice_pages
    )
  end
end
