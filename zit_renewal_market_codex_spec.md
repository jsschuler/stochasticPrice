# ZIT Renewal Market: Codex Implementation Specification

## Purpose

Build a simple stochastic price-theory model in which a large finite population of zero-intelligence traders enters, exits, and re-enters a discrete market. Agents trade only integral quantities, prices are rational, and the model tests whether coarse-grained transaction prices recover the competitive equilibrium price interval in expectation.

The core hypothesis is:

> A zero-intelligence trader (ZIT) market with random Poisson exit, Poisson entry, and endowment refilling can recover the Walrasian / discrete competitive equilibrium price in expectation at suitable time and measurement grains. As the grain expands, the error term should fall.

This model is intentionally **not** bigeometric yet. It is the stochastic price-theory model. Bigeometric price theory should be developed separately and combined only later.

---

## Modeling Principles

1. **Quantities are integral.**
   - Goods are counted units.
   - Endowments, supplies, demands, and traded quantities are integers.

2. **Prices are rational.**
   - WTP, WTA, bids, asks, and transaction prices should be represented as rational numbers where possible.
   - In Julia, prefer `Rational{Int}` or `Rational{BigInt}` depending on scale.

3. **Agents are zero-intelligence but constrained.**
   - Buyers do not bid above their WTP.
   - Sellers do not ask below their WTA.
   - Agents do not solve a global optimization problem.

4. **Entry and exit are stochastic renewal processes.**
   - Exits follow a Poisson process.
   - Entries follow a Poisson process.
   - Entry and exit shocks may be correlated using a Gaussian copula.
   - The copula correlation parameter may be set to `0` for independent entry and exit.

5. **Re-entry refills tradeable endowment.**
   - When an agent re-enters the active market, their tradeable endowment is refreshed from an integer distribution.
   - Their WTP/WTA schedule may also be refreshed.

6. **Equilibrium is a benchmark, not an agent objective.**
   - At each macro window, compute the discrete competitive equilibrium price interval from the active population.
   - Compare coarse-grained transaction prices to that interval.

---

## Core Types

### Agent

A minimal agent should include:

```julia
struct Agent
    id::Int
    active::Bool
    role::Symbol              # :buyer, :seller, or possibly :both later
    endowment::Int            # integral tradeable inventory
    acquired::Int             # units acquired through trade
    wtp::Vector{Rational{Int}} # descending marginal willingness-to-pay
    wta::Vector{Rational{Int}} # ascending marginal willingness-to-accept / cost
end
```

For the first version, roles may be fixed as `:buyer` or `:seller`. Later, agents can be allowed to be both buyers and sellers depending on endowment and preferences.

### MarketConfig

```julia
struct MarketConfig
    n_agents::Int
    initial_active_share::Float64
    buyer_share::Float64

    lambda_exit::Float64
    lambda_entry::Float64
    entry_exit_rho::Float64   # Gaussian copula correlation; 0 means independent

    max_endowment::Int
    max_wtp_units::Int
    price_min::Rational{Int}
    price_max::Rational{Int}

    ticks_per_period::Int
    n_periods::Int
    seed::Int
end
```

### TradeRecord

```julia
struct TradeRecord
    period::Int
    tick::Int
    buyer_id::Int
    seller_id::Int
    bid::Rational{Int}
    ask::Rational{Int}
    price::Rational{Int}
    quantity::Int
end
```

### EquilibriumRecord

```julia
struct EquilibriumRecord
    period::Int
    p_low::Rational{Int}
    p_high::Rational{Int}
    q_star::Int
    active_buyers::Int
    active_sellers::Int
end
```

---

## Stochastic Entry and Exit

At each period `t`, define the active population size:

```math
A_t = \#\{i : active_i(t)=1\}.
```

A simple period-level exit count is:

```math
X_t \sim \mathrm{Poisson}(\lambda_X A_t).
```

A simple period-level entry count is:

```math
E_t \sim \mathrm{Poisson}(\lambda_E (N-A_t)).
```

Cap these counts:

```math
X_t \le A_t,
\qquad
E_t \le N-A_t+X_t.
```

That is, exiting agents become eligible for re-entry depending on update order. The recommended first implementation order is:

1. Draw exits from currently active agents.
2. Mark them inactive.
3. Draw entries from currently inactive agents.
4. Refill endowment and refresh WTP/WTA schedules for entrants.
5. Mark entrants active.

---

## Gaussian Copula for Entry-Exit Dependence

We want `X_t` and `E_t` to be marginally Poisson, but dependence controlled by a correlation parameter `rho`.

Algorithm:

1. Draw correlated normals:

```math
\begin{pmatrix} Z_X \\ Z_E \end{pmatrix}
\sim
\mathcal{N}\left(
\begin{pmatrix}0\\0\end{pmatrix},
\begin{pmatrix}1 & \rho \\ \rho & 1\end{pmatrix}
\right).
```

2. Convert to uniforms:

```math
U_X = \Phi(Z_X),
\qquad
U_E = \Phi(Z_E).
```

3. Convert to Poisson counts:

```math
X_t = F_X^{-1}(U_X),
\qquad
E_t = F_E^{-1}(U_E),
```

where `F_X` and `F_E` are Poisson CDFs with means:

```math
\mu_X = \lambda_X A_t,
\qquad
\mu_E = \lambda_E (N-A_t+X_t).
```

Implementation note: in Julia, `Distributions.jl` provides `Normal`, `Poisson`, `cdf`, and `quantile`.

Special case:

```julia
rho = 0.0
```

should generate independent Poisson entry and exit shocks.

Interpretation:

- `rho = 0`: independent entry and exit.
- `rho > 0`: churn regimes; high exits tend to coincide with high entries.
- `rho < 0`: thinning regimes; high exits tend to coincide with low entries.

---

## Endowment Refill and Schedule Refresh

When an agent re-enters:

```math
e_i(t^+) \sim F_e,
\qquad e_i(t^+) \in \mathbb{N}.
```

For sellers, `endowment` is the number of sellable units.

For buyers, the relevant tradeable capacity is the length of the WTP vector or a budget constraint. For the first version, avoid budget complications and give buyers a WTP schedule of integer length.

Recommended first version:

- Seller receives:

```julia
endowment ∈ 1:max_endowment
wta = sorted random rational costs, ascending, length=endowment
```

- Buyer receives:

```julia
endowment = 0
wtp = sorted random rational values, descending, length=max_wtp_units
```

The model remains integral because each marginal WTP/WTA corresponds to one unit.

---

## Integral Demand and Supply

For buyer `i`, demand at price `p` is:

```math
D_i(p)=\#\{n : v_i^n \ge p\}.
```

For seller `j`, supply correspondence at price `p` is:

```math
S_{j,\min}(p)=\#\{n : c_j^n < p\},
```

```math
S_{j,\max}(p)=\#\{n : c_j^n \le p\}.
```

Aggregate demand:

```math
D_t(p)=\sum_{i\in A_t}D_i(p).
```

Aggregate supply correspondence:

```math
S_{t,\min}(p)=\sum_{j\in A_t}S_{j,\min}(p),
```

```math
S_{t,\max}(p)=\sum_{j\in A_t}S_{j,\max}(p).
```

Discrete market clearing condition:

```math
D_t(p^*)\in [S_{t,\min}(p^*), S_{t,\max}(p^*)].
```

---

## Competitive Equilibrium Benchmark

For each period or macro window, compute the active-population benchmark.

Collect all active buyers' marginal WTP values:

```math
V_t = \{v_i^n : i active buyer, n=1,\dots,m_i\}.
```

Collect all active sellers' marginal WTA values:

```math
C_t = \{c_j^n : j active seller, n=1,\dots,e_j\}.
```

Sort:

```math
v_{(1),t}\ge v_{(2),t}\ge\cdots,
```

```math
c_{(1),t}\le c_{(2),t}\le\cdots.
```

Efficient competitive quantity:

```math
q_t^* = \max\{q : v_{(q),t} \ge c_{(q),t}\}.
```

Equilibrium price interval:

```math
I_t^* = [p_{L,t}^*,p_{U,t}^*].
```

Minimal first version:

```math
p_{L,t}^* = c_{(q_t^*),t},
\qquad
p_{U,t}^* = v_{(q_t^*),t}.
```

More careful later version may account for adjacent no-trade units:

```math
p_{L,t}^* = \max(c_{(q_t^*),t}, v_{(q_t^*+1),t}),
```

```math
p_{U,t}^* = \min(v_{(q_t^*),t}, c_{(q_t^*+1),t}).
```

Use the simpler version first, then refine.

If no gains from trade exist, set:

```julia
q_star = 0
p_low = missing
p_high = missing
```

or define a no-trade interval separately.

---

## ZIT Trading Protocol

At each tick within a period:

1. Select a random active buyer with remaining WTP units.
2. Select a random active seller with positive endowment.
3. Buyer draws a bid constrained by WTP:

```math
b_i \in \mathbb{Q}_+,
\qquad b_i \le v_i^{next}.
```

4. Seller draws an ask constrained by WTA:

```math
a_j \in \mathbb{Q}_+,
\qquad a_j \ge c_j^{next}.
```

5. If:

```math
b_i \ge a_j,
```

trade occurs.

6. Transaction price is rational. Recommended first rule:

```math
p^{tr}=\frac{a_j+b_i}{2}.
```

7. Quantity traded:

```math
q^{tr}=1.
```

8. Update buyer and seller states:

```julia
buyer.acquired += 1
seller.endowment -= 1
```

Also advance the buyer's consumed WTP unit and seller's used WTA unit.

### Bid and Ask Drawing

Use rational grids.

For buyer:

```julia
bid = random_rational_between(price_min, current_wtp)
```

For seller:

```julia
ask = random_rational_between(current_wta, price_max)
```

A simple implementation can draw integer cents or integer ticks and convert to rationals.

Example:

```julia
function random_rational_between(lo::Rational{Int}, hi::Rational{Int}, denom::Int=100)
    lo_i = ceil(Int, lo * denom)
    hi_i = floor(Int, hi * denom)
    if lo_i > hi_i
        return missing
    end
    return rand(lo_i:hi_i) // denom
end
```

---

## Coarse-Graining

Transaction records are grouped into windows.

Let window size be `G` trades or `G` ticks.

For each window `w`, compute:

Arithmetic mean price:

```math
\bar p_w = \frac{1}{N_w}\sum_{r\in w}p_r^{tr}.
```

Median transaction price:

```math
\tilde p_w = \operatorname{median}\{p_r^{tr}:r\in w\}.
```

Optional geometric mean for later bigeometric comparison:

```math
p_w^{geo}=\exp\left(\frac{1}{N_w}\sum_{r\in w}\log p_r^{tr}\right).
```

Do not use the geometric mean as the main statistic in the first stochastic model. Keep it as a diagnostic.

---

## Error Metrics

Let the equilibrium interval for window `w` be:

```math
I_w^*=[p_{L,w}^*,p_{U,w}^*].
```

Define distance from price `p` to interval:

```math
d(p,I^*) =
\begin{cases}
0, & p\in I^*,\\
p_L^*-p, & p<p_L^*,\\
p-p_U^*, & p>p_U^*.
\end{cases}
```

Compute:

```math
error_w = d(\bar p_w,I_w^*).
```

Also compute:

```math
abs_mid_error_w = |\bar p_w - midpoint(I_w^*)|.
```

where:

```math
midpoint(I_w^*) = \frac{p_L^*+p_U^*}{2}.
```

The interval-distance error is preferred.

---

## Main Simulation Diagnostics

For each grain/window size `G`, estimate:

1. Mean interval error:

```math
\mathbb{E}[d(\bar p_G,I_G^*)].
```

2. Root mean squared error:

```math
RMSE_G = \sqrt{\mathbb{E}[d(\bar p_G,I_G^*)^2]}.
```

3. Probability of equilibrium recovery:

```math
\Pr(\bar p_G\in I_G^*).
```

4. Variance of window-level average price:

```math
\operatorname{Var}(\bar p_G).
```

5. Log-log slope of error versus grain:

```math
\log(error_G) = \alpha - \beta \log(G) + \epsilon_G.
```

A simple LLN/CLT-like benchmark suggests:

```math
\beta \approx 1/2.
```

But serial dependence and renewal shocks may reduce the slope.

---

## Main Hypotheses

### H1: Equilibrium recovery in expectation

As grain `G` expands:

```math
\mathbb{E}[d(\bar p_G,I_G^*)]\to 0.
```

Or more conservatively:

```math
\mathbb{E}[\bar p_G]\in I_G^*
```

within simulation tolerance.

### H2: Error declines with grain

```math
\mathbb{E}[d(\bar p_G,I_G^*)]
```

should decline as `G` increases.

Expected approximate rate under weak dependence:

```math
O(G^{-1/2}).
```

### H3: Entry-exit correlation affects convergence

The Gaussian copula parameter `rho` should affect the effective variance:

```math
\sigma_{eff}^2(\rho).
```

Expected qualitative effects:

- `rho = 0`: baseline convergence.
- `rho > 0`: churn shocks; possibly higher variance, but active population remains more stable.
- `rho < 0`: thinning shocks; likely higher error and more unstable recovery.

### H4: High renewal improves stationarity

Moderate entry and exit can improve sampling of the underlying valuation distribution, but excessive churn may raise volatility.

---

## Recommended Experiments

### Experiment 1: Baseline independent renewal

Set:

```julia
rho = 0.0
lambda_exit = lambda_entry
```

Run many simulations and plot:

```math
error_G \text{ versus } G.
```

Expected result: decreasing error with increasing grain.

### Experiment 2: Copula dependence sweep

Run:

```julia
rho_values = [-0.75, -0.5, 0.0, 0.5, 0.75]
```

Compare error curves and active-population volatility.

### Experiment 3: Renewal-rate sweep

Run:

```julia
lambda_values = [0.001, 0.005, 0.01, 0.05, 0.1]
```

Compare equilibrium recovery.

### Experiment 4: Population-size sweep

Run:

```julia
N_values = [100, 500, 1000, 5000, 10000]
```

Compare finite-population error.

### Experiment 5: Price protocol comparison

Compare transaction price rules:

1. Midpoint:

```math
p=(ask+bid)/2.
```

2. Buyer bid:

```math
p=bid.
```

3. Seller ask:

```math
p=ask.
```

4. Random rational point in the feasible interval:

```math
p\sim U_\mathbb{Q}([ask,bid]).
```

Check which protocol best recovers the WGE benchmark in expectation.

---

## Implementation Outline

Recommended file structure:

```text
src/
  ZITRenewalMarket.jl
  agents.jl
  renewal.jl
  trading.jl
  equilibrium.jl
  coarse_grain.jl
  diagnostics.jl

scripts/
  run_baseline.jl
  sweep_rho.jl
  sweep_grain.jl

test/
  runtests.jl
  test_equilibrium.jl
  test_renewal.jl
  test_trading.jl
```

---

## Main Simulation Loop

Pseudocode:

```julia
function run_simulation(config::MarketConfig)
    rng = MersenneTwister(config.seed)
    agents = initialize_agents(config, rng)

    trades = TradeRecord[]
    equilibria = EquilibriumRecord[]

    for period in 1:config.n_periods
        # 1. Renewal
        exits, entries = draw_entry_exit_counts(agents, config, rng)
        apply_exits!(agents, exits, rng)
        apply_entries!(agents, entries, config, rng)

        # 2. Benchmark equilibrium for active population
        eq = compute_equilibrium(agents, period)
        push!(equilibria, eq)

        # 3. ZIT trading ticks
        for tick in 1:config.ticks_per_period
            trade = attempt_random_trade!(agents, period, tick, config, rng)
            if trade !== nothing
                push!(trades, trade)
            end
        end
    end

    return trades, equilibria
end
```

---

## Tests

### Test 1: Rational prices

All WTP, WTA, bids, asks, and transaction prices should be rational.

```julia
@test price isa Rational
```

### Test 2: Integral quantities

All endowments and traded quantities should be integers.

```julia
@test agent.endowment isa Int
@test trade.quantity == 1
```

### Test 3: Feasible trades only

For every trade:

```math
ask \le price \le bid.
```

and:

```math
current_wta \le ask \le bid \le current_wtp.
```

### Test 4: Equilibrium computation on known example

Use the small README-style example:

Buyers:

```julia
[9,7,5,3,1]
[8,6,4,2]
```

Sellers:

```julia
[2,4,6,8]
[1,3,5,7]
```

Expected:

```julia
q_star == 5
p_low <= 5//1 <= p_high
```

Depending on the interval definition, `p_low == 5//1` and `p_high == 5//1` may hold.

### Test 5: Copula independence at rho = 0

For a long simulated sequence, sample correlation between entry and exit counts should be close to zero when:

```julia
rho = 0.0
```

Use a tolerance appropriate for stochastic tests.

---

## Outputs

Save simulation results as CSV or Arrow/Parquet:

```text
outputs/
  trades.csv
  equilibria.csv
  coarse_grain_results.csv
  diagnostics.csv
```

Required columns for `coarse_grain_results.csv`:

```text
grain_size, window_id, mean_price, median_price, geo_mean_price,
p_low, p_high, q_star, interval_error, midpoint_error, n_trades,
active_buyers, active_sellers, rho, lambda_exit, lambda_entry, seed
```

---

## Plotting

Generate plots:

1. Transaction prices over time with equilibrium interval bands.
2. Coarse-grained mean prices over time with equilibrium interval bands.
3. Error versus grain size.
4. Log error versus log grain size.
5. Error curves by `rho`.
6. Active population size over time.
7. Entry and exit counts over time.

---

## Success Criteria

The first working version is successful if it can:

1. Simulate a large finite ZIT renewal market.
2. Preserve integer quantities and rational prices.
3. Generate Poisson entry and exit with optional Gaussian-copula dependence.
4. Refill endowments upon re-entry.
5. Compute active-population discrete competitive equilibrium intervals.
6. Coarse-grain transaction prices.
7. Show whether error falls as grain increases.

The model does **not** need to prove convergence analytically in version 1. Simulation evidence and clean diagnostics are enough.

---

## Later Extensions

Do not implement these in the first pass unless the base model is stable.

1. Multi-good markets.
2. Agents who can be both buyers and sellers.
3. Budget constraints.
4. Inventory holding costs.
5. Factor markets.
6. Order-book institutions.
7. Bigeometric price grids.
8. Stochastic multiplicative price adjustment.
9. Endogenous role switching.
10. Nonstationary renewal distributions.

---

## Conceptual Summary

This model should demonstrate that classical competitive price theory can appear as a coarse-grained expectation of a stochastic zero-intelligence market process.

Agents do not optimize globally. They enter, exit, re-enter, and trade randomly subject only to feasibility constraints. Yet under appropriate renewal and measurement grains, the transaction-price process may recover the competitive equilibrium interval generated by the active population's integral supply and demand schedules.

The guiding thesis is:

> Traditional price theory is an effective theory of coarse-grained market observables, not necessarily a pointwise description of agent cognition.
