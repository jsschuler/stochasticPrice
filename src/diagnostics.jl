function regression_slope(x::Vector{Float64}, y::Vector{Float64})
    length(x) >= 2 || return missing
    x_centered = x .- mean(x)
    denominator = sum(abs2, x_centered)
    denominator == 0.0 && return missing
    return sum(x_centered .* (y .- mean(y))) / denominator
end

function summarize_diagnostics(records::Vector{CoarseGrainRecord})
    grain_sizes = sort(unique(record.grain_size for record in records))
    metrics = NamedTuple[]
    for grain_size in grain_sizes
        grain_records = filter(record -> record.grain_size == grain_size, records)
        valid = filter(
            record -> !ismissing(record.interval_error) && !ismissing(record.mean_price),
            grain_records,
        )
        errors = Float64[record.interval_error for record in valid]
        prices = Float64[record.mean_price for record in valid]
        mean_error = isempty(errors) ? missing : mean(errors)
        rmse = isempty(errors) ? missing : sqrt(mean(abs2, errors))
        recovery = isempty(errors) ? missing : mean(iszero, errors)
        price_variance = isempty(prices) ? missing :
                         length(prices) == 1 ? 0.0 : var(prices)
        push!(
            metrics,
            (
                grain_size=grain_size,
                n_windows=length(grain_records),
                n_valid_windows=length(valid),
                mean_interval_error=mean_error,
                rmse=rmse,
                recovery_probability=recovery,
                mean_price_variance=price_variance,
            ),
        )
    end

    positive = filter(
        metric ->
            !ismissing(metric.mean_interval_error) &&
                metric.mean_interval_error > 0.0,
        metrics,
    )
    slope = regression_slope(
        log.(Float64[metric.grain_size for metric in positive]),
        log.(Float64[metric.mean_interval_error for metric in positive]),
    )
    return DiagnosticRecord[
        DiagnosticRecord(
            metric.grain_size,
            metric.n_windows,
            metric.n_valid_windows,
            metric.mean_interval_error,
            metric.rmse,
            metric.recovery_probability,
            metric.mean_price_variance,
            slope,
        ) for metric in metrics
    ]
end
