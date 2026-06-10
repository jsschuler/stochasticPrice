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

Run the parallel long study:

```sh
julia --project=. scripts/run_long_study.jl
```

Run the paired buyer-capacity comparison:

```sh
julia --project=. scripts/compare_capacity_bias.jl
```

Run the population and renewal-rate study:

```sh
julia --project=. scripts/study_population_renewal.jl
```

Run the continuous-double-auction comparison:

```sh
julia --project=. scripts/study_cda_convergence.jl
```

The baseline and grain scripts write transaction, equilibrium, renewal,
coarse-grain, and diagnostic CSV files plus six PNG diagnostics. Price columns
include decimal values and exact numerator/denominator columns. The long study
writes compact per-seed and cross-seed summaries plus two aggregate plots.

## Long-Study Findings

The long study was run on June 10, 2026 using 10 independent seeds in parallel.
Each seed simulated 1,000 agents for 500 periods of 1,000 ticks, for a total of
5,000,000 ticks and 48,816 completed trades. Entry and exit were independent
(`rho = 0`), with `lambda_exit = 0.01` and `lambda_entry = 0.04`.

| Grain | Mean interval error | 95% CI half-width | Mean price variance |
| ---: | ---: | ---: | ---: |
| 10 | 18.348 | 0.152 | 376.929 |
| 100 | 17.271 | 0.214 | 314.119 |
| 1,000 | 12.906 | 0.313 | 59.354 |
| 5,000 | 12.621 | 0.351 | 12.080 |
| 50,000 | 12.774 | 0.363 | 1.367 |

The findings are:

- Coarse-graining strongly reduces variance: window-mean price variance fell
  99.6% between grains 10 and 50,000.
- Mean interval error fell 30.4% over the same range, but stopped improving
  around grains 5,000 to 50,000. The aggregate log-log slope was only `-0.051`,
  far from the `-0.5` weak-dependence benchmark.
- Exact interval recovery remained rare at small grains and was not observed
  at grains 5,000 or larger. Lower variance therefore did not imply convergence
  to the competitive-equilibrium interval.
- The active population was stable: the cross-run mean was 801.8 agents, and
  the mean within-run standard deviation was 11.3 agents.
- Under the current uniform valuation schedules and midpoint transaction rule,
  the simulation supports variance reduction but does not support the stronger
  hypothesis that coarse-grained transaction prices converge to the active
  population's competitive-equilibrium interval.

Reproduce the study with `scripts/run_long_study.jl`. Detailed results and
plots are written to `outputs/long_study/`; generated outputs are intentionally
excluded from version control.

## Capacity-Bias Experiment

A paired 10-seed experiment compared the baseline five-unit buyer schedules
with three-unit buyer schedules. Sellers retain uniformly distributed
endowments from one to five units, so their expected capacity is three units.
Each treatment simulated 5,000,000 ticks.

| Buyer units | Mean trade price | Mean equilibrium midpoint | Grain-50,000 signed gap | Grain-50,000 interval error |
| ---: | ---: | ---: | ---: | ---: |
| 3 | 50.518 | 50.558 | -0.008 | 1.360 |
| 5 | 55.991 | 68.895 | -12.907 | 12.774 |

Balancing expected buyer and seller capacity removed the directional price
bias: the signed midpoint gap was statistically indistinguishable from zero at
every measured grain. At grain 50,000, 51% of balanced-capacity windows were
below the equilibrium interval and 45% were above it, compared with 100% below
under the five-unit baseline.

This shows that the baseline bias is not caused by agents being unable to trade
past equilibrium. It comes from combining excess aggregate demand with a
bilateral quote protocol whose accepted midpoint prices remain much closer to
the center of the configured price grid than to the scarcity-shifted
competitive price. Coarse-graining removes sampling variance but cannot remove
that structural difference in expected prices.

The balanced treatment still had positive absolute interval error because its
window prices remained dispersed around a narrow equilibrium interval. That
error declined from 16.149 at grain 10 to 1.360 at grain 50,000, unlike the
baseline error floor near 12.8.

## Population and Renewal Study

A 45-run study crossed balanced-capacity populations of 1,000, 5,000, and
10,000 agents with three renewal intensities. Five paired seeds were simulated
for each combination, with 200,000 ticks per run. Renewal rates were increased
proportionally so the expected active share remained 80%:

| Renewal | `lambda_exit` | `lambda_entry` |
| --- | ---: | ---: |
| 1x | 0.01 | 0.04 |
| 5x | 0.05 | 0.20 |
| 10x | 0.10 | 0.40 |

Mean interval error at grain 20,000 was:

| Agents | 1x renewal | 5x renewal | 10x renewal |
| ---: | ---: | ---: | ---: |
| 1,000 | 1.512 | 1.030 | 0.685 |
| 5,000 | 0.846 | 0.407 | 0.367 |
| 10,000 | 0.560 | 0.365 | 0.329 |

Both changes improve recovery:

- Increasing population lowers finite-market noise and narrows the equilibrium
  benchmark. At baseline renewal, raising population from 1,000 to 10,000
  reduced grain-20,000 error by 62.9%.
- Faster renewal produces more completed trades and more independent schedule
  refreshes within a fixed tick window. At 1,000 agents, 10x renewal increased
  mean trade count from 1,906 to 9,315 and reduced error by 54.7%.
- Renewal has diminishing returns at larger populations. At 10,000 agents,
  grain-20,000 error fell from 0.560 to 0.365 at 5x renewal, then only to 0.329
  at 10x renewal.
- Error continued declining through the largest tested grain in all nine
  treatments. Log-log slopes ranged from `-0.435` to `-0.500`, close to the
  weak-dependence `-0.5` benchmark. No persistent absolute-error floor was
  detected in the balanced model.

Signed midpoint gaps remained small relative to the original `-12.9` baseline
bias. Several 10,000-agent treatments showed a residual downward gap near
`-0.2` to `-0.3`; this is small but statistically detectable in some
treatments and may reflect the period-start equilibrium benchmark being held
fixed while inventories are depleted during the period.

Reproduce the study with `scripts/study_population_renewal.jl`. Summary CSVs
and plots are written to `outputs/population_renewal/`.

## Continuous Double Auction Fork

The package also provides `run_cda_simulation(config)`, a traditional
ZI-constrained continuous-double-auction fork that retains Poisson entry,
Poisson exit, and schedule/endowment refresh on re-entry. It differs from the
bilateral model by using:

- persistent standing bids and asks;
- price-time priority;
- one replaceable order per active agent;
- transaction prices equal to the standing order that an incoming quote
  crosses;
- cancellation of standing orders when agents exit.

A paired 10-seed study compared this CDA with the original bilateral mechanism
under the asymmetric five-unit buyer treatment. Each mechanism simulated
5,000,000 ticks.

| Mechanism | Mean trades/run | Mean trade price | Mean equilibrium midpoint | Grain-50,000 signed gap | Grain-50,000 error |
| --- | ---: | ---: | ---: | ---: | ---: |
| Bilateral midpoint | 4,919 | 56.150 | 68.688 | -12.502 | 12.372 |
| CDA standing price | 5,102 | 63.060 | 67.991 | -4.464 | 3.975 |

The CDA materially improves price discovery: it reduces the large-window
directional gap by 64.3% and interval error by 67.9%. The order book filters
random quotes through competition, moving transaction prices toward the
scarcity-shifted competitive benchmark.

It does not fully converge in this implementation. CDA error declined from
5.404 at grain 10 to 3.630 at grain 5,000, then rose to 3.975 at grain 50,000.
Its full-range log-log slope was `-0.044`, and every grain-50,000 window
remained below the equilibrium interval.

This is consistent with two differences from the static textbook experiment:

- Endowments and marginal schedules are depleted across periods and refreshed
  only through stochastic re-entry, rather than resetting the entire market
  each trading day.
- The equilibrium benchmark is computed at the beginning of each period and
  held fixed while trades alter the remaining supply and demand schedules.

The result therefore supports a qualified conclusion: a traditional CDA
institution substantially corrects the bilateral mechanism's structural bias,
but Poisson renewal alone does not make prices converge to a stale
period-start equilibrium benchmark. A cleaner next test is to recompute the
benchmark after each trade or reset all schedules at fixed trading-day
boundaries.

Reproduce the comparison with `scripts/study_cda_convergence.jl`. Outputs are
written to `outputs/cda_convergence/`.

## Package API

```julia
using ZITRenewalMarket

config = default_config(seed=42, n_periods=10)
result = run_simulation(config)
cda_result = run_cda_simulation(config)
windows = coarse_grain(result)
diagnostics = summarize_diagnostics(windows)
write_results("outputs/example", result, windows, diagnostics)
make_plots("outputs/example", result, windows, diagnostics)
```

Entry and exit counts are drawn from period-start active and inactive pools.
Agents exiting in a period cannot re-enter until the following period, so
`entry_exit_rho = 0.0` gives genuinely independent count shocks conditional on
the period-start population.
