defmodule Perf.Scenarios.TakeAssessment do
  use Chaperon.Scenario

  import Perf.Scenarios.Utils

  @moduledoc """
  A scenario that will take a specific graded assessment in a specific
  open and free section a specified number of times.
  """

  def init(session) do
    session
    |> ok
  end

  def run(session) do
    section_slug = session.config.section_slug
    page_slug = session.config.page_slug
    num_attempts = session.config.num_attempts

    session =
      session
      |> pick_section(section_slug)
      |> login()
      |> view_section_overview()

    page = Enum.find(session.assigned.pages, fn p -> p["slug"] == page_slug end)

    session
    |> repeat(:take_assessment, [page], num_attempts)
  end

  def take_assessment(session, page) do
    session
    |> view_page(page)
    |> start_graded_page_attempt(page)
    |> view_page(page)
    |> for_each(
      :activity_attempts,
      fn session, activity_attempt ->
        submit_activity(session, activity_attempt)
      end
    )
    |> submit_assessment()
  end
end
