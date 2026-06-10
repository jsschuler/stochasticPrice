using CSV
using DataFrames
using Distributed
using Plots
using Statistics
using ZITRenewalMarket

output_dir = isempty(ARGS) ? joinpath(@__DIR__, "..", "outputs", "long_study") : ARGS[1]
seeds = 20260610:20260619
grain_sizes = [10, 50, 100, 500, 1_000, 5_000, 10_000, 25_000, 50_000]
worker_count = min(length(seeds), max(1, Sys.CPU_THREADS - 1))

mkpath(output_dir)

if nworkers() < worker_count
    addprocs(worker_count - nworkers(); exeflags="--project=$(Base.active_project())")
end

@everywhere using Statistics
@everywhere using ZITRenewalMarket

@everywhere function run_seed(seed::Int, grain_sizes::Vector{Int})
    config = default_config(
        n_agents=1_000,
        initial_active_share=0.8,
        buyer_share=0.5,
        lambda_exit=0.01,
        lambda_entry=0.04,
        entry_exit_rho=0.0,
        ticks_per_period=1_000,
        n_periods=500,
        grain_sizes=grain_sizes,
        seed=seed,
    )
    result = run_simulation(config)
    coarse_records = coarse_grain(result)
    diagnostics = summarize_diagnostics(coarse_records)
    active_counts = [record.active_after for record in result.renewals]
    rows = [
        (
            seed=seed,
            grain_size=diagnostic.grain_size,
            n_windows=diagnostic.n_windows,
            n_valid_windows=diagnostic.n_valid_windows,
            mean_interval_error=diagnostic.mean_interval_error,
            rmse=diagnostic.rmse,
            recovery_probability=diagnostic.recovery_probability,
            mean_price_variance=diagnostic.mean_price_variance,
            trade_count=length(result.trades),
            mean_active_agents=mean(active_counts),
            active_agents_sd=std(active_counts),
        ) for diagnostic in diagnostics if !ismissing(diagnostic.mean_interval_error)
    ]
    println("Completed seed $(seed): $(length(result.trades)) trades")
    return rows
end

seed_rows = pmap(seed -> run_seed(seed, grain_sizes), collect(seeds))
per_seed = DataFrame(vcat(seed_rows...))
sort!(per_seed, [:seed, :grain_size])

summary = combine(
    groupby(per_seed, :grain_size),
    :mean_interval_error => mean => :mean_interval_error,
    :mean_interval_error => std => :sd_interval_error,
    :mean_interval_error => (values -> std(values) / sqrt(length(values))) => :se_interval_error,
    :rmse => mean => :mean_rmse,
    :recovery_probability => mean => :mean_recovery_probability,
    :mean_price_variance => mean => :mean_price_variance,
    :n_valid_windows => mean => :mean_valid_windows,
    nrow => :n_seeds,
)
sort!(summary, :grain_size)

positive = summary.mean_interval_error .> 0.0
log_grains = log.(Float64.(summary.grain_size[positive]))
log_errors = log.(summary.mean_interval_error[positive])
aggregate_slope = sum(
    (log_grains .- mean(log_grains)) .* (log_errors .- mean(log_errors)),
) / sum(abs2, log_grains .- mean(log_grains))
summary.aggregate_log_log_slope = fill(aggregate_slope, nrow(summary))

run_summary = combine(
    groupby(per_seed, :seed),
    :trade_count => first => :trade_count,
    :mean_active_agents => first => :mean_active_agents,
    :active_agents_sd => first => :active_agents_sd,
)

CSV.write(joinpath(output_dir, "per_seed_diagnostics.csv"), per_seed)
CSV.write(joinpath(output_dir, "study_summary.csv"), summary)
CSV.write(joinpath(output_dir, "run_summary.csv"), run_summary)

error_plot = plot(
    summary.grain_size,
    summary.mean_interval_error;
    ribbon=1.96 .* summary.se_interval_error,
    marker=:circle,
    xscale=:log10,
    xlabel="Grain size",
    ylabel="Mean interval error",
    label="Cross-seed mean (95% CI)",
    title="Long Study: Error by Grain",
)
savefig(error_plot, joinpath(output_dir, "long_study_error.png"))

log_plot = plot(
    log_grains,
    log_errors;
    marker=:circle,
    xlabel="log grain size",
    ylabel="log mean interval error",
    label="Cross-seed mean",
    title="Long Study: Log Error by Log Grain",
)
intercept = mean(log_errors) - aggregate_slope * mean(log_grains)
plot!(
    log_plot,
    log_grains,
    intercept .+ aggregate_slope .* log_grains;
    label="OLS slope=$(round(aggregate_slope; digits=3))",
)
savefig(log_plot, joinpath(output_dir, "long_study_log_error.png"))

println("Wrote long-study results to $(abspath(output_dir))")
println("Aggregate log-log slope: $(round(aggregate_slope; digits=4))")
