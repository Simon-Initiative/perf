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
      {{50, Perf.Scenarios.VisitAllPages}, %{iterations: 1}}
    ]
end
