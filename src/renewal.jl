function correlated_uniforms(rho::Float64, rng::AbstractRNG)
    z_exit = randn(rng)
    z_entry = rho * z_exit + sqrt(1.0 - rho^2) * randn(rng)
    normal = Normal()
    epsilon = eps(Float64)
    return clamp(cdf(normal, z_exit), epsilon, 1.0 - epsilon),
           clamp(cdf(normal, z_entry), epsilon, 1.0 - epsilon)
end

poisson_quantile(mean::Float64, uniform::Float64) =
    mean == 0.0 ? 0 : Int(quantile(Poisson(mean), uniform))

function draw_entry_exit_counts(
    active_count::Int,
    inactive_count::Int,
    config::MarketConfig,
    rng::AbstractRNG,
)
    uniform_exit, uniform_entry = correlated_uniforms(config.entry_exit_rho, rng)
    exits = poisson_quantile(config.lambda_exit * active_count, uniform_exit)
    entries = poisson_quantile(config.lambda_entry * inactive_count, uniform_entry)
    return min(exits, active_count), min(entries, inactive_count)
end

function draw_entry_exit_counts(
    agents::Vector{Agent},
    config::MarketConfig,
    rng::AbstractRNG,
)
    active_count = count(agent -> agent.active, agents)
    return draw_entry_exit_counts(
        active_count,
        length(agents) - active_count,
        config,
        rng,
    )
end

function apply_exits!(agents::Vector{Agent}, count::Int, rng::AbstractRNG)
    eligible = findall(agent -> agent.active, agents)
    selected = count == 0 ? Int[] : shuffle(rng, eligible)[1:min(count, length(eligible))]
    for index in selected
        agents[index].active = false
    end
    return selected
end

function apply_entries!(
    agents::Vector{Agent},
    count::Int,
    config::MarketConfig,
    rng::AbstractRNG;
    eligible_ids::Union{Nothing,Vector{Int}}=nothing,
)
    eligible = isnothing(eligible_ids) ? findall(agent -> !agent.active, agents) : eligible_ids
    selected = count == 0 ? Int[] : shuffle(rng, eligible)[1:min(count, length(eligible))]
    for index in selected
        refresh_agent!(agents[index], config, rng)
        agents[index].active = true
    end
    return selected
end
