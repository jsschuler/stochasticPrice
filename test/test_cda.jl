@testset "Continuous double auction" begin
    book = OrderBook()
    ZITRenewalMarket.submit_order!(book, 1, :bid, 5 // 1)
    ZITRenewalMarket.submit_order!(book, 2, :bid, 6 // 1)
    ZITRenewalMarket.submit_order!(book, 3, :bid, 6 // 1)
    agents = Agent[
        Agent(1, true, :buyer, 0, 0, 0, [10 // 1], Rational{Int}[], 1, 1),
        Agent(2, true, :buyer, 0, 0, 0, [10 // 1], Rational{Int}[], 1, 1),
        Agent(3, true, :buyer, 0, 0, 0, [10 // 1], Rational{Int}[], 1, 1),
    ]
    @test ZITRenewalMarket.best_bid!(book, agents).agent_id == 2
    ZITRenewalMarket.submit_order!(book, 2, :bid, 4 // 1)
    @test ZITRenewalMarket.best_bid!(book, agents).agent_id == 3

    config = default_config(
        n_agents=100,
        initial_active_share=1.0,
        lambda_exit=0.02,
        lambda_entry=0.08,
        ticks_per_period=300,
        n_periods=4,
        max_wtp_units=5,
        transaction_price_rule=:standing,
        seed=91,
    )
    first_result = run_cda_simulation(config)
    second_result = run_cda_simulation(config)
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
        @test trade.current_wta <= trade.ask <= trade.price <= trade.bid <= trade.current_wtp
        @test trade.price == trade.ask || trade.price == trade.bid
        @test trade.quantity == 1
    end
end
