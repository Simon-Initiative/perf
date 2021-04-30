# Perf

Performance and load testing framework for `Torus` that leverages
`polleverywhere/chaperon`. 

## Installation

1. `git clone <this repo>`
2. `cd perf`
3. `mix deps.compile`

## Executing a test (localhost)

1. Ensure you have your Torus instance running with the `:load_testing_mode` configuration option set to `:enabled`. 
2. Ensure that you have one or more open and free sections in your instance.  
2. Open an `iex` shell via: `iex -S mix`
3. Start the test via `Perf.go`
4. After the test finishes, look at the results in `/results`

