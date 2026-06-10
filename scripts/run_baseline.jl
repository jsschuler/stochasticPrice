using ZITRenewalMarket

output_dir = isempty(ARGS) ? joinpath(@__DIR__, "..", "outputs", "baseline") : ARGS[1]
config = default_config(
    n_agents=1_000,
    initial_active_share=0.8,
    buyer_share=0.5,
    lambda_exit=0.01,
    lambda_entry=0.04,
    entry_exit_rho=0.0,
    ticks_per_period=1_000,
    n_periods=100,
    grain_sizes=[10, 50, 100, 500, 1_000, 5_000, 10_000],
    seed=20260610,
)

result = run_simulation(config)
coarse_records = coarse_grain(result)
diagnostics = summarize_diagnostics(coarse_records)
write_results(output_dir, result, coarse_records, diagnostics)
make_plots(output_dir, result, coarse_records, diagnostics; display_grain=1_000)

println("Wrote baseline results to $(abspath(output_dir))")
println("Trades: $(length(result.trades))")
