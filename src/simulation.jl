function run_simulation(config::MarketConfig)
    validate(config)
    rng = MersenneTwister(config.seed)
    agents = initialize_agents(config, rng)
    trades = TradeRecord[]
    equilibria = EquilibriumRecord[]
    renewals = RenewalRecord[]

    for period in 1:config.n_periods
        active_before = count(agent -> agent.active, agents)
        inactive_at_start = findall(agent -> !agent.active, agents)
        exits, entries = draw_entry_exit_counts(
            active_before,
            length(inactive_at_start),
            config,
            rng,
        )
        apply_exits!(agents, exits, rng)
        apply_entries!(
            agents,
            entries,
            config,
            rng;
            eligible_ids=inactive_at_start,
        )
        active_after = count(agent -> agent.active, agents)
        push!(
            renewals,
            RenewalRecord(period, exits, entries, active_before, active_after),
        )
        push!(equilibria, compute_equilibrium(agents, period))

        for tick in 1:config.ticks_per_period
            trade = attempt_random_trade!(agents, period, tick, config, rng)
            isnothing(trade) || push!(trades, trade)
        end
    end
    return SimulationResult(config, trades, equilibria, renewals)
end
