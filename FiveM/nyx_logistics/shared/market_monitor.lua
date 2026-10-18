--[[
    Nyxframework: nyx_logistics
    File: shared/market_monitor.lua
    Description: Pure Lua 5.4 3D warehouse shelf matrix projection, dynamic elasticity
                 pricing calculations, regional supply/demand ratios, and hauler arbitrage models.
]]

Nyx = Nyx or {}
Nyx.LogisticsMarket = Nyx.LogisticsMarket or {}

-- Precision rounding helper
local function round(val, decimals)
    local mult = 10 ^ (decimals or 2)
    return math.floor((val or 0.0) * mult + 0.5) / mult
end

--- Standard US Dollar formatting helper ($1,250.00)
--- @param amount number
--- @return string
function Nyx.LogisticsMarket.FormatCurrency(amount)
    local amt = tonumber(amount) or 0.0
    local sign = (amt < 0) and "-" or ""
    amt = math.abs(amt)
    local intPart = math.floor(amt)
    local cents = math.floor((amt - intPart) * 100 + 0.5)

    local formattedInt = tostring(intPart)
    local k
    while true do
        formattedInt, k = string.gsub(formattedInt, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end

    if cents > 0 then
        return string.format("%s$%s.%02d", sign, formattedInt, cents)
    end
    return string.format("%s$%s", sign, formattedInt)
end

--- Computes 2D isometric projected coordinates and depth layer for a 3D shelf slot.
--- Used by the interactive 3D shelf matrix visualizer in the CEF web interface.
--- @param tier number 1-indexed tier level (from bottom to top)
--- @param slot number 1-indexed slot index (left to right)
--- @param tiersCount number Total tiers on the rack
--- @param slotsPerTier number Total slots per tier
--- @param spacingX number Optional horizontal spacing (default 50.0)
--- @param spacingY number Optional vertical isometric tilt (default 28.0)
--- @param tierHeight number Optional vertical step per tier (default 65.0)
--- @return table { tier, slot, isoX, isoY, layer }
function Nyx.LogisticsMarket.ProjectIsometricSlot(tier, slot, tiersCount, slotsPerTier, spacingX, spacingY, tierHeight)
    local t = math.max(1, math.floor(tonumber(tier) or 1))
    local s = math.max(1, math.floor(tonumber(slot) or 1))
    local totalT = math.max(1, math.floor(tonumber(tiersCount) or 3))
    local totalS = math.max(1, math.floor(tonumber(slotsPerTier) or 3))

    local sx = tonumber(spacingX) or 50.0
    local _ = tonumber(spacingY) or 28.0
    local th = tonumber(tierHeight) or 65.0

    -- Centered horizontal offset
    local slotCenterOffset = (s - (totalS + 1) / 2.0)
    local isoX = round(slotCenterOffset * sx, 2)
    -- Vertical position (top tier has lower screen Y, plus subtle isometric tilt)
    local isoY = round((totalT - t) * th - (slotCenterOffset * 6.0), 2)
    -- Depth layer for SVG / HTML stacking
    local layer = (totalT - t) * 10 + s

    return {
        tier = t,
        slot = s,
        isoX = isoX,
        isoY = isoY,
        layer = layer
    }
end

--- Computes dynamic elastic pricing and stock-to-demand metrics for a commodity shelf.
--- Formula:
---   D_eff = targetCapacity * zoneMultiplier * (1 + min(2.0, (velocity / velBase) * alpha))
---   R_sd = currentStock / D_eff
---   If R_sd < 1.0: mult = 1.0 + (1.0 - R_sd) * 1.50 (capped at 3.0x)
---   If R_sd >= 1.0: mult = max(0.40, 1.0 - (R_sd - 1.0) * 0.40)
--- @param basePrice number
--- @param targetCapacity number
--- @param currentStock number
--- @param zoneDemandMultiplier number
--- @param salesVelocity number
--- @param velocityImpactFactor number
--- @return table
function Nyx.LogisticsMarket.ComputeElasticPrice(basePrice, targetCapacity, currentStock, zoneDemandMultiplier, salesVelocity, velocityImpactFactor)
    local baseP = math.max(0.01, tonumber(basePrice) or 10.0)
    local targetCap = math.max(1.0, tonumber(targetCapacity) or 100.0)
    local currStock = math.max(0.0, tonumber(currentStock) or 0.0)
    local zoneMult = math.max(0.10, math.min(5.0, tonumber(zoneDemandMultiplier) or 1.0))
    local impact = tonumber(velocityImpactFactor) or 0.25

    local vel = math.max(0.0, tonumber(salesVelocity) or 0.0)
    local velBase = math.max(1.0, targetCap * 0.25)
    local velBonus = math.min(2.0, (vel / velBase) * impact)

    local effectiveDemand = round(targetCap * zoneMult * (1.0 + velBonus), 2)
    local stockRatio = round(currStock / math.max(1.0, effectiveDemand), 4)

    local mult = 1.0000
    if stockRatio < 1.0 then
        -- Deficit: price increases progressively up to 3.0x
        mult = 1.0 + (1.0 - stockRatio) * 1.50
        mult = math.min(3.0, mult)
    else
        -- Surplus: price decreases progressively down to 0.40x floor
        mult = math.max(0.40, 1.0 - (stockRatio - 1.0) * 0.40)
    end

    local priceMultiplier = round(mult, 4)
    local calculatedPrice = round(baseP * priceMultiplier, 2)
    local deficitUnits = math.max(0, math.floor(round(effectiveDemand - currStock, 0)))

    return {
        basePrice = baseP,
        calculatedPrice = calculatedPrice,
        priceMultiplier = priceMultiplier,
        effectiveDemand = effectiveDemand,
        stockToDemandRatio = stockRatio,
        deficitUnits = deficitUnits
    }
end

--- Computes hauler gross/net arbitrage spread between origin depot and destination retail zone.
--- @param originCost number
--- @param destPrice number
--- @param units number
--- @param distanceKm number
--- @param fuelRatePerKm number
--- @return table
function Nyx.LogisticsMarket.CalculateHaulerArbitrage(originCost, destPrice, units, distanceKm, fuelRatePerKm)
    local cost = math.max(0.0, tonumber(originCost) or 0.0)
    local price = math.max(0.0, tonumber(destPrice) or 0.0)
    local qty = math.max(1, math.floor(tonumber(units) or 10))
    local dist = math.max(0.1, tonumber(distanceKm) or 5.0)
    local fuelRate = tonumber(fuelRatePerKm) or 3.50

    local unitSpread = round(price - cost, 2)
    local grossProfit = round(unitSpread * qty, 2)
    local fuelCost = round(dist * fuelRate, 2)
    local netProfit = round(grossProfit - fuelCost, 2)
    local roiPct = round((netProfit / math.max(1.0, cost * qty)) * 100.0, 2)

    local rating = "UNPROFITABLE"
    if netProfit >= 1000.0 then
        rating = "EXCELLENT"
    elseif netProfit >= 300.0 then
        rating = "PROFITABLE"
    elseif netProfit > 0.0 then
        rating = "MARGINAL"
    end

    return {
        unitSpread = unitSpread,
        grossProfit = grossProfit,
        fuelCost = fuelCost,
        netProfit = netProfit,
        roiPct = roiPct,
        rating = rating
    }
end

--- Formats color-coded health badge based on stock-to-demand ratio.
--- @param stockToDemandRatio number
--- @return table
function Nyx.LogisticsMarket.FormatHealthBadge(stockToDemandRatio)
    local ratio = tonumber(stockToDemandRatio) or 0.0
    if ratio < 0.25 then
        return {
            status = "CRITICAL_DEFICIT",
            label = "KRITIKUS HIÁNY",
            badgeClass = "badge-danger",
            color = "#EF4444"
        }
    elseif ratio < 0.65 then
        return {
            status = "MODERATE_SHORTAGE",
            label = "MÉRSÉKELT HIÁNY",
            badgeClass = "badge-warning",
            color = "#F59E0B"
        }
    elseif ratio <= 1.35 then
        return {
            status = "EQUILIBRIUM",
            label = "PIACI EGYENSÚLY",
            badgeClass = "badge-success",
            color = "#10B981"
        }
    else
        return {
            status = "SURPLUS",
            label = "TÚLKÍNÁLAT / TÖBBLET",
            badgeClass = "badge-info",
            color = "#06B6D4"
        }
    end
end

--- Validates hauler route booking dispatch payload.
--- @param payload table
--- @return boolean success
--- @return table|nil sanitized
--- @return string|nil error
function Nyx.LogisticsMarket.ValidateDispatchPayload(payload)
    if type(payload) ~= "table" then
        return false, nil, "INVALID_PAYLOAD"
    end

    local whId = tostring(payload.originWarehouseId or payload.warehouseId or ""):gsub("^%s*(.-)%s*$", "%1")
    if #whId < 3 then
        return false, nil, "INVALID_ORIGIN_WAREHOUSE"
    end

    local zoneId = tostring(payload.destinationZoneId or payload.zoneId or ""):gsub("^%s*(.-)%s*$", "%1")
    if #zoneId < 3 then
        return false, nil, "INVALID_DESTINATION_ZONE"
    end

    local itemId = tostring(payload.itemId or ""):gsub("^%s*(.-)%s*$", "%1")
    if #itemId < 2 then
        return false, nil, "INVALID_ITEM_ID"
    end

    local units = math.floor(tonumber(payload.units) or 0)
    if units <= 0 or units > 1000 then
        return false, nil, "INVALID_UNITS_RANGE"
    end

    return true, {
        originWarehouseId = whId,
        destinationZoneId = zoneId,
        itemId = itemId,
        units = units
    }, nil
end

--- Multi-dimensional filtering across commodity lists.
--- @param commodities table
--- @param query string
--- @param zoneFilter string
--- @param categoryFilter string
--- @return table
function Nyx.LogisticsMarket.FilterCommodityCatalog(commodities, query, zoneFilter, categoryFilter)
    if type(commodities) ~= "table" then return {} end

    local q = (type(query) == "string") and string.lower(query:gsub("^%s*(.-)%s*$", "%1")) or ""
    local zFilt = (type(zoneFilter) == "string") and string.lower(zoneFilter:gsub("^%s*(.-)%s*$", "%1")) or "all"
    local cFilt = (type(categoryFilter) == "string") and string.lower(categoryFilter:gsub("^%s*(.-)%s*$", "%1")) or "all"

    local results = {}
    for _, item in ipairs(commodities) do
        local itemId = string.lower(tostring(item.itemId or ""))
        local name = string.lower(tostring(item.name or ""))
        local zone = string.lower(tostring(item.zoneId or ""))
        local cat = string.lower(tostring(item.category or ""))

        local matchQuery = (q == "") or (string.find(itemId, q, 1, true) ~= nil) or (string.find(name, q, 1, true) ~= nil)
        local matchZone = (zFilt == "all") or (zone == zFilt)
        local matchCategory = (cFilt == "all") or (cat == cFilt)

        if matchQuery and matchZone and matchCategory then
            results[#results + 1] = item
        end
    end

    return results
end
