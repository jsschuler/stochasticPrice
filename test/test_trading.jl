@testset "Trading and reproducibility" begin
    config = default_config(
        n_agents=80,
        initial_active_share=1.0,
        lambda_exit=0.0,
        lambda_entry=0.0,
        ticks_per_period=200,
        n_periods=3,
        grain_sizes=[20, 100],
        seed=77,
    )
    first_result = run_simulation(config)
    second_result = run_simulation(config)
    first_signature = [
        (trade.global_tick, trade.buyer_id, trade.seller_id, trade.price) for
        trade in first_result.trades
    ]
    second_signature = [
        (trade.global_tick, trade.buyer_id, trade.seller_id, trade.price) for
        trade in second_result.trades
    ]
    @test first_signature == second_signature
    @test !isempty(first_result.trades)

    for trade in first_result.trades
        @test trade.quantity == 1
        @test trade.price isa Rational
        @test trade.current_wta <= trade.ask <= trade.price <= trade.bid <= trade.current_wtp
    end
end
