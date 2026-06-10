@testset "Renewal process" begin
    config = default_config(
        n_agents=200,
        initial_active_share=0.5,
        lambda_exit=0.05,
        lambda_entry=0.05,
        entry_exit_rho=0.0,
        seed=8,
    )
    rng = MersenneTwister(8)
    draws = [draw_entry_exit_counts(100, 100, config, rng) for _ in 1:10_000]
    exits = Float64[first(draw) for draw in draws]
    entries = Float64[last(draw) for draw in draws]
    @test abs(cor(exits, entries)) < 0.04

    agents = initialize_agents(config, MersenneTwister(12))
    inactive_id = findfirst(agent -> !agent.active, agents)
    agent = agents[inactive_id]
    agent.acquired = 9
    agent.sold = 9
    agent.endowment = 0
    empty!(agent.wtp)
    empty!(agent.wta)
    selected = apply_entries!(
        agents,
        1,
        config,
        MersenneTwister(13);
        eligible_ids=[inactive_id],
    )
    @test selected == [inactive_id]
    @test agent.active
    @test agent.acquired == 0
    @test agent.sold == 0
    if agent.role == :buyer
        @test length(agent.wtp) == config.max_wtp_units
        @test agent.endowment == 0
    else
        @test 1 <= agent.endowment <= config.max_endowment
        @test length(agent.wta) == agent.endowment
    end
end
