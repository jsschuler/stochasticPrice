function price_grid_bounds(config::MarketConfig)
    lower = ceil(Int, config.price_min * config.price_denominator)
    upper = floor(Int, config.price_max * config.price_denominator)
    lower <= upper || throw(ArgumentError("price grid contains no points"))
    return lower, upper
end

function draw_price_schedule(length::Int, config::MarketConfig, rng::AbstractRNG; rev::Bool)
    lower, upper = price_grid_bounds(config)
    schedule = Price[rand(rng, lower:upper) // config.price_denominator for _ in 1:length]
    sort!(schedule; rev=rev)
    return schedule
end

function refresh_agent!(agent::Agent, config::MarketConfig, rng::AbstractRNG)
    agent.acquired = 0
    agent.sold = 0
    agent.next_wtp = 1
    agent.next_wta = 1
    if agent.role == :buyer
        agent.endowment = 0
        agent.wtp = draw_price_schedule(config.max_wtp_units, config, rng; rev=true)
        empty!(agent.wta)
    elseif agent.role == :seller
        agent.endowment = rand(rng, 1:config.max_endowment)
        empty!(agent.wtp)
        agent.wta = draw_price_schedule(agent.endowment, config, rng; rev=false)
    else
        throw(ArgumentError("unsupported role $(agent.role)"))
    end
    return agent
end

function initialize_agents(config::MarketConfig, rng::AbstractRNG)
    validate(config)
    n_buyers = round(Int, config.n_agents * config.buyer_share)
    roles = vcat(fill(:buyer, n_buyers), fill(:seller, config.n_agents - n_buyers))
    shuffle!(rng, roles)
    active_count = round(Int, config.n_agents * config.initial_active_share)
    active_ids = Set(randperm(rng, config.n_agents)[1:active_count])
    agents = Agent[]
    sizehint!(agents, config.n_agents)
    for id in 1:config.n_agents
        agent = Agent(id, id in active_ids, roles[id], 0, 0, 0, Price[], Price[], 1, 1)
        refresh_agent!(agent, config, rng)
        push!(agents, agent)
    end
    return agents
end

remaining_wtp(agent::Agent) =
    agent.next_wtp <= length(agent.wtp) ? @view(agent.wtp[agent.next_wtp:end]) : Price[]

remaining_wta(agent::Agent) =
    agent.next_wta <= length(agent.wta) ? @view(agent.wta[agent.next_wta:end]) : Price[]

can_buy(agent::Agent) =
    agent.active && agent.role == :buyer && agent.next_wtp <= length(agent.wtp)

can_sell(agent::Agent) =
    agent.active &&
    agent.role == :seller &&
    agent.endowment > 0 &&
    agent.next_wta <= length(agent.wta)
