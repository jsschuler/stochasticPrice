is_live(order::LimitOrder, book::OrderBook, agents::Vector{Agent}) =
    get(book.active_sequences, order.agent_id, 0) == order.sequence &&
    agents[order.agent_id].active &&
    (order.side == :bid ? can_buy(agents[order.agent_id]) : can_sell(agents[order.agent_id]))

function bid_precedes(left::LimitOrder, right::LimitOrder)
    left.price != right.price && return left.price > right.price
    return left.sequence < right.sequence
end

function ask_precedes(left::LimitOrder, right::LimitOrder)
    left.price != right.price && return left.price < right.price
    return left.sequence < right.sequence
end

function heap_push!(
    heap::Vector{LimitOrder},
    order::LimitOrder,
    precedes::Function,
)
    push!(heap, order)
    index = length(heap)
    while index > 1
        parent = index ÷ 2
        precedes(heap[index], heap[parent]) || break
        heap[index], heap[parent] = heap[parent], heap[index]
        index = parent
    end
    return order
end

function heap_pop!(heap::Vector{LimitOrder}, precedes::Function)
    top = first(heap)
    last_order = pop!(heap)
    isempty(heap) && return top
    heap[1] = last_order
    index = 1
    while true
        left = 2 * index
        right = left + 1
        left > length(heap) && break
        child = right <= length(heap) && precedes(heap[right], heap[left]) ? right : left
        precedes(heap[child], heap[index]) || break
        heap[index], heap[child] = heap[child], heap[index]
        index = child
    end
    return top
end

function best_live_order!(
    heap::Vector{LimitOrder},
    book::OrderBook,
    agents::Vector{Agent},
    precedes::Function,
)
    while !isempty(heap) && !is_live(first(heap), book, agents)
        heap_pop!(heap, precedes)
    end
    return isempty(heap) ? nothing : first(heap)
end

best_bid!(book::OrderBook, agents::Vector{Agent}) =
    best_live_order!(book.bids, book, agents, bid_precedes)

best_ask!(book::OrderBook, agents::Vector{Agent}) =
    best_live_order!(book.asks, book, agents, ask_precedes)

function cancel_order!(book::OrderBook, agent_id::Int)
    delete!(book.active_sequences, agent_id)
    return book
end

function submit_order!(
    book::OrderBook,
    agent_id::Int,
    side::Symbol,
    price::Price,
)
    sequence = book.next_sequence
    book.next_sequence += 1
    order = LimitOrder(agent_id, side, price, sequence)
    book.active_sequences[agent_id] = sequence
    if side == :bid
        heap_push!(book.bids, order, bid_precedes)
    elseif side == :ask
        heap_push!(book.asks, order, ask_precedes)
    else
        throw(ArgumentError("order side must be :bid or :ask"))
    end
    return order
end

function clear_inactive_orders!(book::OrderBook, agents::Vector{Agent})
    for agent_id in collect(keys(book.active_sequences))
        agents[agent_id].active || delete!(book.active_sequences, agent_id)
    end
    return book
end

function execute_cda_trade!(
    buyer::Agent,
    seller::Agent,
    bid::Price,
    ask::Price,
    price::Price,
    period::Int,
    tick::Int,
    config::MarketConfig,
)
    current_wtp = buyer.wtp[buyer.next_wtp]
    current_wta = seller.wta[seller.next_wta]
    buyer.acquired += 1
    buyer.next_wtp += 1
    seller.endowment -= 1
    seller.sold += 1
    seller.next_wta += 1
    global_tick = (period - 1) * config.ticks_per_period + tick
    return TradeRecord(
        period,
        tick,
        global_tick,
        buyer.id,
        seller.id,
        current_wtp,
        current_wta,
        bid,
        ask,
        price,
        1,
    )
end

function attempt_cda_action!(
    agents::Vector{Agent},
    book::OrderBook,
    period::Int,
    tick::Int,
    config::MarketConfig,
    rng::AbstractRNG,
)
    eligible = findall(agent -> can_buy(agent) || can_sell(agent), agents)
    isempty(eligible) && return nothing
    agent = agents[rand(rng, eligible)]

    if agent.role == :buyer
        current_wtp = agent.wtp[agent.next_wtp]
        bid = random_rational_between(
            config.price_min,
            current_wtp,
            config.price_denominator,
            rng,
        )
        ask_order = best_ask!(book, agents)
        if !isnothing(ask_order) && bid >= ask_order.price
            seller = agents[ask_order.agent_id]
            cancel_order!(book, agent.id)
            cancel_order!(book, seller.id)
            return execute_cda_trade!(
                agent,
                seller,
                bid,
                ask_order.price,
                ask_order.price,
                period,
                tick,
                config,
            )
        end
        submit_order!(book, agent.id, :bid, bid)
    else
        current_wta = agent.wta[agent.next_wta]
        ask = random_rational_between(
            current_wta,
            config.price_max,
            config.price_denominator,
            rng,
        )
        bid_order = best_bid!(book, agents)
        if !isnothing(bid_order) && bid_order.price >= ask
            buyer = agents[bid_order.agent_id]
            cancel_order!(book, agent.id)
            cancel_order!(book, buyer.id)
            return execute_cda_trade!(
                buyer,
                agent,
                bid_order.price,
                ask,
                bid_order.price,
                period,
                tick,
                config,
            )
        end
        submit_order!(book, agent.id, :ask, ask)
    end
    return nothing
end

function run_cda_simulation(config::MarketConfig)
    validate(config)
    rng = MersenneTwister(config.seed)
    agents = initialize_agents(config, rng)
    book = OrderBook()
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
        clear_inactive_orders!(book, agents)
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
            trade = attempt_cda_action!(agents, book, period, tick, config, rng)
            isnothing(trade) || push!(trades, trade)
        end
    end
    return SimulationResult(config, trades, equilibria, renewals)
end
