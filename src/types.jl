const Price = Rational{Int}

Base.@kwdef struct MarketConfig
    n_agents::Int = 1_000
    initial_active_share::Float64 = 0.8
    buyer_share::Float64 = 0.5
    lambda_exit::Float64 = 0.01
    lambda_entry::Float64 = 0.04
    entry_exit_rho::Float64 = 0.0
    max_endowment::Int = 5
    max_wtp_units::Int = 5
    price_min::Price = 1 // 1
    price_max::Price = 100 // 1
    price_denominator::Int = 100
    ticks_per_period::Int = 1_000
    n_periods::Int = 100
    grain_sizes::Vector{Int} = [10, 50, 100, 500, 1_000, 5_000]
    seed::Int = 1
    transaction_price_rule::Symbol = :midpoint
end

mutable struct Agent
    id::Int
    active::Bool
    role::Symbol
    endowment::Int
    acquired::Int
    sold::Int
    wtp::Vector{Price}
    wta::Vector{Price}
    next_wtp::Int
    next_wta::Int
end

struct TradeRecord
    period::Int
    tick::Int
    global_tick::Int
    buyer_id::Int
    seller_id::Int
    current_wtp::Price
    current_wta::Price
    bid::Price
    ask::Price
    price::Price
    quantity::Int
end

struct EquilibriumRecord
    period::Int
    p_low::Union{Missing,Price}
    p_high::Union{Missing,Price}
    q_star::Int
    active_buyers::Int
    active_sellers::Int
    active_agents::Int
end

struct RenewalRecord
    period::Int
    exits::Int
    entries::Int
    active_before::Int
    active_after::Int
end

struct SimulationResult
    config::MarketConfig
    trades::Vector{TradeRecord}
    equilibria::Vector{EquilibriumRecord}
    renewals::Vector{RenewalRecord}
end

struct CoarseGrainRecord
    grain_size::Int
    window_id::Int
    tick_start::Int
    tick_end::Int
    mean_price::Union{Missing,Price}
    median_price::Union{Missing,Price}
    geo_mean_price::Union{Missing,Float64}
    p_low::Union{Missing,Price}
    p_high::Union{Missing,Price}
    q_star::Union{Missing,Float64}
    interval_error::Union{Missing,Price}
    midpoint_error::Union{Missing,Price}
    n_trades::Int
    active_buyers::Union{Missing,Float64}
    active_sellers::Union{Missing,Float64}
    rho::Float64
    lambda_exit::Float64
    lambda_entry::Float64
    seed::Int
end

struct DiagnosticRecord
    grain_size::Int
    n_windows::Int
    n_valid_windows::Int
    mean_interval_error::Union{Missing,Float64}
    rmse::Union{Missing,Float64}
    recovery_probability::Union{Missing,Float64}
    mean_price_variance::Union{Missing,Float64}
    log_log_slope::Union{Missing,Float64}
end

function validate(config::MarketConfig)
    config.n_agents > 0 || throw(ArgumentError("n_agents must be positive"))
    0.0 <= config.initial_active_share <= 1.0 ||
        throw(ArgumentError("initial_active_share must be in [0, 1]"))
    0.0 <= config.buyer_share <= 1.0 ||
        throw(ArgumentError("buyer_share must be in [0, 1]"))
    config.lambda_exit >= 0.0 || throw(ArgumentError("lambda_exit must be nonnegative"))
    config.lambda_entry >= 0.0 || throw(ArgumentError("lambda_entry must be nonnegative"))
    -1.0 < config.entry_exit_rho < 1.0 ||
        throw(ArgumentError("entry_exit_rho must be strictly between -1 and 1"))
    config.max_endowment > 0 || throw(ArgumentError("max_endowment must be positive"))
    config.max_wtp_units > 0 || throw(ArgumentError("max_wtp_units must be positive"))
    config.price_min > 0 ||
        throw(ArgumentError("price_min must be positive for geometric diagnostics"))
    config.price_max >= config.price_min ||
        throw(ArgumentError("price_max must not be below price_min"))
    config.price_denominator > 0 ||
        throw(ArgumentError("price_denominator must be positive"))
    config.ticks_per_period > 0 ||
        throw(ArgumentError("ticks_per_period must be positive"))
    config.n_periods > 0 || throw(ArgumentError("n_periods must be positive"))
    all(>(0), config.grain_sizes) ||
        throw(ArgumentError("grain_sizes must contain positive integers"))
    config.transaction_price_rule == :midpoint ||
        throw(ArgumentError("version 1 supports only :midpoint pricing"))
    return config
end

default_config(; kwargs...) = MarketConfig(; kwargs...)
