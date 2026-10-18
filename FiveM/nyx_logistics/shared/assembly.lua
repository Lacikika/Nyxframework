--[[
    Nyxframework: nyx_logistics
    File: shared/assembly.lua
    Description: Pure Lua 5.4 deterministic algorithms for power-dependent manufacturing,
                 substation interlocks, energy consumption, and batch palletization.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Assembly = {}

-- Power State Enums
Nyx.Assembly.PowerStates = {
    OPTIMAL = "OPTIMAL",
    NO_GRID = "NO_GRID",
    GRID_BLACKOUT = "GRID_BLACKOUT",
    BREAKER_TRIPPED = "BREAKER_TRIPPED",
    FUEL_DEPLETED = "FUEL_DEPLETED",
    MECHANICAL_BREAKDOWN = "MECHANICAL_BREAKDOWN"
}

--- Evaluates whether a regional substation is energized and capable of powering a facility
--- @param substationData table|nil
--- @param recipePowerKw number|nil
--- @return boolean isPowered, string reasonCode
function Nyx.Assembly.EvaluatePowerStatus(substationData, recipePowerKw)
    if not substationData then
        return false, Nyx.Assembly.PowerStates.NO_GRID
    end

    if substationData.isBlackout then
        return false, Nyx.Assembly.PowerStates.GRID_BLACKOUT
    end

    if substationData.breakerTripped then
        return false, Nyx.Assembly.PowerStates.BREAKER_TRIPPED
    end

    local fuel = tonumber(substationData.fuelLevel)
    if fuel and fuel <= 0.0 then
        return false, Nyx.Assembly.PowerStates.FUEL_DEPLETED
    end

    local health = tonumber(substationData.conditionHealth)
    if health and health <= 10.0 then
        return false, Nyx.Assembly.PowerStates.MECHANICAL_BREAKDOWN
    end

    return true, Nyx.Assembly.PowerStates.OPTIMAL
end

--- Calculates metered electrical energy consumption in kilowatt-hours (kWh)
--- @param powerKw number
--- @param durationSeconds number
--- @return number kWh
function Nyx.Assembly.CalculateEnergyUsageKwh(powerKw, durationSeconds)
    local kw = math.max(0.0, tonumber(powerKw) or 0.0)
    local sec = math.max(0.0, tonumber(durationSeconds) or 0.0)
    local kwh = kw * (sec / 3600.0)
    return math.floor(kwh * 10000) / 10000
end

--- Calculates the electrical load spike in MegaWatts (MW) imposed on the regional grid
--- @param powerKw number
--- @param batchCount number
--- @return number spikeMw
function Nyx.Assembly.CalculateGridLoadSpike(powerKw, batchCount)
    local kw = math.max(0.0, tonumber(powerKw) or 0.0)
    local batches = math.max(1, tonumber(batchCount) or 1)
    -- Concurrent equipment startup factor: 1.0 for single batch, +0.15 per additional concurrent batch
    local concurrencyFactor = 1.0 + ((batches - 1) * 0.15)
    local totalKw = kw * batches * concurrencyFactor
    local mw = totalKw / 1000.0 -- 1 MW = 1000 kW
    return math.floor(mw * 10000) / 10000
end

--- Calculates queue progress step percentage for a given tick interval
--- If power is offline, the assembly machinery halts and step is 0.0%
--- @param processingTime number
--- @param tickSeconds number
--- @param isPowerActive boolean
--- @return number stepPercent
function Nyx.Assembly.CalculateProgressStep(processingTime, tickSeconds, isPowerActive)
    if not isPowerActive then
        return 0.0
    end
    local totalTime = math.max(1.0, tonumber(processingTime) or 30.0)
    local tick = math.max(0.0, tonumber(tickSeconds) or 5.0)
    local step = (tick / totalTime) * 100.0
    return math.floor(step * 100) / 100
end

--- Validates whether available item counts satisfy the input requirements for a batch
--- @param recipe table
--- @param availableItems table<string, number>
--- @param batchCount number
--- @return boolean success, string|nil error, string|nil missingItem, number|nil needed, number|nil have
function Nyx.Assembly.ValidateBatchInputs(recipe, availableItems, batchCount)
    if not recipe or not recipe.inputs then
        return false, "INVALID_RECIPE", nil, nil, nil
    end

    local batches = math.max(1, tonumber(batchCount) or 1)
    availableItems = availableItems or {}

    for _, input in ipairs(recipe.inputs) do
        local requiredTotal = input.amount * batches
        local have = availableItems[input.item] or 0
        if have < requiredTotal then
            return false, "INSUFFICIENT_INPUTS", input.item, requiredTotal, have
        end
    end

    return true, nil, nil, nil, nil
end

--- Calculates total output quantities and metadata for a completed batch
--- @param recipe table
--- @param batchCount number
--- @param creationTimestamp number|nil
--- @return table outputs
function Nyx.Assembly.CalculateBatchOutputs(recipe, batchCount, creationTimestamp)
    local batches = math.max(1, tonumber(batchCount) or 1)
    local ts = creationTimestamp or os.time()
    local results = {}

    if not recipe or not recipe.outputs then return results end

    for _, out in ipairs(recipe.outputs) do
        local meta = {}
        if out.metadata then
            for k, v in pairs(out.metadata) do
                meta[k] = v
            end
        end
        meta.createdAt = ts
        meta.recipeKey = recipe.key
        meta.batchSize = batches

        results[#results + 1] = {
            item = out.item,
            amount = out.amount * batches,
            metadata = meta
        }
    end

    return results
end

--- Computes the cumulative weight of batch outputs given unit weights
--- @param outputs table
--- @param itemUnitWeights table<string, number>
--- @return number totalGrams
function Nyx.Assembly.CalculateTotalOutputWeight(outputs, itemUnitWeights)
    local total = 0
    itemUnitWeights = itemUnitWeights or {}

    for _, out in ipairs(outputs or {}) do
        local unitW = itemUnitWeights[out.item] or 1000 -- Default fallback 1000g
        total = total + (out.amount * unitW)
    end

    return total
end

--- Determines whether the completed batch should automatically package onto a physical freight pallet
--- @param outputMode string
--- @param totalOutputWeight number
--- @param batchCount number
--- @return boolean shouldPalletize
function Nyx.Assembly.ShouldAutoPalletize(outputMode, totalOutputWeight, batchCount)
    if outputMode == "pallet" then
        return true
    end

    local weight = math.max(0, tonumber(totalOutputWeight) or 0)
    -- Heavy freight threshold: 50,000g (50kg) or larger automatically auto-palletizes for flatbed/forklift hauling
    if weight >= 50000 then
        return true
    end

    return false
end
