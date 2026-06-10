using CSV
using DataFrames
using Distributed
using Plots
using Statistics
using ZITRenewalMarket

output_dir = isempty(ARGS) ? joinpath(@__DIR__, "..", "outputs", "population_renewal") : ARGS[1]
seeds = collect(20260620:20260624)
agent_counts = [1_000, 5_000, 10_000]
renewal_treatments = [
    (label="1x", lambda_exit=0.01, lambda_entry=0.04),
    (label="5x", lambda_exit=0.05, lambda_entry=0.20),
    (label="10x", lambda_exit=0.10, lambda_entry=0.40),
]
grain_sizes = [100, 1_000, 5_000, 10_000, 20_000]
jobs = [
    (
        seed=seed,
        n_agents=n_agents,
        renewal_label=renewal.label,
        lambda_exit=renewal.lambda_exit,
        lambda_entry=renewal.lambda_entry,
    ) for n_agents in agent_counts for renewal in renewal_treatments for seed in seeds
]
worker_count = min(length(jobs), max(1, Sys.CPU_THREADS - 1))

mkpath(output_dir)

if nworkers() < worker_count
    addprocs(worker_count - nworkers(); exeflags="--project=$(Base.active_project())")
end

@everywhere using Statistics
@everywhere using ZITRenewalMarket

@everywhere function run_population_renewal_job(job, grain_sizes)
    config = default_config(
        n_agents=job.n_agents,
        initial_active_share=0.8,
        buyer_share=0.5,
        lambda_exit=job.lambda_exit,
        lambda_entry=job.lambda_entry,
        entry_exit_rho=0.0,
        max_endowment=5,
        max_wtp_units=3,
        ticks_per_period=1_000,
        n_periods=200,
        grain_sizes=grain_sizes,
        seed=job.seed,
    )
    result = run_simulation(config)
    coarse_records = coarse_grain(result)
    active_counts = [record.active_after for record in result.renewals]
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
                n_agents=job.n_agents,
                renewal_label=job.renewal_label,
                lambda_exit=job.lambda_exit,
                lambda_entry=job.lambda_entry,
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
                mean_active_agents=mean(active_counts),
                active_agents_sd=std(active_counts),
            ),
        )
    end
    println(
        "Completed N=$(job.n_agents), renewal=$(job.renewal_label), " *
        "seed=$(job.seed): $(length(result.trades)) trades",
    )
    return rows
end

job_rows = pmap(job -> run_population_renewal_job(job, grain_sizes), jobs)
per_seed = DataFrame(vcat(job_rows...))
sort!(per_seed, [:n_agents, :renewal_label, :seed, :grain_size])

summary = combine(
    groupby(per_seed, [:n_agents, :renewal_label, :lambda_exit, :lambda_entry, :grain_size]),
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
    :mean_active_agents => mean => :mean_active_agents,
    :active_agents_sd => mean => :mean_active_agents_sd,
    nrow => :n_seeds,
)
sort!(summary, [:n_agents, :renewal_label, :grain_size])

CSV.write(joinpath(output_dir, "population_renewal_per_seed.csv"), per_seed)
CSV.write(joinpath(output_dir, "population_renewal_summary.csv"), summary)

error_plot = plot(
    xlabel="Grain size",
    ylabel="Mean interval error",
    xscale=:log10,
    title="Population and Renewal Effects on Error",
)
for n_agents in agent_counts
    for renewal in renewal_treatments
        treatment = filter(
            row ->
                row.n_agents == n_agents &&
                    row.renewal_label == renewal.label,
            summary,
        )
        plot!(
            error_plot,
            treatment.grain_size,
            treatment.mean_interval_error;
            marker=:circle,
            label="N=$(n_agents), $(renewal.label)",
        )
    end
end
savefig(error_plot, joinpath(output_dir, "error_by_population_renewal.png"))

largest_grain = maximum(grain_sizes)
endpoint = filter(row -> row.grain_size == largest_grain, summary)
endpoint_plot = plot(
    xlabel="Agents",
    ylabel="Mean interval error",
    xscale=:log10,
    title="Error at Grain $(largest_grain)",
)
for renewal in renewal_treatments
    treatment = filter(row -> row.renewal_label == renewal.label, endpoint)
    plot!(
        endpoint_plot,
        treatment.n_agents,
        treatment.mean_interval_error;
        marker=:circle,
        label=renewal.label,
    )
end
savefig(endpoint_plot, joinpath(output_dir, "endpoint_error.png"))

println("Wrote population-renewal study to $(abspath(output_dir))")
