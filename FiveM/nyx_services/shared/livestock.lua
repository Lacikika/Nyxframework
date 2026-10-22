--[[
    Nyxframework: nyx_services
    File: shared/livestock.lua
    Description: Pure Lua 5.4 deterministic calculations for agricultural livestock,
                 cattle growth/husbandry, perishable carcass decay, cold-chain temperature
                 preservation, butchering conversion yields, and reefer freight payouts.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.Livestock = Nyx.Services.Livestock or {}

-- Container Cold-Chain Decay Multipliers
Nyx.Services.Livestock.ContainerMultipliers = {
    ['cold_storage'] = 0.10,        -- Industrial walk-in freezer (90% decay reduction)
    ['refrigerated_truck'] = 0.15,   -- Active reefer trailer / thermo-van
    ['stash'] = 0.50,               -- Standard indoor storage
    ['player'] = 1.00,              -- Player inventory
    ['drop'] = 2.50                 -- Exposed outdoor ground drop
}

--- Calculate cattle ranch growth, feed consumption, and health updates over elapsed time
--- @param cattleHead number Current count of cattle
--- @param maxCapacity number Maximum ranch capacity
--- @param feedLevel number Current feed level percentage (0.0 to 100.0)
--- @param healthIndex number Current health index percentage (0.0 to 100.0)
--- @param elapsedSeconds number Elapsed time in seconds
--- @return number newFeedLevel, number newHealthIndex, number cattleGained
function Nyx.Services.Livestock.CalculateCattleGrowth(cattleHead, maxCapacity, feedLevel, healthIndex, elapsedSeconds)
    cattleHead = math.max(0, math.floor(tonumber(cattleHead) or 0))
    maxCapacity = math.max(1, math.floor(tonumber(maxCapacity) or 100))
    feedLevel = math.max(0.0, math.min(100.0, tonumber(feedLevel) or 100.0))
    healthIndex = math.max(0.0, math.min(100.0, tonumber(healthIndex) or 100.0))
    elapsedSeconds = math.max(0, math.floor(tonumber(elapsedSeconds) or 0))

    if elapsedSeconds <= 0 or cattleHead <= 0 then
        return feedLevel, healthIndex, 0
    end

    local hours = elapsedSeconds / 3600.0

    -- Feed consumption rate: 0.05% feed per cattle head per hour
    local feedConsumed = hours * (cattleHead * 0.05)
    local newFeedLevel = math.max(0.0, math.floor((feedLevel - feedConsumed) * 100.0 + 0.5) / 100.0)

    -- Health dynamics: If fed (>10%), health regenerates by 5%/hr up to 100%. If starved, health degrades by 10%/hr.
    local newHealthIndex = healthIndex
    if newFeedLevel > 10.0 then
        newHealthIndex = math.min(100.0, math.floor((healthIndex + (hours * 5.0)) * 100.0 + 0.5) / 100.0)
    else
        newHealthIndex = math.max(10.0, math.floor((healthIndex - (hours * 10.0)) * 100.0 + 0.5) / 100.0)
    end

    -- Cattle growth rate: If health >= 75% and feed > 20%, gains 1 head per 50 head per 2 hours
    local cattleGained = 0
    if newHealthIndex >= 75.0 and newFeedLevel >= 20.0 and cattleHead < maxCapacity then
        local baseGrowth = (cattleHead / 50.0) * (hours / 2.0)
        cattleGained = math.floor(baseGrowth)
        if cattleHead + cattleGained > maxCapacity then
            cattleGained = maxCapacity - cattleHead
        end
    end

    return newFeedLevel, newHealthIndex, cattleGained
end

--- Calculate perishable carcass / meat durability decay and temperature protection
--- @param durability number Current item durability (0.0 to 100.0)
--- @param decayRate number Base decay rate (e.g. 0.12)
--- @param elapsedSeconds number Time elapsed in seconds
--- @param containerType string Container type archetype ('cold_storage', 'refrigerated_truck', 'stash', 'player', 'drop')
--- @param isReeferActive boolean Whether active refrigeration unit is turned on
--- @param ambientTempC number Ambient temperature in degrees Celsius
--- @return number newDurability, boolean isSpoiled, string tier, number loss
function Nyx.Services.Livestock.CalculateCarcassDecay(durability, decayRate, elapsedSeconds, containerType, isReeferActive, ambientTempC)
    durability = math.max(0.0, math.min(100.0, tonumber(durability) or 100.0))
    decayRate = math.max(0.0, tonumber(decayRate) or 0.08)
    elapsedSeconds = math.max(0, math.floor(tonumber(elapsedSeconds) or 0))
    ambientTempC = tonumber(ambientTempC) or 22.0

    if elapsedSeconds <= 0 or durability <= 0.0 then
        local spoiled = durability <= 0.0
        local tier = spoiled and "SPOILED" or (durability >= 75.0 and "PRISTINE" or (durability >= 50.0 and "FRESH" or "STALE"))
        return durability, spoiled, tier, 0.0
    end

    local mult = Nyx.Services.Livestock.ContainerMultipliers[containerType] or 1.00

    -- Refrigeration unit override
    if isReeferActive or ambientTempC <= 4.0 then
        mult = math.min(mult, 0.10)
    end

    local rawLoss = (elapsedSeconds / 3600.0) * decayRate * 100.0 * mult
    local loss = math.max(0.0, math.floor(rawLoss * 10.0 + 0.5) / 10.0)
    local newDurability = math.max(0.0, math.floor((durability - loss) * 10.0 + 0.5) / 10.0)

    local isSpoiled = newDurability <= 0.0
    local tier = "SPOILED"
    if not isSpoiled then
        if newDurability >= 75.0 then
            tier = "PRISTINE"
        elseif newDurability >= 50.0 then
            tier = "FRESH"
        else
            tier = "STALE"
        end
    end

    return newDurability, isSpoiled, tier, loss
end

--- Evaluate cold chain operational status and temperature compliance
--- @param currentTempC number Actual cold storage temperature in C
--- @param isReeferActive boolean Whether refrigeration power unit is running
--- @return string status, number targetTemp, number currentTemp
function Nyx.Services.Livestock.EvaluateColdChainStatus(currentTempC, isReeferActive)
    currentTempC = math.floor((tonumber(currentTempC) or 2.0) * 10.0 + 0.5) / 10.0
    local targetTemp = 2.0

    if not isReeferActive then
        return "CRITICAL_SPOILAGE", targetTemp, currentTempC
    end

    if currentTempC <= 4.0 then
        return "PRISTINE", targetTemp, currentTempC
    elseif currentTempC <= 8.0 then
        return "FRESH", targetTemp, currentTempC
    elseif currentTempC <= 12.0 then
        return "DEGRADED", targetTemp, currentTempC
    else
        return "CRITICAL_SPOILAGE", targetTemp, currentTempC
    end
end

--- Calculate slaughtering & butchering yield output based on carcass state and facility cleanliness
--- @param carcassDurability number Carcass durability percentage
--- @param cleanlinessIndex number Slaughterhouse cleanliness percentage
--- @return number cutsAmount, number palletAmount, string qualityGrade
function Nyx.Services.Livestock.CalculateButcheringYield(carcassDurability, cleanlinessIndex)
    carcassDurability = math.max(0.0, math.min(100.0, tonumber(carcassDurability) or 100.0))
    cleanlinessIndex = math.max(0.0, math.min(100.0, tonumber(cleanlinessIndex) or 100.0))

    if carcassDurability <= 0.0 then
        return 0, 0, "SPOILED"
    end

    local durabilityFactor = carcassDurability / 100.0
    local cleanFactor = cleanlinessIndex / 100.0

    local baseCuts = 10
    local basePallets = 1

    local cutsAmount = math.max(1, math.floor(baseCuts * durabilityFactor * cleanFactor + 0.5))
    local palletAmount = (carcassDurability >= 50.0 and cleanlinessIndex >= 50.0) and 1 or 0

    local qualityGrade = "PRISTINE"
    local combinedScore = (durabilityFactor * 0.6) + (cleanFactor * 0.4)
    if combinedScore < 0.40 then
        qualityGrade = "SPOILED"
    elseif combinedScore < 0.65 then
        qualityGrade = "STALE"
    elseif combinedScore < 0.85 then
        qualityGrade = "FRESH"
    end

    return cutsAmount, palletAmount, qualityGrade
end

--- Calculate reefer cold-chain freight haulage payout, bond returns, and spoilage penalties
--- @param basePayout number Contract base payment
--- @param averageDurability number Average durability of delivered perishable freight
--- @param transitSeconds number Elapsed time in transit
--- @param deadlineSeconds number Contract max allowed transit time
--- @return number finalPayout, number escrowReturn, number penaltyDeduction, number bonus
function Nyx.Services.Livestock.CalculateRefrigeratedFreightPayout(basePayout, averageDurability, transitSeconds, deadlineSeconds)
    basePayout = math.max(0.0, tonumber(basePayout) or 1000.0)
    averageDurability = math.max(0.0, math.min(100.0, tonumber(averageDurability) or 100.0))
    transitSeconds = math.max(0, math.floor(tonumber(transitSeconds) or 0))
    deadlineSeconds = math.max(1, math.floor(tonumber(deadlineSeconds) or 1800))

    local escrowBond = math.floor(basePayout * 0.15 * 100.0 + 0.5) / 100.0

    if averageDurability <= 0.0 then
        -- Total spoilage: Payout is 0, bond is forfeited as penalty
        return 0.0, 0.0, escrowBond, 0.0
    end

    local durabilityMult = 1.00
    if averageDurability >= 90.0 then
        durabilityMult = 1.10 -- 10% pristine cold-chain bonus
    elseif averageDurability >= 75.0 then
        durabilityMult = 1.00
    elseif averageDurability >= 50.0 then
        durabilityMult = 0.75 -- 25% stale penalty
    else
        durabilityMult = 0.40 -- 60% severe decay penalty
    end

    local timeMult = 1.00
    if transitSeconds > deadlineSeconds then
        timeMult = 0.70 -- 30% late delivery penalty
    end

    local bonus = 0.0
    if averageDurability >= 90.0 and transitSeconds <= (deadlineSeconds * 0.75) then
        bonus = math.floor(basePayout * 0.15 * 100.0 + 0.5) / 100.0 -- 15% express cold-chain bonus
    end

    local rawPayout = (basePayout * durabilityMult * timeMult) + bonus
    local finalPayout = math.floor(rawPayout * 100.0 + 0.5) / 100.0
    local penaltyDeduction = math.max(0.0, math.floor((basePayout - (basePayout * durabilityMult * timeMult)) * 100.0 + 0.5) / 100.0)

    return finalPayout, escrowBond, penaltyDeduction, bonus
end
