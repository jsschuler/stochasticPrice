decimal(value) = ismissing(value) ? missing : Float64(value)
exact_numerator(value) = ismissing(value) ? missing : numerator(value)
exact_denominator(value) = ismissing(value) ? missing : denominator(value)

function trade_dataframe(trades::Vector{TradeRecord})
    return DataFrame(
        period=[trade.period for trade in trades],
        tick=[trade.tick for trade in trades],
        global_tick=[trade.global_tick for trade in trades],
        buyer_id=[trade.buyer_id for trade in trades],
        seller_id=[trade.seller_id for trade in trades],
        current_wtp=[Float64(trade.current_wtp) for trade in trades],
        current_wtp_num=[numerator(trade.current_wtp) for trade in trades],
        current_wtp_den=[denominator(trade.current_wtp) for trade in trades],
        current_wta=[Float64(trade.current_wta) for trade in trades],
        current_wta_num=[numerator(trade.current_wta) for trade in trades],
        current_wta_den=[denominator(trade.current_wta) for trade in trades],
        bid=[Float64(trade.bid) for trade in trades],
        bid_num=[numerator(trade.bid) for trade in trades],
        bid_den=[denominator(trade.bid) for trade in trades],
        ask=[Float64(trade.ask) for trade in trades],
        ask_num=[numerator(trade.ask) for trade in trades],
        ask_den=[denominator(trade.ask) for trade in trades],
        price=[Float64(trade.price) for trade in trades],
        price_num=[numerator(trade.price) for trade in trades],
        price_den=[denominator(trade.price) for trade in trades],
        quantity=[trade.quantity for trade in trades],
    )
end

function equilibrium_dataframe(equilibria::Vector{EquilibriumRecord})
    return DataFrame(
        period=[record.period for record in equilibria],
        p_low=[decimal(record.p_low) for record in equilibria],
        p_low_num=[exact_numerator(record.p_low) for record in equilibria],
        p_low_den=[exact_denominator(record.p_low) for record in equilibria],
        p_high=[decimal(record.p_high) for record in equilibria],
        p_high_num=[exact_numerator(record.p_high) for record in equilibria],
        p_high_den=[exact_denominator(record.p_high) for record in equilibria],
        q_star=[record.q_star for record in equilibria],
        active_buyers=[record.active_buyers for record in equilibria],
        active_sellers=[record.active_sellers for record in equilibria],
        active_agents=[record.active_agents for record in equilibria],
    )
end

function renewal_dataframe(renewals::Vector{RenewalRecord})
    return DataFrame(
        period=[record.period for record in renewals],
        exits=[record.exits for record in renewals],
        entries=[record.entries for record in renewals],
        active_before=[record.active_before for record in renewals],
        active_after=[record.active_after for record in renewals],
    )
end

function coarse_dataframe(records::Vector{CoarseGrainRecord})
    return DataFrame(
        grain_size=[record.grain_size for record in records],
        window_id=[record.window_id for record in records],
        tick_start=[record.tick_start for record in records],
        tick_end=[record.tick_end for record in records],
        mean_price=[decimal(record.mean_price) for record in records],
        mean_price_num=[exact_numerator(record.mean_price) for record in records],
        mean_price_den=[exact_denominator(record.mean_price) for record in records],
        median_price=[decimal(record.median_price) for record in records],
        median_price_num=[exact_numerator(record.median_price) for record in records],
        median_price_den=[exact_denominator(record.median_price) for record in records],
        geo_mean_price=[record.geo_mean_price for record in records],
        p_low=[decimal(record.p_low) for record in records],
        p_low_num=[exact_numerator(record.p_low) for record in records],
        p_low_den=[exact_denominator(record.p_low) for record in records],
        p_high=[decimal(record.p_high) for record in records],
        p_high_num=[exact_numerator(record.p_high) for record in records],
        p_high_den=[exact_denominator(record.p_high) for record in records],
        q_star=[record.q_star for record in records],
        interval_error=[decimal(record.interval_error) for record in records],
        interval_error_num=[exact_numerator(record.interval_error) for record in records],
        interval_error_den=[exact_denominator(record.interval_error) for record in records],
        midpoint_error=[decimal(record.midpoint_error) for record in records],
        midpoint_error_num=[exact_numerator(record.midpoint_error) for record in records],
        midpoint_error_den=[exact_denominator(record.midpoint_error) for record in records],
        n_trades=[record.n_trades for record in records],
        active_buyers=[record.active_buyers for record in records],
        active_sellers=[record.active_sellers for record in records],
        rho=[record.rho for record in records],
        lambda_exit=[record.lambda_exit for record in records],
        lambda_entry=[record.lambda_entry for record in records],
        seed=[record.seed for record in records],
    )
end

diagnostic_dataframe(records::Vector{DiagnosticRecord}) = DataFrame(
    grain_size=[record.grain_size for record in records],
    n_windows=[record.n_windows for record in records],
    n_valid_windows=[record.n_valid_windows for record in records],
    mean_interval_error=[record.mean_interval_error for record in records],
    rmse=[record.rmse for record in records],
    recovery_probability=[record.recovery_probability for record in records],
    mean_price_variance=[record.mean_price_variance for record in records],
    log_log_slope=[record.log_log_slope for record in records],
)

function write_results(
    output_dir::AbstractString,
    result::SimulationResult,
    coarse_records::Vector{CoarseGrainRecord},
    diagnostics::Vector{DiagnosticRecord},
)
    mkpath(output_dir)
    CSV.write(joinpath(output_dir, "trades.csv"), trade_dataframe(result.trades))
    CSV.write(
        joinpath(output_dir, "equilibria.csv"),
        equilibrium_dataframe(result.equilibria),
    )
    CSV.write(
        joinpath(output_dir, "renewals.csv"),
        renewal_dataframe(result.renewals),
    )
    CSV.write(
        joinpath(output_dir, "coarse_grain_results.csv"),
        coarse_dataframe(coarse_records),
    )
    CSV.write(
        joinpath(output_dir, "diagnostics.csv"),
        diagnostic_dataframe(diagnostics),
    )
    return output_dir
end
