defmodule Perf.Scenarios.Utils do
  def decode_testing_metadata(key, content) do
    String.split(content, key)
    |> Enum.at(1)
    |> Base.decode64!()
    |> Jason.decode!()
  end
end
