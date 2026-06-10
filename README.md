# ZIT Renewal Market

A Julia 1.11 implementation of a finite zero-intelligence trader market with
Poisson renewal, Gaussian-copula entry/exit dependence, integral quantities,
exact rational prices, and discrete competitive-equilibrium diagnostics.

## Run

Instantiate the project and run the tests:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

Run the default 1,000-agent, 100,000-tick baseline:

```sh
julia --project=. scripts/run_baseline.jl
```

Run a grain study with custom output location and grain sizes:

```sh
julia --project=. scripts/sweep_grain.jl outputs/custom 25,100,500,2000
```

Each run writes transaction, equilibrium, renewal, coarse-grain, and diagnostic
CSV files plus six PNG diagnostics. Price columns include decimal values and
exact numerator/denominator columns.

## Package API

```julia
using ZITRenewalMarket

config = default_config(seed=42, n_periods=10)
result = run_simulation(config)
windows = coarse_grain(result)
diagnostics = summarize_diagnostics(windows)
write_results("outputs/example", result, windows, diagnostics)
make_plots("outputs/example", result, windows, diagnostics)
```

Entry and exit counts are drawn from period-start active and inactive pools.
Agents exiting in a period cannot re-enter until the following period, so
`entry_exit_rho = 0.0` gives genuinely independent count shocks conditional on
the period-start population.
