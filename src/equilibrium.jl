function compute_equilibrium(agents::Vector{Agent}, period::Int)
    values = Price[]
    costs = Price[]
    active_buyers = 0
    active_sellers = 0
    for agent in agents
        agent.active || continue
        if agent.role == :buyer
            active_buyers += 1
            append!(values, remaining_wtp(agent))
        elseif agent.role == :seller
            active_sellers += 1
            append!(costs, remaining_wta(agent))
        end
    end
    sort!(values; rev=true)
    sort!(costs)
    q_star = 0
    for quantity in 1:min(length(values), length(costs))
        values[quantity] >= costs[quantity] || break
        q_star = quantity
    end
    if q_star == 0
        return EquilibriumRecord(
            period,
            missing,
            missing,
            0,
            active_buyers,
            active_sellers,
            active_buyers + active_sellers,
        )
    end
    return EquilibriumRecord(
        period,
        costs[q_star],
        values[q_star],
        q_star,
        active_buyers,
        active_sellers,
        active_buyers + active_sellers,
    )
end
