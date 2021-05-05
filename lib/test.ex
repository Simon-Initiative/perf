defmodule Perf.LoadTest.Production do
  use Chaperon.LoadTest

  def default_config,
    do: %{
      # scenario_timeout: 12_000,
      base_url: "https://localhost/",
      http: %{
        # additional http (hackney request) parameters, if needed
        ssl: [{:versions, [:"tlsv1.2"]}],
        recv_timeout: 1000
      }
    }

  def scenarios,
    do: [
      {{1, Perf.Scenarios.TakeAssessment},
       %{section_slug: "example_course", page_slug: "quiz", num_attempts: 5}},
      {{1, Perf.Scenarios.VisitAllPages}, %{iterations: 1}}
    ]
end
