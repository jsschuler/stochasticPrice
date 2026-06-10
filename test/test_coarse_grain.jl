@testset "Tick coarse graining and diagnostics" begin
    config = default_config(
        n_agents=2,
        ticks_per_period=4,
        n_periods=2,
        grain_sizes=[2, 4, 8],
    )
    trades = TradeRecord[
        TradeRecord(1, 1, 1, 1, 2, 6 // 1, 4 // 1, 6 // 1, 4 // 1, 5 // 1, 1),
        TradeRecord(1, 4, 4, 1, 2, 8 // 1, 6 // 1, 8 // 1, 6 // 1, 7 // 1, 1),
        TradeRecord(2, 1, 5, 1, 2, 10 // 1, 8 // 1, 10 // 1, 8 // 1, 9 // 1, 1),
    ]
    equilibria = EquilibriumRecord[
        EquilibriumRecord(1, 4 // 1, 6 // 1, 1, 1, 1, 2),
        EquilibriumRecord(2, 8 // 1, 10 // 1, 1, 1, 1, 2),
    ]
    result = SimulationResult(config, trades, equilibria, RenewalRecord[])
    records = coarse_grain(result)

    grain_four = filter(record -> record.grain_size == 4, records)
    @test length(grain_four) == 2
    @test grain_four[1].tick_start == 1
    @test grain_four[1].tick_end == 4
    @test grain_four[1].mean_price == 6 // 1
    @test grain_four[1].median_price == 6 // 1
    @test grain_four[1].interval_error == 0 // 1
    @test grain_four[2].mean_price == 9 // 1

    grain_eight = only(filter(record -> record.grain_size == 8, records))
    @test grain_eight.mean_price == 7 // 1
    @test grain_eight.p_low == 6 // 1
    @test grain_eight.p_high == 8 // 1
    @test grain_eight.interval_error == 0 // 1

    no_trade_window = records[findfirst(
        record -> record.grain_size == 2 && record.window_id == 4,
        records,
    )]
    @test no_trade_window.n_trades == 0
    @test ismissing(no_trade_window.mean_price)
    @test ismissing(no_trade_window.interval_error)

    function diagnostic_fixture(grain_size, window_id, error)
        return CoarseGrainRecord(
            grain_size,
            window_id,
            window_id,
            window_id,
            5 // 1,
            5 // 1,
            5.0,
            4 // 1,
            6 // 1,
            1.0,
            error,
            error,
            1,
            1.0,
            1.0,
            0.0,
            0.0,
            0.0,
            1,
        )
    end
    controlled = [
        diagnostic_fixture(1, 1, 2 // 1),
        diagnostic_fixture(2, 1, 1 // 1),
        diagnostic_fixture(4, 1, 1 // 2),
    ]
    diagnostics = summarize_diagnostics(controlled)
    @test [record.mean_interval_error for record in diagnostics] == [2.0, 1.0, 0.5]
    @test diagnostics[1].log_log_slope ≈ -1.0
end
