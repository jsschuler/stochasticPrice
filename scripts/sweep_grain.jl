using ZITRenewalMarket

output_dir = isempty(ARGS) ? joinpath(@__DIR__, "..", "outputs", "grain_study") : ARGS[1]
grain_sizes = length(ARGS) < 2 ? [10, 50, 100, 500, 1_000, 5_000, 10_000] :
              parse.(Int, split(ARGS[2], ","))
config = default_config(
    n_agents=1_000,
    ticks_per_period=1_000,
    n_periods=100,
    grain_sizes=grain_sizes,
    seed=20260610,
)

result = run_simulation(config)
coarse_records = coarse_grain(result)
diagnostics = summarize_diagnostics(coarse_records)
write_results(output_dir, result, coarse_records, diagnostics)
make_plots(
    output_dir,
    result,
    coarse_records,
    diagnostics;
    display_grain=grain_sizes[cld(length(grain_sizes), 2)],
)

println("Wrote grain study to $(abspath(output_dir))")
