function random_rational_between(
    lo::Price,
    hi::Price,
    denominator::Int,
    rng::AbstractRNG,
)
    lower = ceil(Int, lo * denominator)
    upper = floor(Int, hi * denominator)
    lower <= upper || return missing
    return rand(rng, lower:upper) // denominator
end

function attempt_random_trade!(
    agents::Vector{Agent},
    period::Int,
    tick::Int,
    config::MarketConfig,
    rng::AbstractRNG,
)
    buyer_ids = findall(can_buy, agents)
    seller_ids = findall(can_sell, agents)
    (isempty(buyer_ids) || isempty(seller_ids)) && return nothing

    buyer = agents[rand(rng, buyer_ids)]
    seller = agents[rand(rng, seller_ids)]
    current_wtp = buyer.wtp[buyer.next_wtp]
    current_wta = seller.wta[seller.next_wta]
    bid = random_rational_between(config.price_min, current_wtp, config.price_denominator, rng)
    ask = random_rational_between(current_wta, config.price_max, config.price_denominator, rng)
    (ismissing(bid) || ismissing(ask) || bid < ask) && return nothing

    price = (bid + ask) / 2
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
