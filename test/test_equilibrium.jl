@testset "Discrete equilibrium" begin
    agents = Agent[
        Agent(1, true, :buyer, 0, 0, 0, [9, 7, 5, 3, 1] .// 1, Rational{Int}[], 1, 1),
        Agent(2, true, :buyer, 0, 0, 0, [8, 6, 4, 2] .// 1, Rational{Int}[], 1, 1),
        Agent(3, true, :seller, 4, 0, 0, Rational{Int}[], [2, 4, 6, 8] .// 1, 1, 1),
        Agent(4, true, :seller, 4, 0, 0, Rational{Int}[], [1, 3, 5, 7] .// 1, 1, 1),
    ]
    equilibrium = compute_equilibrium(agents, 1)
    @test equilibrium.q_star == 5
    @test equilibrium.p_low == 5 // 1
    @test equilibrium.p_high == 5 // 1

    agents[1].next_wtp = length(agents[1].wtp) + 1
    agents[2].next_wtp = length(agents[2].wtp) + 1
    no_trade = compute_equilibrium(agents, 2)
    @test no_trade.q_star == 0
    @test ismissing(no_trade.p_low)
    @test ismissing(no_trade.p_high)
end
