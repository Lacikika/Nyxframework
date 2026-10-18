--[[
    Nyxframework: nyx_services & nyx_logistics
    File: shared/agriculture.lua
    Description: Pure Lua 5.4 domain engine for agricultural harvest node extraction,
                 soil fertility degradation, milling conversions, perishable food decay,
                 cold storage multipliers, and municipal emergency food pantry triage.
]]

Nyx = Nyx or {}
Nyx.Agriculture = Nyx.Agriculture or {}

-- ----------------------------------------------------------------------------
-- 1. Status Taxonomy & Constants
-- ----------------------------------------------------------------------------
Nyx.Agriculture.STATUS_OPTIMAL           = "optimal"
Nyx.Agriculture.STATUS_DEGRADED          = "degraded"
Nyx.Agriculture.STATUS_CRITICAL_SHORTAGE = "critical_shortage"

Nyx.Agriculture.FRESHNESS_PRISTINE       = "PRISTINE"  -- 75.0% - 100.0%
Nyx.Agriculture.FRESHNESS_FRESH          = "FRESH"     -- 50.0% - 74.9%
Nyx.Agriculture.FRESHNESS_STALE          = "STALE"     -- 25.0% - 49.9%
Nyx.Agriculture.FRESHNESS_EXPIRING       = "EXPIRING"  -- 0.1% - 24.9%
Nyx.Agriculture.FRESHNESS_SPOILED        = "SPOILED"   -- <= 0.0%

-- Environmental Container Decay Multipliers
Nyx.Agriculture.ContainerMultipliers = {
    ['cold_storage'] = 0.15, -- Climate-controlled industrial refrigerator / cold-chain walk-in
    ['refrigerator'] = 0.20, -- Domestic refrigerator / deli display cooler
    ['stash']        = 0.50, -- Standard indoor shelving / grocery warehouse
    ['trunk']        = 0.75, -- Vehicle cargo compartment
    ['glovebox']     = 0.75, -- Vehicle interior glovebox
    ['player']       = 1.00, -- Ambient temperature in backpack or pockets
    ['drop']         = 2.00  -- Exposed ground terrain, direct heat, moisture
}

-- ----------------------------------------------------------------------------
-- 2. Pure Calculation: Crop Extraction & Soil Fertility Invariants
-- ----------------------------------------------------------------------------

--- Calculate agricultural crop harvest yield based on current reserves and soil fertility
--- @param currentReserve number
--- @param soilFertility number 0.0 to 100.0%
--- @param toolBonus number|nil
--- @return number yieldAmount
--- @return number remainingReserve
--- @return number newSoilFertility
function Nyx.Agriculture.CalculateCropYield(currentReserve, soilFertility, toolBonus)
    currentReserve = math.max(0, tonumber(currentReserve) or 0)
    soilFertility = math.max(0.0, math.min(100.0, tonumber(soilFertility) or 100.0))
    toolBonus = math.max(1.0, tonumber(toolBonus) or 1.0)

    if currentReserve <= 0 then
        return 0, 0, soilFertility
    end

    -- Fertility scaling factor between 0.20x and 1.25x
    local fertilityFactor = math.max(0.20, math.min(1.25, soilFertility / 100.0))
    local baseYield = 4
    local calculatedYield = math.floor(baseYield * fertilityFactor * toolBonus)
    local yieldAmount = math.max(1, math.min(calculatedYield, currentReserve))

    -- Soil wear: -2.5% fertility degradation per harvest cycle, floor at 10.0%
    local fertilityWear = 2.50
    local newSoilFertility = math.max(10.0, math.floor((soilFertility - fertilityWear) * 100) / 100)
    local remainingReserve = currentReserve - yieldAmount

    return yieldAmount, remainingReserve, newSoilFertility
end

--- Calculate soil fertility recovery over elapsed idle time
--- @param currentFertility number
--- @param elapsedSeconds number
--- @param regenRatePerHour number|nil (default 15% per hour)
--- @return number recoveredFertility
function Nyx.Agriculture.CalculateSoilRecovery(currentFertility, elapsedSeconds, regenRatePerHour)
    currentFertility = math.max(0.0, math.min(100.0, tonumber(currentFertility) or 100.0))
    elapsedSeconds = math.max(0, tonumber(elapsedSeconds) or 0)
    regenRatePerHour = math.max(1.0, tonumber(regenRatePerHour) or 15.0)

    if currentFertility >= 100.0 or elapsedSeconds <= 0 then
        return currentFertility
    end

    local recovered = (elapsedSeconds / 3600.0) * regenRatePerHour
    local newFertility = math.min(100.0, math.floor((currentFertility + recovered) * 100) / 100)
    return newFertility
end

-- ----------------------------------------------------------------------------
-- 3. Pure Calculation: Milling & Food Processing Ratios
-- ----------------------------------------------------------------------------

--- Calculate bulk milling batch transformation outputs
--- @param recipeKey string 'wheat_milling', 'corn_milling', 'bakery_bread'
--- @param batchMultiplier number|nil
--- @return table|nil outputItems, table|nil inputRequirements
function Nyx.Agriculture.CalculateMillingOutput(recipeKey, batchMultiplier)
    batchMultiplier = math.max(1, math.min(50, math.floor(tonumber(batchMultiplier) or 1)))

    if recipeKey == "wheat_milling" then
        return {
            { item = "bulk_flour", amount = 1 * batchMultiplier, label = "Commercial Milled Flour Sack" }
        }, {
            { item = "crop_wheat", amount = 4 * batchMultiplier }
        }
    elseif recipeKey == "corn_milling" then
        return {
            { item = "bulk_cornmeal", amount = 1 * batchMultiplier, label = "Industrial Cornmeal Sack" }
        }, {
            { item = "crop_corn", amount = 4 * batchMultiplier }
        }
    elseif recipeKey == "bakery_bread" then
        return {
            { item = "food_bread", amount = 4 * batchMultiplier, label = "Fresh Artisan Bread Loaf" }
        }, {
            { item = "bulk_flour", amount = 1 * batchMultiplier },
            { item = "drink_water", amount = 2 * batchMultiplier }
        }
    elseif recipeKey == "produce_pallet_packaging" then
        return {
            { item = "pallet_agricultural_produce", amount = 1 * batchMultiplier, label = "Agricultural Bulk Produce Pallet" }
        }, {
            { item = "crop_produce", amount = 10 * batchMultiplier },
            { item = "civic_wooden_pallet", amount = 1 * batchMultiplier }
        }
    end

    return nil, nil
end

-- ----------------------------------------------------------------------------
-- 4. Pure Calculation: Perishable Food Durability Decay & Cold Chain
-- ----------------------------------------------------------------------------

--- Calculate numerical durability loss and freshness state for perishable food
--- @param currentDurability number
--- @param decayRate number
--- @param deltaSeconds number
--- @param containerType string|nil
--- @param isRefrigerated boolean|nil
--- @return number newDurability
--- @return boolean isSpoiled
--- @return string freshnessTier
--- @return number lossPoints
function Nyx.Agriculture.CalculatePerishableDecay(currentDurability, decayRate, deltaSeconds, containerType, isRefrigerated)
    currentDurability = math.max(0.0, math.min(100.0, tonumber(currentDurability) or 100.0))
    decayRate = math.max(0.0, tonumber(decayRate) or 0.08)
    deltaSeconds = math.max(0, tonumber(deltaSeconds) or 0)

    if currentDurability <= 0.0 then
        return 0.0, true, Nyx.Agriculture.FRESHNESS_SPOILED, 0.0
    end

    if decayRate <= 0.0 or deltaSeconds <= 0 then
        local tier = Nyx.Agriculture.GetFreshnessTier(currentDurability)
        return currentDurability, false, tier, 0.0
    end

    local mult = Nyx.Agriculture.ContainerMultipliers[containerType] or 1.0
    if isRefrigerated == true then
        mult = math.min(mult, Nyx.Agriculture.ContainerMultipliers['cold_storage'])
    end

    local rawLoss = (deltaSeconds / 3600.0) * decayRate * 100.0 * mult
    local lossPoints = math.max(0.0, math.floor(rawLoss * 10) / 10)
    local newDurability = math.max(0.0, math.floor((currentDurability - lossPoints) * 10) / 10)
    local isSpoiled = (newDurability <= 0.0)
    local freshnessTier = Nyx.Agriculture.GetFreshnessTier(newDurability)

    return newDurability, isSpoiled, freshnessTier, lossPoints
end

--- Classify durability percentage into freshness taxonomy
--- @param durability number
--- @return string freshnessTier
function Nyx.Agriculture.GetFreshnessTier(durability)
    durability = tonumber(durability) or 0.0
    if durability <= 0.0 then
        return Nyx.Agriculture.FRESHNESS_SPOILED
    elseif durability < 25.0 then
        return Nyx.Agriculture.FRESHNESS_EXPIRING
    elseif durability < 50.0 then
        return Nyx.Agriculture.FRESHNESS_STALE
    elseif durability < 75.0 then
        return Nyx.Agriculture.FRESHNESS_FRESH
    else
        return Nyx.Agriculture.FRESHNESS_PRISTINE
    end
end

-- ----------------------------------------------------------------------------
-- 5. Pure Calculation: Emergency Food Pantry Status & Triage
-- ----------------------------------------------------------------------------

--- Evaluate emergency pantry food security index and tier classification
--- @param pantry table { target_rations, target_bread }
--- @param stockCounts table { food_ration, food_bread }
--- @return string status 'optimal', 'degraded', 'critical_shortage'
--- @return number compositeSecurity 0.0 to 100.0%
--- @return table metrics breakdown of stock, targets, and deficits
function Nyx.Agriculture.EvaluatePantryStatus(pantry, stockCounts)
    pantry = pantry or {}
    stockCounts = stockCounts or {}

    local targetRations = math.max(1, tonumber(pantry.target_rations) or 100)
    local targetBread = math.max(1, tonumber(pantry.target_bread) or 50)

    local curRations = math.max(0, tonumber(stockCounts.food_ration) or 0)
    local curBread = math.max(0, tonumber(stockCounts.food_bread) or 0)

    local ratioRations = math.min(1.0, curRations / targetRations)
    local ratioBread = math.min(1.0, curBread / targetBread)

    -- Composite food security score: 50% shelf-stable rations, 50% fresh bread
    local compositeSecurity = math.floor(((ratioRations * 0.50) + (ratioBread * 0.50)) * 1000) / 10

    local deficitRations = math.max(0, targetRations - curRations)
    local deficitBread = math.max(0, targetBread - curBread)
    local totalDeficit = deficitRations + deficitBread

    local status = Nyx.Agriculture.STATUS_OPTIMAL
    if compositeSecurity < 25.0 or curRations == 0 then
        status = Nyx.Agriculture.STATUS_CRITICAL_SHORTAGE
    elseif compositeSecurity < 60.0 then
        status = Nyx.Agriculture.STATUS_DEGRADED
    end

    local metrics = {
        currentRations = curRations,
        targetRations = targetRations,
        deficitRations = deficitRations,
        currentBread = curBread,
        targetBread = targetBread,
        deficitBread = deficitBread,
        totalDeficit = totalDeficit,
        securityPercent = compositeSecurity,
        status = status
    }

    return status, compositeSecurity, metrics
end

-- ----------------------------------------------------------------------------
-- 6. Pure Calculation: Emergency Food Logistics Freight Contract
-- ----------------------------------------------------------------------------

--- Calculate emergency courier freight contract parameters for pantry restocking
--- @param pantry table
--- @param deficitItem string 'food_ration' or 'food_bread'
--- @param deficitCount number
--- @param status string
--- @return table contractParameters
function Nyx.Agriculture.CalculateEmergencyFoodContract(pantry, deficitItem, deficitCount, status)
    pantry = pantry or {}
    deficitItem = (deficitItem == "food_bread") and "food_bread" or "food_ration"
    deficitCount = math.max(10, math.min(60, tonumber(deficitCount) or 30))

    local baseRate = (deficitItem == "food_bread") and 35.00 or 25.00
    local urgencyMultiplier = 1.00

    if status == Nyx.Agriculture.STATUS_CRITICAL_SHORTAGE then
        urgencyMultiplier = 2.00
    elseif status == Nyx.Agriculture.STATUS_DEGRADED then
        urgencyMultiplier = 1.40
    end

    local payoutPerUnit = math.floor(baseRate * urgencyMultiplier * 100) / 100
    local totalPayout = math.floor(payoutPerUnit * deficitCount * 100) / 100
    local escrowDeposit = math.floor((totalPayout * 0.15) * 100) / 100

    local sourceInvId = (deficitItem == "food_bread") and "stash:grapeseed_mill_out" or "stash:refinery_out"
    local destInvId = pantry.stash_id or "stash:pantry_city_hall"

    return {
        contractType = "perishable_food",
        itemId = deficitItem,
        quantity = deficitCount,
        payoutPerUnit = payoutPerUnit,
        totalPayout = totalPayout,
        escrowDeposit = escrowDeposit,
        deadlineSeconds = 1800,
        sourceInventoryId = sourceInvId,
        destInventoryId = destInvId,
        urgencyMultiplier = urgencyMultiplier
    }
end

-- ----------------------------------------------------------------------------
-- 7. Zero-Trust Payload Validation
-- ----------------------------------------------------------------------------

--- Validate payload for crop harvesting action
--- @param payload table
--- @return boolean isValid, string|nil errorCode
function Nyx.Agriculture.ValidateHarvestPayload(payload)
    if type(payload) ~= "table" then return false, "INVALID_PAYLOAD" end
    if not payload.farmId or type(payload.farmId) ~= "string" or #payload.farmId > 64 then
        return false, "INVALID_FARM_ID"
    end
    return true, nil
end

--- Validate payload for pantry restocking action
--- @param payload table
--- @return boolean isValid, string|nil errorCode
function Nyx.Agriculture.ValidateRestockPayload(payload)
    if type(payload) ~= "table" then return false, "INVALID_PAYLOAD" end
    if not payload.pantryId or type(payload.pantryId) ~= "string" or #payload.pantryId > 64 then
        return false, "INVALID_PANTRY_ID"
    end
    if not payload.itemId or type(payload.itemId) ~= "string" then
        return false, "INVALID_ITEM_ID"
    end

    local allowedItems = {
        ["food_ration"] = true,
        ["food_bread"] = true,
        ["food_sandwich"] = true,
        ["crop_produce"] = true,
        ["bulk_flour"] = true,
        ["bulk_cornmeal"] = true
    }
    if not allowedItems[payload.itemId] then
        return false, "ITEM_NOT_ACCEPTED_AT_PANTRY"
    end

    local amount = tonumber(payload.amount)
    if not amount or amount <= 0 or amount > 200 or math.floor(amount) ~= amount then
        return false, "INVALID_AMOUNT"
    end

    return true, nil
end

-- ----------------------------------------------------------------------------
-- 8. UI Formatting & Presentation Badges
-- ----------------------------------------------------------------------------

--- Format pantry security status badge
--- @param status string
--- @return table { code, css, label }
function Nyx.Agriculture.FormatPantryBadge(status)
    if status == Nyx.Agriculture.STATUS_OPTIMAL then
        return { code = "OPTIMAL", css = "badge-success", label = "Reserves Optimal" }
    elseif status == Nyx.Agriculture.STATUS_DEGRADED then
        return { code = "DEGRADED", css = "badge-warning", label = "Moderate Shortage" }
    elseif status == Nyx.Agriculture.STATUS_CRITICAL_SHORTAGE then
        return { code = "CRITICAL_SHORTAGE", css = "badge-danger", label = "Critical Shortage" }
    end
    return { code = "UNKNOWN", css = "badge-secondary", label = "Unknown Status" }
end

--- Format food freshness status badge
--- @param durability number
--- @param isSpoiled boolean
--- @return table { code, css, label, percent }
function Nyx.Agriculture.FormatFreshnessBadge(durability, isSpoiled)
    durability = math.max(0.0, math.min(100.0, tonumber(durability) or 100.0))
    if isSpoiled or durability <= 0.0 then
        return { code = "SPOILED", css = "badge-danger", label = "Spoiled / Unsafe", percent = 0.0 }
    elseif durability < 25.0 then
        return { code = "EXPIRING", css = "badge-warning", label = "Expiring Soon", percent = durability }
    elseif durability < 50.0 then
        return { code = "STALE", css = "badge-info", label = "Stale Quality", percent = durability }
    elseif durability < 75.0 then
        return { code = "FRESH", css = "badge-primary", label = "Fresh Standard", percent = durability }
    else
        return { code = "PRISTINE", css = "badge-success", label = "Pristine Fresh", percent = durability }
    end
end

--- Format currency amounts into standard USD representation
--- @param amount number
--- @return string formatted
function Nyx.Agriculture.FormatCurrency(amount)
    local n = math.max(0, tonumber(amount) or 0)
    local left, num, right = string.match(string.format("%.2f", n), '^([^%d]*%d)(%d*)(.-)$')
    return "$" .. left .. (num:reverse():gsub('(%d%d%d)', '%1,'):reverse()) .. right
end
