@testset "CSV schemas" begin
    config = default_config(
        n_agents=30,
        ticks_per_period=30,
        n_periods=2,
        grain_sizes=[10],
        seed=14,
    )
    result = run_simulation(config)
    coarse_records = coarse_grain(result)
    diagnostics = summarize_diagnostics(coarse_records)
    mktempdir() do output_dir
        write_results(output_dir, result, coarse_records, diagnostics)
        @test isfile(joinpath(output_dir, "trades.csv"))
        @test isfile(joinpath(output_dir, "equilibria.csv"))
        @test isfile(joinpath(output_dir, "coarse_grain_results.csv"))
        @test isfile(joinpath(output_dir, "diagnostics.csv"))
        coarse = CSV.read(joinpath(output_dir, "coarse_grain_results.csv"), DataFrame)
        required = [
            "grain_size",
            "window_id",
            "mean_price",
            "mean_price_num",
            "mean_price_den",
            "p_low",
            "p_high",
            "interval_error",
            "n_trades",
            "rho",
            "seed",
        ]
        @test all(name -> name in names(coarse), required)
    end
end
