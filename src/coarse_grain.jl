exact_mean(values::Vector{Price}) = sum(values; init=0 // 1) / length(values)

function exact_median(values::Vector{Price})
    ordered = sort(values)
    middle = length(ordered) ÷ 2
    return isodd(length(ordered)) ? ordered[middle + 1] :
           (ordered[middle] + ordered[middle + 1]) / 2
end

function interval_distance(
    price::Price,
    p_low::Price,
    p_high::Price,
)
    price < p_low && return p_low - price
    price > p_high && return price - p_high
    return 0 // 1
end

function overlap_length(start_a::Int, end_a::Int, start_b::Int, end_b::Int)
    return max(0, min(end_a, end_b) - max(start_a, start_b) + 1)
end

function window_benchmark(
    equilibria::Vector{EquilibriumRecord},
    config::MarketConfig,
    tick_start::Int,
    tick_end::Int,
)
    total_weight = 0
    low_sum = 0 // 1
    high_sum = 0 // 1
    q_sum = 0.0
    buyer_sum = 0.0
    seller_sum = 0.0
    for equilibrium in equilibria
        period_start = (equilibrium.period - 1) * config.ticks_per_period + 1
        period_end = equilibrium.period * config.ticks_per_period
        weight = overlap_length(tick_start, tick_end, period_start, period_end)
        weight == 0 && continue
        (ismissing(equilibrium.p_low) || ismissing(equilibrium.p_high)) && continue
        total_weight += weight
        low_sum += weight * equilibrium.p_low
        high_sum += weight * equilibrium.p_high
        q_sum += weight * equilibrium.q_star
        buyer_sum += weight * equilibrium.active_buyers
        seller_sum += weight * equilibrium.active_sellers
    end
    total_weight == 0 &&
        return (missing, missing, missing, missing, missing)
    return (
        low_sum / total_weight,
        high_sum / total_weight,
        q_sum / total_weight,
        buyer_sum / total_weight,
        seller_sum / total_weight,
    )
end

function coarse_grain(
    result::SimulationResult;
    grain_sizes::Vector{Int}=result.config.grain_sizes,
)
    all(>(0), grain_sizes) || throw(ArgumentError("grain sizes must be positive"))
    total_ticks = result.config.n_periods * result.config.ticks_per_period
    records = CoarseGrainRecord[]
    for grain_size in sort(unique(grain_sizes))
        n_windows = cld(total_ticks, grain_size)
        for window_id in 1:n_windows
            tick_start = (window_id - 1) * grain_size + 1
            tick_end = min(window_id * grain_size, total_ticks)
            window_trades = filter(
                trade -> tick_start <= trade.global_tick <= tick_end,
                result.trades,
            )
            prices = Price[trade.price for trade in window_trades]
            mean_price = isempty(prices) ? missing : exact_mean(prices)
            median_price = isempty(prices) ? missing : exact_median(prices)
            geo_mean_price = isempty(prices) ? missing :
                             exp(mean(log(Float64(price)) for price in prices))
            p_low, p_high, q_star, active_buyers, active_sellers =
                window_benchmark(
                    result.equilibria,
                    result.config,
                    tick_start,
                    tick_end,
                )
            if ismissing(mean_price) || ismissing(p_low) || ismissing(p_high)
                interval_error = missing
                midpoint_error = missing
            else
                interval_error = interval_distance(mean_price, p_low, p_high)
                midpoint_error = abs(mean_price - (p_low + p_high) / 2)
            end
            push!(
                records,
                CoarseGrainRecord(
                    grain_size,
                    window_id,
                    tick_start,
                    tick_end,
                    mean_price,
                    median_price,
                    geo_mean_price,
                    p_low,
                    p_high,
                    q_star,
                    interval_error,
                    midpoint_error,
                    length(window_trades),
                    active_buyers,
                    active_sellers,
                    result.config.entry_exit_rho,
                    result.config.lambda_exit,
                    result.config.lambda_entry,
                    result.config.seed,
                ),
            )
        end
    end
    return records
end
