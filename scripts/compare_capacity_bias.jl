using CSV
using DataFrames
using Distributed
using Plots
using Statistics
using ZITRenewalMarket

output_dir = isempty(ARGS) ? joinpath(@__DIR__, "..", "outputs", "capacity_bias") : ARGS[1]
seeds = collect(20260610:20260619)
buyer_unit_treatments = [3, 5]
grain_sizes = [10, 100, 1_000, 5_000, 10_000, 50_000]
jobs = [(seed=seed, buyer_units=units) for units in buyer_unit_treatments for seed in seeds]
worker_count = min(length(jobs), max(1, Sys.CPU_THREADS - 1))

mkpath(output_dir)

if nworkers() < worker_count
    addprocs(worker_count - nworkers(); exeflags="--project=$(Base.active_project())")
end

@everywhere using Statistics
@everywhere using ZITRenewalMarket

@everywhere function run_capacity_job(job, grain_sizes)
    config = default_config(
        n_agents=1_000,
        initial_active_share=0.8,
        buyer_share=0.5,
        lambda_exit=0.01,
        lambda_entry=0.04,
        entry_exit_rho=0.0,
        max_endowment=5,
        max_wtp_units=job.buyer_units,
        ticks_per_period=1_000,
        n_periods=500,
        grain_sizes=grain_sizes,
        seed=job.seed,
    )
    result = run_simulation(config)
    coarse_records = coarse_grain(result)
    rows = NamedTuple[]
    for grain_size in grain_sizes
        records = filter(
            record ->
                record.grain_size == grain_size &&
                    !ismissing(record.mean_price) &&
                    !ismissing(record.p_low) &&
                    !ismissing(record.p_high),
            coarse_records,
        )
        signed_gaps = Float64[
            record.mean_price - (record.p_low + record.p_high) / 2 for
            record in records
        ]
        interval_errors = Float64[record.interval_error for record in records]
        push!(
            rows,
            (
                seed=job.seed,
                buyer_units=job.buyer_units,
                grain_size=grain_size,
                n_valid_windows=length(records),
                mean_signed_midpoint_gap=mean(signed_gaps),
                mean_interval_error=mean(interval_errors),
                below_probability=mean(
                    record.mean_price < record.p_low for record in records
                ),
                inside_probability=mean(
                    record.p_low <= record.mean_price <= record.p_high for
                    record in records
                ),
                above_probability=mean(
                    record.mean_price > record.p_high for record in records
                ),
            ),
        )
    end
    valid_equilibria = filter(record -> !ismissing(record.p_low), result.equilibria)
    run_row = (
        seed=job.seed,
        buyer_units=job.buyer_units,
        trade_count=length(result.trades),
        mean_trade_price=mean(Float64(trade.price) for trade in result.trades),
        mean_equilibrium_midpoint=mean(
            Float64((record.p_low + record.p_high) / 2) for record in valid_equilibria
        ),
        mean_q_star=mean(record.q_star for record in valid_equilibria),
    )
    println(
        "Completed buyer_units=$(job.buyer_units), seed=$(job.seed): " *
        "$(length(result.trades)) trades",
    )
    return rows, run_row
end

job_results = pmap(job -> run_capacity_job(job, grain_sizes), jobs)
per_seed = DataFrame(vcat((result[1] for result in job_results)...))
run_summary = DataFrame([result[2] for result in job_results])
sort!(per_seed, [:buyer_units, :seed, :grain_size])
sort!(run_summary, [:buyer_units, :seed])

summary = combine(
    groupby(per_seed, [:buyer_units, :grain_size]),
    :mean_signed_midpoint_gap => mean => :mean_signed_midpoint_gap,
    :mean_signed_midpoint_gap =>
        (values -> std(values) / sqrt(length(values))) => :se_signed_midpoint_gap,
    :mean_interval_error => mean => :mean_interval_error,
    :mean_interval_error =>
        (values -> std(values) / sqrt(length(values))) => :se_interval_error,
    :below_probability => mean => :mean_below_probability,
    :inside_probability => mean => :mean_inside_probability,
    :above_probability => mean => :mean_above_probability,
    :n_valid_windows => mean => :mean_valid_windows,
    nrow => :n_seeds,
)
sort!(summary, [:buyer_units, :grain_size])

run_aggregate = combine(
    groupby(run_summary, :buyer_units),
    :trade_count => mean => :mean_trade_count,
    :mean_trade_price => mean => :mean_trade_price,
    :mean_equilibrium_midpoint => mean => :mean_equilibrium_midpoint,
    :mean_q_star => mean => :mean_q_star,
)

CSV.write(joinpath(output_dir, "per_seed_capacity_bias.csv"), per_seed)
CSV.write(joinpath(output_dir, "capacity_bias_summary.csv"), summary)
CSV.write(joinpath(output_dir, "capacity_run_summary.csv"), run_summary)
CSV.write(joinpath(output_dir, "capacity_run_aggregate.csv"), run_aggregate)

bias_plot = plot(
    xlabel="Grain size",
    ylabel="Signed midpoint gap",
    xscale=:log10,
    title="Capacity Balance and Signed Price Bias",
)
for units in buyer_unit_treatments
    treatment = filter(row -> row.buyer_units == units, summary)
    plot!(
        bias_plot,
        treatment.grain_size,
        treatment.mean_signed_midpoint_gap;
        ribbon=1.96 .* treatment.se_signed_midpoint_gap,
        marker=:circle,
        label="$(units) buyer units",
    )
end
hline!(bias_plot, [0.0]; color=:black, linestyle=:dash, label="No bias")
savefig(bias_plot, joinpath(output_dir, "signed_bias_by_capacity.png"))

error_plot = plot(
    xlabel="Grain size",
    ylabel="Mean interval error",
    xscale=:log10,
    title="Capacity Balance and Interval Error",
)
for units in buyer_unit_treatments
    treatment = filter(row -> row.buyer_units == units, summary)
    plot!(
        error_plot,
        treatment.grain_size,
        treatment.mean_interval_error;
        ribbon=1.96 .* treatment.se_interval_error,
        marker=:circle,
        label="$(units) buyer units",
    )
end
savefig(error_plot, joinpath(output_dir, "interval_error_by_capacity.png"))

println("Wrote capacity-bias study to $(abspath(output_dir))")
