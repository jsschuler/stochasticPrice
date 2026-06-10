function save_plot(plot_object, output_dir::AbstractString, filename::AbstractString)
    path = joinpath(output_dir, filename)
    savefig(plot_object, path)
    return path
end

function make_plots(
    output_dir::AbstractString,
    result::SimulationResult,
    coarse_records::Vector{CoarseGrainRecord},
    diagnostics::Vector{DiagnosticRecord};
    display_grain::Int=first(sort(unique(record.grain_size for record in coarse_records))),
)
    mkpath(output_dir)
    paths = String[]

    trade_ticks = [trade.global_tick for trade in result.trades]
    trade_prices = Float64[trade.price for trade in result.trades]
    transaction_plot = scatter(
        trade_ticks,
        trade_prices;
        markersize=1.5,
        markerstrokewidth=0,
        alpha=0.5,
        label="Transactions",
        xlabel="Global tick",
        ylabel="Price",
        title="Transaction Prices and Equilibrium Interval",
    )
    period_ticks = [
        (record.period - 0.5) * result.config.ticks_per_period for
        record in result.equilibria if !ismissing(record.p_low)
    ]
    lower = Float64[
        record.p_low for record in result.equilibria if !ismissing(record.p_low)
    ]
    upper = Float64[
        record.p_high for record in result.equilibria if !ismissing(record.p_high)
    ]
    plot!(
        transaction_plot,
        period_ticks,
        lower;
        fillrange=upper,
        fillalpha=0.15,
        label="Equilibrium interval",
        linewidth=2,
    )
    plot!(transaction_plot, period_ticks, upper; label="", linewidth=2)
    push!(paths, save_plot(transaction_plot, output_dir, "transaction_prices.png"))

    selected = filter(
        record ->
            record.grain_size == display_grain &&
                !ismissing(record.mean_price) &&
                !ismissing(record.p_low),
        coarse_records,
    )
    centers = [(record.tick_start + record.tick_end) / 2 for record in selected]
    coarse_plot = plot(
        centers,
        Float64[record.mean_price for record in selected];
        label="Mean price",
        xlabel="Global tick",
        ylabel="Price",
        title="Coarse Prices (G=$(display_grain))",
    )
    coarse_lower = Float64[record.p_low for record in selected]
    coarse_upper = Float64[record.p_high for record in selected]
    plot!(
        coarse_plot,
        centers,
        coarse_lower;
        fillrange=coarse_upper,
        fillalpha=0.15,
        label="Equilibrium interval",
    )
    plot!(coarse_plot, centers, coarse_upper; label="")
    push!(paths, save_plot(coarse_plot, output_dir, "coarse_prices.png"))

    valid_diagnostics = filter(
        record -> !ismissing(record.mean_interval_error),
        diagnostics,
    )
    grains = [record.grain_size for record in valid_diagnostics]
    errors = Float64[record.mean_interval_error for record in valid_diagnostics]
    error_plot = plot(
        grains,
        errors;
        marker=:circle,
        label="Mean interval error",
        xlabel="Grain size",
        ylabel="Error",
        title="Error by Grain Size",
    )
    push!(paths, save_plot(error_plot, output_dir, "error_by_grain.png"))

    positive = findall(>(0.0), errors)
    log_plot = plot(
        log.(Float64.(grains[positive])),
        log.(errors[positive]);
        marker=:circle,
        label="Observed",
        xlabel="log grain size",
        ylabel="log error",
        title="Log Error by Log Grain Size",
    )
    if length(positive) >= 2
        slope = valid_diagnostics[first(positive)].log_log_slope
        if !ismissing(slope)
            x = log.(Float64.(grains[positive]))
            intercept = mean(log.(errors[positive])) - slope * mean(x)
            plot!(log_plot, x, intercept .+ slope .* x; label="OLS slope=$(round(slope; digits=3))")
        end
    end
    push!(paths, save_plot(log_plot, output_dir, "log_error_by_log_grain.png"))

    renewal_periods = [record.period for record in result.renewals]
    active_plot = plot(
        renewal_periods,
        [record.active_after for record in result.renewals];
        label="Active agents",
        xlabel="Period",
        ylabel="Count",
        title="Active Population",
    )
    push!(paths, save_plot(active_plot, output_dir, "active_population.png"))

    renewal_plot = plot(
        renewal_periods,
        [record.exits for record in result.renewals];
        label="Exits",
        xlabel="Period",
        ylabel="Count",
        title="Entry and Exit Counts",
    )
    plot!(
        renewal_plot,
        renewal_periods,
        [record.entries for record in result.renewals];
        label="Entries",
    )
    push!(paths, save_plot(renewal_plot, output_dir, "renewal_counts.png"))
    return paths
end
