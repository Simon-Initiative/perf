defmodule Perf.LoadTest.Production do
  use Chaperon.LoadTest

  def default_config,
    do: %{
      # scenario_timeout: 12_000,
      base_url: "https://loadtest.oli.cmu.edu/",
      http: %{
        # additional http (hackney request) parameters, if needed
        ssl: [{:versions, [:"tlsv1.2"]}],
        recv_timeout: 10000
      }
    }

  def scenarios,
    do: [
      {{1, Perf.Scenarios.TakeAssessment},
       %{section_slug: "kth_cs101", page_slug: "security_quiz", num_attempts: 5}},
      {{100, Perf.Scenarios.VisitAllPages}, %{iterations: 1}}
    ]
end
