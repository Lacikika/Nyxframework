--[[
    Nyxframework: nyx_logistics
    File: server/market_monitor.lua
    Description: Authoritative server-side warehouse matrix aggregation, real-time
                 elastic market telemetry, hauler route dispatching, and slot reservation.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Warehouses = Nyx.Warehouses or {}

-- Defensive RPC registration helper
local function registerRPC(name, handler)
    if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
        exports['nyx_core']:RegisterRPC(name, handler)
    elseif Nyx.RPC and Nyx.RPC.Register then
        Nyx.RPC.Register(name, handler)
    end
end

--- Aggregates complete 3D warehouse matrix telemetry for the web visualizer.
--- @param warehouseId string|nil
--- @return table
function Nyx.Logistics.GetWarehouseMatrixOverview(warehouseId)
    local loadedWarehouses = Nyx.Warehouses.Loaded or {}
    local whList = {}

    for whId, wh in pairs(loadedWarehouses) do
        local shelfCount = 0
        local totalNodes = 0
        local occupiedNodes = 0

        if wh.shelves then
            for _, _ in pairs(wh.shelves) do shelfCount = shelfCount + 1 end
        end
        if wh.nodes then
            for _, n in pairs(wh.nodes) do
                totalNodes = totalNodes + 1
                if n.occupiedDropId then occupiedNodes = occupiedNodes + 1 end
            end
        end

        whList[#whList + 1] = {
            id = wh.id,
            name = wh.name,
            zoneId = wh.zoneId,
            routingBucket = wh.routingBucket,
            isLocked = wh.isLocked,
            shelfCount = shelfCount,
            totalSlots = totalNodes,
            occupiedSlots = occupiedNodes,
            availableSlots = math.max(0, totalNodes - occupiedNodes)
        }
    end

    -- Pick selected warehouse or default to first
    local targetWhId = warehouseId or (whList[1] and whList[1].id) or "wh_dock_ls_01"
    local selectedWh = loadedWarehouses[targetWhId]
    local shelvesData = {}
    local nodesData = {}

    if selectedWh then
        if selectedWh.shelves then
            for sId, sObj in pairs(selectedWh.shelves) do
                shelvesData[#shelvesData + 1] = {
                    id = sObj.id,
                    warehouseId = sObj.warehouseId,
                    label = sObj.label,
                    model = sObj.model,
                    tiers = sObj.tiers,
                    slotsPerTier = sObj.slotsPerTier,
                    coords = sObj.coords,
                    heading = sObj.heading
                }
            end
        end

        if selectedWh.nodes then
            for nId, nObj in pairs(selectedWh.nodes) do
                local slotStatus = nObj.occupiedDropId and "occupied" or "available"
                local itemInfo = nObj.itemData or nil

                -- If occupied but itemInfo not cached, query inventory metadata
                if nObj.occupiedDropId and not itemInfo and exports['nyx_inventory'] and exports['nyx_inventory'].GetInventory then
                    local inv = exports['nyx_inventory']:GetInventory(nObj.occupiedDropId)
                    if inv and inv.items then
                        for _, itm in pairs(inv.items) do
                            itemInfo = {
                                itemId = itm.name or itm.itemId or "item_crate",
                                label = itm.label or itm.name or "Freight Crate",
                                count = itm.count or 1,
                                weight = itm.weight or 10.0,
                                durability = itm.durability or 100
                            }
                            break
                        end
                    end
                end

                -- Compute 2D isometric projection for web canvas
                local shelfObj = selectedWh.shelves and selectedWh.shelves[nObj.shelfId]
                local tiersCount = shelfObj and shelfObj.tiers or 3
                local slotsCount = shelfObj and shelfObj.slotsPerTier or 3
                local projection = Nyx.LogisticsMarket.ProjectIsometricSlot(nObj.tier, nObj.slot, tiersCount, slotsCount)

                nodesData[#nodesData + 1] = {
                    id = nObj.id,
                    shelfId = nObj.shelfId,
                    warehouseId = nObj.warehouseId,
                    shelfLabel = nObj.shelfLabel or "Shelf Unit",
                    tier = nObj.tier,
                    slot = nObj.slot,
                    isoX = projection.isoX,
                    isoY = projection.isoY,
                    layer = projection.layer,
                    status = slotStatus,
                    temperatureZone = nObj.temperatureZone or "ambient",
                    occupiedDropId = nObj.occupiedDropId,
                    item = itemInfo,
                    worldCoords = nObj.worldCoords,
                    localOffset = nObj.localOffset
                }
            end
        end
    end

    return {
        success = true,
        selectedWarehouseId = targetWhId,
        warehouses = whList,
        shelves = shelvesData,
        nodes = nodesData,
        serverTime = os.time()
    }
end

--- Aggregates regional economic delivery zones, elastic pricing, and commodity stocks.
--- @param filterZoneId string|nil
--- @return table
function Nyx.Logistics.GetMarketMonitorOverview(filterZoneId)
    local zonesList = {}
    local commoditiesList = {}
    local totalShelvesCount = 0
    local deficitCount = 0
    local surplusCount = 0

    -- 1. Gather Regional Delivery Zones
    local zonesMap = Nyx.Logistics.Zones or Nyx.Logistics.DefaultZones or {}
    for zoneId, z in pairs(zonesMap) do
        local stats = Nyx.Logistics.GetZoneMarketIndex and Nyx.Logistics.GetZoneMarketIndex(zoneId)
        if stats then
            local badge = Nyx.LogisticsMarket.FormatHealthBadge(stats.stockToDemandRatio)
            stats.badge = badge
            zonesList[#zonesList + 1] = stats

            if stats.healthStatus == "CRITICAL_DEFICIT" or stats.healthStatus == "MODERATE_SHORTAGE" then
                deficitCount = deficitCount + 1
            elseif stats.healthStatus == "SURPLUS" then
                surplusCount = surplusCount + 1
            end
        end
    end

    -- 2. Gather Commodity Shelves
    if Nyx.Logistics.Shelves then
        for _, s in pairs(Nyx.Logistics.Shelves) do
            totalShelvesCount = totalShelvesCount + 1
            local sZone = s.zone_id or "zone_ls_metro"

            if not filterZoneId or filterZoneId == "all" or filterZoneId == sZone then
                local stock = 0
                if exports['nyx_inventory'] and exports['nyx_inventory'].GetItemCount then
                    stock = exports['nyx_inventory']:GetItemCount(s.inventory_id, s.item_id)
                end

                local zoneObj = zonesMap[sZone]
                local zoneMult = zoneObj and zoneObj.baseDemandMultiplier or 1.00

                local elasticity = Nyx.LogisticsMarket.ComputeElasticPrice(
                    s.base_price,
                    s.target_capacity,
                    stock,
                    zoneMult,
                    s.sales_velocity or 0.0,
                    0.25
                )

                local healthBadge = Nyx.LogisticsMarket.FormatHealthBadge(elasticity.stockToDemandRatio)

                commoditiesList[#commoditiesList + 1] = {
                    shelfId = s.id,
                    storeId = s.store_id or "general",
                    zoneId = sZone,
                    zoneName = zoneObj and zoneObj.name or sZone,
                    itemId = s.item_id,
                    name = s.label or s.item_id,
                    category = s.category or "goods",
                    basePrice = s.base_price,
                    currentPrice = elasticity.calculatedPrice,
                    priceMultiplier = elasticity.priceMultiplier,
                    currentStock = stock,
                    targetCapacity = s.target_capacity,
                    effectiveDemand = elasticity.effectiveDemand,
                    stockToDemandRatio = elasticity.stockToDemandRatio,
                    deficitUnits = elasticity.deficitUnits,
                    salesVelocity = s.sales_velocity or 0.0,
                    healthBadge = healthBadge
                }
            end
        end
    end

    -- Compute Citywide Index
    local citySummary = Nyx.Logistics.GetMarketSummary and Nyx.Logistics.GetMarketSummary()

    return {
        success = true,
        zones = zonesList,
        commodities = commoditiesList,
        citywideCpi = citySummary and citySummary.citywideCpi or 1.00,
        totalShelves = totalShelvesCount,
        activeDeficitZones = deficitCount,
        activeSurplusZones = surplusCount,
        serverTime = os.time()
    }
end

--- Computes lucrative regional arbitrage routes between depots and deficit zones.
--- @param src number|nil Caller player source
--- @return table
function Nyx.Logistics.GetHaulerArbitrageRoutes(src)
    local routes = {}
    local zonesMap = Nyx.Logistics.Zones or Nyx.Logistics.DefaultZones or {}

    -- Identify top arbitrage commodities
    local candidates = {
        { itemId = "repairkit", name = "Standard Vehicle Repair Kit", originWh = "wh_dock_ls_01", destZone = "zone_ls_metro", baseCost = 65.0, distanceKm = 6.5 },
        { itemId = "medikit", name = "Emergency Medical Trauma Kit", originWh = "wh_dock_ls_01", destZone = "zone_sandy_shores", baseCost = 90.0, distanceKm = 14.2 },
        { itemId = "refined_copper", name = "Industrial Refined Copper Wire", originWh = "wh_sandy_dist_01", destZone = "zone_port_industrial", baseCost = 45.0, distanceKm = 16.0 },
        { itemId = "first_aid_pack", name = "Field First Aid Pack", originWh = "wh_dock_ls_01", destZone = "zone_paleto_bay", baseCost = 35.0, distanceKm = 22.0 }
    }

    for _, c in ipairs(candidates) do
        local destZoneObj = zonesMap[c.destZone]
        local zoneMult = destZoneObj and destZoneObj.baseDemandMultiplier or 1.0

        -- Compute target retail price with deficit premium
        local elasticity = Nyx.LogisticsMarket.ComputeElasticPrice(c.baseCost * 1.5, 100, 30, zoneMult, 12.0)
        local destPrice = elasticity.calculatedPrice

        local arb = Nyx.LogisticsMarket.CalculateHaulerArbitrage(c.baseCost, destPrice, 20, c.distanceKm, 3.50)

        routes[#routes + 1] = {
            routeId = string.format("route_%s_%s", c.originWh, c.destZone),
            originWarehouseId = c.originWh,
            originName = (c.originWh == "wh_dock_ls_01") and "Port of Los Santos Terminal 4" or "Sandy Shores Freight Depot",
            destinationZoneId = c.destZone,
            destinationName = destZoneObj and destZoneObj.name or c.destZone,
            itemId = c.itemId,
            itemName = c.name,
            recommendedUnits = 20,
            unitCost = c.baseCost,
            targetPrice = destPrice,
            unitSpread = arb.unitSpread,
            grossProfit = arb.grossProfit,
            fuelCost = arb.fuelCost,
            projectedProfit = arb.netProfit,
            roiPct = arb.roiPct,
            rating = arb.rating,
            distanceKm = c.distanceKm
        }
    end

    -- Query active dispatches for caller if citizen known
    local myDispatches = {}
    if src then
        local player = exports['nyx_core']:GetPlayer(src)
        if player then
            local citId = player:getCitizenId()
            local rows = MySQL.query.await([[
                SELECT * FROM `nyx_logistics_hauler_dispatches`
                WHERE `hauler_citizen_id` = ? AND `status` IN ('claimed', 'loaded')
                ORDER BY `claimed_at` DESC LIMIT 10
            ]], { citId })

            if rows then
                for _, r in ipairs(rows) do
                    myDispatches[#myDispatches + 1] = {
                        dispatchId = r.dispatch_id,
                        originWarehouseId = r.origin_warehouse_id,
                        destinationZoneId = r.destination_zone_id,
                        itemId = r.item_id,
                        units = r.units,
                        unitCost = tonumber(r.unit_cost),
                        targetPrice = tonumber(r.target_price),
                        projectedProfit = tonumber(r.projected_profit),
                        status = r.status,
                        claimedAt = r.claimed_at
                    }
                end
            end
        end
    end

    return {
        success = true,
        routes = routes,
        myDispatches = myDispatches,
        serverTime = os.time()
    }
end

--- Books a new authoritative hauler dispatch route.
--- @param src number
--- @param payload table
--- @return table
function Nyx.Logistics.BookHaulerDispatch(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local valid, sanitized, err = Nyx.LogisticsMarket.ValidateDispatchPayload(payload)
    if not valid then
        return { success = false, error = err or "INVALID_DISPATCH_PAYLOAD" }
    end

    local citId = player:getCitizenId()
    local unitCost = tonumber(payload.unitCost) or 50.0
    local targetPrice = tonumber(payload.targetPrice) or 80.0
    local projectedProfit = tonumber(payload.projectedProfit) or ((targetPrice - unitCost) * sanitized.units)
    local fuelSurcharge = tonumber(payload.fuelSurcharge) or 25.0

    local insertId = MySQL.insert.await([[
        INSERT INTO `nyx_logistics_hauler_dispatches`
        (`hauler_citizen_id`, `origin_warehouse_id`, `destination_zone_id`, `item_id`, `units`, `unit_cost`, `target_price`, `projected_profit`, `fuel_surcharge`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'claimed')
    ]], {
        citId,
        sanitized.originWarehouseId,
        sanitized.destinationZoneId,
        sanitized.itemId,
        sanitized.units,
        unitCost,
        targetPrice,
        projectedProfit,
        fuelSurcharge
    })

    if not insertId or insertId <= 0 then
        return { success = false, error = "DATABASE_INSERT_FAILED" }
    end

    if exports['nyx_ui'] and exports['nyx_ui'].Notify then
        TriggerClientEvent("nyx:ui:notify", src, {
            type = "success",
            title = "HAULER DISPATCH",
            message = string.format("Fuvarmegbízás rögzítve (#%d): %d db %s szállításra kész.", insertId, sanitized.units, sanitized.itemId)
        })
    end

    return {
        success = true,
        dispatchId = insertId,
        originWarehouseId = sanitized.originWarehouseId,
        destinationZoneId = sanitized.destinationZoneId,
        units = sanitized.units,
        projectedProfit = projectedProfit
    }
end

--- Cancels an active hauler dispatch.
--- @param src number
--- @param dispatchId number
--- @return table
function Nyx.Logistics.CancelHaulerDispatch(src, dispatchId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local citId = player:getCitizenId()
    local dId = tonumber(dispatchId) or 0
    if dId <= 0 then return { success = false, error = "INVALID_DISPATCH_ID" } end

    local affected = MySQL.update.await([[
        UPDATE `nyx_logistics_hauler_dispatches`
        SET `status` = 'abandoned', `completed_at` = CURRENT_TIMESTAMP
        WHERE `dispatch_id` = ? AND `hauler_citizen_id` = ? AND `status` = 'claimed'
    ]], { dId, citId })

    if not affected or affected <= 0 then
        return { success = false, error = "DISPATCH_NOT_FOUND_OR_ACTIVE" }
    end

    return { success = true, dispatchId = dId }
end

--- Reserves a shelf snap node for dedicated storage.
--- @param src number
--- @param nodeId string
--- @param durationMinutes number
--- @return table
function Nyx.Logistics.ReserveShelfNode(src, nodeId, durationMinutes)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local node = Nyx.Warehouses.Nodes and Nyx.Warehouses.Nodes[tostring(nodeId)]
    if not node then return { success = false, error = "NODE_NOT_FOUND" } end

    if node.occupiedDropId then
        return { success = false, error = "NODE_ALREADY_OCCUPIED" }
    end

    local citId = player:getCitizenId()
    local mins = math.max(10, math.min(1440, tonumber(durationMinutes) or 60))
    local expireUnix = os.time() + (mins * 60)

    node.slotStatus = "reserved"
    node.reservedUntil = expireUnix
    node.reservedByCitizenId = citId

    MySQL.query([[
        UPDATE `nyx_logistics_shelf_nodes`
        SET `slot_status` = 'reserved',
            `reserved_until` = FROM_UNIXTIME(?),
            `reserved_by_citizen_id` = ?
        WHERE `node_id` = ?
    ]], { expireUnix, citId, nodeId })

    TriggerClientEvent("nyx:logistics:client:shelfNodeUpdated", -1, node.warehouseId, node.shelfId, node.id, nil, { status = "reserved" })

    return { success = true, nodeId = nodeId, reservedUntil = expireUnix }
end

-- ----------------------------------------------------------------------------
-- Register Authoritative RPC Endpoints
-- ----------------------------------------------------------------------------
registerRPC("logistics:getWarehouseMatrixOverview", function(src, warehouseId)
    return Nyx.Logistics.GetWarehouseMatrixOverview(warehouseId)
end)

registerRPC("logistics:getMarketMonitorOverview", function(src, zoneId)
    return Nyx.Logistics.GetMarketMonitorOverview(zoneId)
end)

registerRPC("logistics:getHaulerArbitrageRoutes", function(src)
    return Nyx.Logistics.GetHaulerArbitrageRoutes(src)
end)

registerRPC("logistics:bookHaulerDispatch", function(src, payload)
    return Nyx.Logistics.BookHaulerDispatch(src, payload)
end)

registerRPC("logistics:cancelHaulerDispatch", function(src, dispatchId)
    return Nyx.Logistics.CancelHaulerDispatch(src, dispatchId)
end)

registerRPC("logistics:reserveShelfNode", function(src, nodeId, durationMinutes)
    return Nyx.Logistics.ReserveShelfNode(src, nodeId, durationMinutes)
end)
