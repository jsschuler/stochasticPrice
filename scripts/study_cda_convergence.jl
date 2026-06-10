using CSV
using DataFrames
using Distributed
using Plots
using Statistics
using ZITRenewalMarket

output_dir = isempty(ARGS) ? joinpath(@__DIR__, "..", "outputs", "cda_convergence") : ARGS[1]
seeds = [
    20260630,
    20260701,
    20260702,
    20260703,
    20260704,
    20260705,
    20260706,
    20260707,
    20260708,
    20260709,
]
mechanisms = [:bilateral, :cda]
grain_sizes = [10, 100, 1_000, 5_000, 10_000, 25_000, 50_000]
jobs = [(seed=seed, mechanism=mechanism) for mechanism in mechanisms for seed in seeds]
worker_count = min(length(jobs), max(1, Sys.CPU_THREADS - 1))

mkpath(output_dir)

if nworkers() < worker_count
    addprocs(worker_count - nworkers(); exeflags="--project=$(Base.active_project())")
end

@everywhere using Statistics
@everywhere using ZITRenewalMarket

@everywhere function run_mechanism_job(job, grain_sizes)
    config = default_config(
        n_agents=1_000,
        initial_active_share=0.8,
        buyer_share=0.5,
        lambda_exit=0.01,
        lambda_entry=0.04,
        entry_exit_rho=0.0,
        max_endowment=5,
        max_wtp_units=5,
        ticks_per_period=1_000,
        n_periods=500,
        grain_sizes=grain_sizes,
        seed=job.seed,
        transaction_price_rule=job.mechanism == :cda ? :standing : :midpoint,
    )
    result = job.mechanism == :cda ? run_cda_simulation(config) : run_simulation(config)
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
                mechanism=String(job.mechanism),
                grain_size=grain_size,
                n_valid_windows=length(records),
                mean_signed_midpoint_gap=mean(signed_gaps),
                mean_interval_error=mean(interval_errors),
                price_variance=length(records) == 1 ? 0.0 :
                               var(Float64[record.mean_price for record in records]),
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
                trade_count=length(result.trades),
            ),
        )
    end
    valid_equilibria = filter(record -> !ismissing(record.p_low), result.equilibria)
    run_row = (
        seed=job.seed,
        mechanism=String(job.mechanism),
        trade_count=length(result.trades),
        mean_trade_price=mean(Float64(trade.price) for trade in result.trades),
        mean_equilibrium_midpoint=mean(
            Float64((record.p_low + record.p_high) / 2) for record in valid_equilibria
        ),
        mean_q_star=mean(record.q_star for record in valid_equilibria),
    )
    println(
        "Completed $(job.mechanism), seed=$(job.seed): " *
        "$(length(result.trades)) trades",
    )
    return rows, run_row
end

job_results = pmap(job -> run_mechanism_job(job, grain_sizes), jobs)
per_seed = DataFrame(vcat((result[1] for result in job_results)...))
run_summary = DataFrame([result[2] for result in job_results])
sort!(per_seed, [:mechanism, :seed, :grain_size])
sort!(run_summary, [:mechanism, :seed])

summary = combine(
    groupby(per_seed, [:mechanism, :grain_size]),
    :mean_signed_midpoint_gap => mean => :mean_signed_midpoint_gap,
    :mean_signed_midpoint_gap =>
        (values -> std(values) / sqrt(length(values))) => :se_signed_midpoint_gap,
    :mean_interval_error => mean => :mean_interval_error,
    :mean_interval_error =>
        (values -> std(values) / sqrt(length(values))) => :se_interval_error,
    :price_variance => mean => :mean_price_variance,
    :below_probability => mean => :mean_below_probability,
    :inside_probability => mean => :mean_inside_probability,
    :above_probability => mean => :mean_above_probability,
    :n_valid_windows => mean => :mean_valid_windows,
    :trade_count => mean => :mean_trade_count,
    nrow => :n_seeds,
)
sort!(summary, [:mechanism, :grain_size])

run_aggregate = combine(
    groupby(run_summary, :mechanism),
    :trade_count => mean => :mean_trade_count,
    :mean_trade_price => mean => :mean_trade_price,
    :mean_equilibrium_midpoint => mean => :mean_equilibrium_midpoint,
    :mean_q_star => mean => :mean_q_star,
)

CSV.write(joinpath(output_dir, "cda_convergence_per_seed.csv"), per_seed)
CSV.write(joinpath(output_dir, "cda_convergence_summary.csv"), summary)
CSV.write(joinpath(output_dir, "cda_run_summary.csv"), run_summary)
CSV.write(joinpath(output_dir, "cda_run_aggregate.csv"), run_aggregate)

error_plot = plot(
    xlabel="Grain size",
    ylabel="Mean interval error",
    xscale=:log10,
    title="Bilateral vs Continuous Double Auction",
)
bias_plot = plot(
    xlabel="Grain size",
    ylabel="Signed midpoint gap",
    xscale=:log10,
    title="Directional Bias by Market Institution",
)
for mechanism in string.(mechanisms)
    treatment = filter(row -> row.mechanism == mechanism, summary)
    plot!(
        error_plot,
        treatment.grain_size,
        treatment.mean_interval_error;
        ribbon=1.96 .* treatment.se_interval_error,
        marker=:circle,
        label=mechanism,
    )
    plot!(
        bias_plot,
        treatment.grain_size,
        treatment.mean_signed_midpoint_gap;
        ribbon=1.96 .* treatment.se_signed_midpoint_gap,
        marker=:circle,
        label=mechanism,
    )
end
hline!(bias_plot, [0.0]; color=:black, linestyle=:dash, label="No bias")
savefig(error_plot, joinpath(output_dir, "institution_error.png"))
savefig(bias_plot, joinpath(output_dir, "institution_bias.png"))

println("Wrote CDA convergence study to $(abspath(output_dir))")
