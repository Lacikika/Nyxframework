--[[
    Nyxframework: nyx_logistics
    File: server/zones.lua
    Description: Authoritative Localized Delivery Zones, Rolling Demand Velocity,
                 Effective Demand Computation, and Regional Commodity Price Indexing.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.Zones = {} -- [zoneId] = zoneTable
Nyx.Logistics.PriceHistory = {}

-- Restore / Hydrate Delivery Zones from MySQL
MySQL.ready(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end

    local rows = MySQL.query.await("SELECT * FROM `nyx_logistics_zones` WHERE `is_active` = 1")
    if rows and #rows > 0 then
        for _, r in ipairs(rows) do
            local rawCoords = r.coords and json.decode(r.coords) or { x = 0.0, y = 0.0, z = 0.0 }
            Nyx.Logistics.Zones[r.zone_id] = {
                id = r.zone_id,
                name = r.name,
                description = r.description,
                coords = vector3(rawCoords.x, rawCoords.y, rawCoords.z or 0.0),
                radius = tonumber(r.radius) or 1500.0,
                baseDemandMultiplier = tonumber(r.base_demand_multiplier) or 1.00,
                taxSurcharge = tonumber(r.tax_surcharge) or 0.0000,
                importTariffRate = tonumber(r.import_tariff_rate) or 0.0000
            }
        end
        print(string.format("^2[Nyx:Logistics] Loaded %d economic delivery zone(s) from database.^7", #rows))
    else
        -- Fallback to default zones
        for k, v in pairs(Nyx.Logistics.DefaultZones) do
            Nyx.Logistics.Zones[k] = v
        end
        print("^3[Nyx:Logistics] Hydrated default economic delivery zones.^7")
    end
end)

-- Retrieve a specific delivery zone or fallback to default
function Nyx.Logistics.GetZone(zoneId)
    if not zoneId then
        return Nyx.Logistics.Zones["zone_ls_metro"] or Nyx.Logistics.DefaultZones["zone_ls_metro"]
    end
    return Nyx.Logistics.Zones[zoneId] or Nyx.Logistics.DefaultZones[zoneId] or Nyx.Logistics.Zones["zone_ls_metro"]
end

-- Exponential velocity half-life decay function: V(t) = V0 * 2^(-dt / t_half)
function Nyx.Logistics.CalculateDecayedVelocity(prevVelocity, lastPurchasedAtUnix)
    if not prevVelocity or prevVelocity <= 0.0 then return 0.0 end
    if not lastPurchasedAtUnix or lastPurchasedAtUnix <= 0 then return 0.0 end

    local now = os.time()
    local elapsed = math.max(0, now - lastPurchasedAtUnix)
    local halfLife = (Config.DeliveryZones and Config.DeliveryZones.VelocityHalfLifeSeconds) or 1800

    local decayFactor = math.pow(0.5, elapsed / halfLife)
    local decayed = prevVelocity * decayFactor

    if decayed < 0.01 then
        return 0.0
    end
    return math.floor(decayed * 100) / 100
end

-- Record a retail purchase to update sales velocity and timestamp
function Nyx.Logistics.RecordPurchase(shelf, quantity)
    if not shelf then return end
    quantity = math.max(1, tonumber(quantity) or 1)

    local now = os.time()
    local decayed = Nyx.Logistics.CalculateDecayedVelocity(shelf.sales_velocity, shelf.last_purchased_at)
    shelf.sales_velocity = math.floor((decayed + quantity) * 100) / 100
    shelf.last_purchased_at = now

    MySQL.prepare([[
        UPDATE `nyx_logistics_shelves`
        SET `sales_velocity` = ?, `last_purchased_at` = FROM_UNIXTIME(?)
        WHERE `shelf_id` = ?
    ]], { shelf.sales_velocity, now, shelf.id })
end

-- Compute Effective Demand: D_eff = C_target * M_zone * (1 + alpha_vel * V_ratio)
function Nyx.Logistics.GetEffectiveDemand(targetCapacity, zoneId, shelf)
    targetCapacity = math.max(1, tonumber(targetCapacity) or 100)
    local zone = Nyx.Logistics.GetZone(zoneId)
    local zoneDemandMult = zone and zone.baseDemandMultiplier or 1.00

    local velRatio = 0.0
    if shelf and shelf.sales_velocity and shelf.sales_velocity > 0 then
        local decayedVel = Nyx.Logistics.CalculateDecayedVelocity(shelf.sales_velocity, shelf.last_purchased_at)
        shelf.sales_velocity = decayedVel

        -- Benchmark velocity relative to 25% of shelf target capacity
        local velocityBase = math.max(1.0, targetCapacity * 0.25)
        local impactFactor = (Config.DeliveryZones and Config.DeliveryZones.VelocityImpactFactor) or 0.25
        local maxVelMult = (Config.DeliveryZones and Config.DeliveryZones.MaxVelocityMultiplier) or 2.0

        velRatio = math.min(maxVelMult, (decayedVel / velocityBase) * impactFactor)
    end

    local effectiveDemand = targetCapacity * zoneDemandMult * (1.0 + velRatio)
    return math.floor(effectiveDemand * 100) / 100, zoneDemandMult, velRatio
end

-- Calculate Stock-to-Demand Ratio (R_sd = S_current / D_eff)
function Nyx.Logistics.GetStockToDemandRatio(currentStock, effectiveDemand)
    currentStock = math.max(0, tonumber(currentStock) or 0)
    effectiveDemand = math.max(1.0, tonumber(effectiveDemand) or 1.0)

    local ratio = currentStock / effectiveDemand
    return math.floor(ratio * 10000) / 10000
end

-- Calculate Regional Consumer Price Index (CPI) and Market Health for a Delivery Zone
function Nyx.Logistics.GetZoneMarketIndex(zoneId)
    zoneId = zoneId or "zone_ls_metro"
    local zone = Nyx.Logistics.GetZone(zoneId)
    if not zone then return nil, "ZONE_NOT_FOUND" end

    local totalBase = 0.0
    local totalCurrent = 0.0
    local totalStock = 0
    local totalEffectiveDemand = 0.0
    local shelfCount = 0

    if Nyx.Logistics.Shelves then
        for _, s in pairs(Nyx.Logistics.Shelves) do
            local sZone = s.zone_id or "zone_ls_metro"
            if sZone == zoneId then
                shelfCount = shelfCount + 1
                local stock = exports['nyx_inventory']:GetItemCount(s.inventory_id, s.item_id)
                local effDemand = Nyx.Logistics.GetEffectiveDemand(s.target_capacity, zoneId, s)

                totalBase = totalBase + s.base_price
                totalCurrent = totalCurrent + (s.current_price or s.base_price)
                totalStock = totalStock + stock
                totalEffectiveDemand = totalEffectiveDemand + effDemand
            end
        end
    end

    local cpi = 1.00
    if totalBase > 0 then
        cpi = math.floor((totalCurrent / totalBase) * 10000) / 10000
    end

    local aggRatio = 1.00
    if totalEffectiveDemand > 0 then
        aggRatio = math.floor((totalStock / totalEffectiveDemand) * 10000) / 10000
    end

    local healthStatus = "EQUILIBRIUM"
    if aggRatio < 0.25 then
        healthStatus = "CRITICAL_DEFICIT"
    elseif aggRatio < 0.65 then
        healthStatus = "MODERATE_SHORTAGE"
    elseif aggRatio > 1.35 then
        healthStatus = "SURPLUS"
    end

    return {
        zoneId = zoneId,
        zoneName = zone.name,
        shelfCount = shelfCount,
        cpi = cpi,
        stockToDemandRatio = aggRatio,
        healthStatus = healthStatus,
        totalStock = totalStock,
        effectiveDemand = math.floor(totalEffectiveDemand * 100) / 100,
        baseDemandMultiplier = zone.baseDemandMultiplier,
        taxSurcharge = zone.taxSurcharge
    }
end

-- Periodic Heartbeat: Decay Shelf Velocities (Runs every 60s)
CreateThread(function()
    while true do
        Wait(60000)
        if Nyx.Logistics.Shelves then
            for _, shelf in pairs(Nyx.Logistics.Shelves) do
                if shelf.sales_velocity and shelf.sales_velocity > 0 then
                    local decayed = Nyx.Logistics.CalculateDecayedVelocity(shelf.sales_velocity, shelf.last_purchased_at)
                    if math.abs(decayed - shelf.sales_velocity) >= 0.05 then
                        shelf.sales_velocity = decayed
                        -- Recalibrate shelf price if velocity changed significantly
                        local stock = exports['nyx_inventory']:GetItemCount(shelf.inventory_id, shelf.item_id)
                        local newPrice = Nyx.Logistics.CalculateShelfPrice(shelf.base_price, shelf.target_capacity, stock, shelf.zone_id, shelf.item_id, shelf)
                        if newPrice ~= shelf.current_price then
                            shelf.current_price = newPrice
                            TriggerClientEvent("nyx:logistics:client:shelfUpdated", -1, shelf.id, newPrice, stock, shelf.zone_id)
                        end
                    end
                end
            end
        end
    end
end)

-- ----------------------------------------------------------------------------
-- RPC Endpoints for Localized Demand & Market Overview
-- ----------------------------------------------------------------------------

-- RPC: Query All Delivery Zones with Market Statistics
Nyx.RPC.Register("logistics:getZoneList", function(src)
    local zonesList = {}
    for zoneId, _ in pairs(Nyx.Logistics.Zones) do
        local stats = Nyx.Logistics.GetZoneMarketIndex(zoneId)
        if stats then
            zonesList[#zonesList + 1] = stats
        end
    end
    return {
        success = true,
        zones = zonesList
    }
end)

-- RPC: Query Specific Zone Demand Metrics
Nyx.RPC.Register("logistics:getZoneDemand", function(src, zoneId)
    local stats, err = Nyx.Logistics.GetZoneMarketIndex(zoneId)
    if not stats then
        return { success = false, error = err or "ZONE_NOT_FOUND" }
    end
    return {
        success = true,
        data = stats
    }
end)

-- RPC: Overall City Market Summary
Nyx.RPC.Register("logistics:getMarketSummary", function(src)
    local totalShelves = 0
    local totalBaseSum = 0.0
    local totalCurrentSum = 0.0
    local zoneSummaries = {}

    for zoneId, _ in pairs(Nyx.Logistics.Zones) do
        local zInfo = Nyx.Logistics.GetZoneMarketIndex(zoneId)
        if zInfo then
            zoneSummaries[#zoneSummaries + 1] = zInfo
            totalShelves = totalShelves + zInfo.shelfCount
        end
    end

    if Nyx.Logistics.Shelves then
        for _, s in pairs(Nyx.Logistics.Shelves) do
            totalBaseSum = totalBaseSum + s.base_price
            totalCurrentSum = totalCurrentSum + (s.current_price or s.base_price)
        end
    end

    local citywideCpi = totalBaseSum > 0 and (math.floor((totalCurrentSum / totalBaseSum) * 10000) / 10000) or 1.0

    return {
        success = true,
        citywideCpi = citywideCpi,
        totalShelves = totalShelves,
        zones = zoneSummaries,
        serverTime = os.time()
    }
end)
