defmodule Perf do
  @moduledoc """
  Documentation for `Perf`.
  """

  @doc """
  Run test.any()

  ## Examples

      iex> Perf.go()

  """
  def go do
    Chaperon.run_load_test(Perf.LoadTest.Production, print_results: false)
  end
end
