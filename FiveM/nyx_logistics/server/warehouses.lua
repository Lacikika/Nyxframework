--[[
    Nyxframework: nyx_logistics
    File: server/warehouses.lua
    Description: Physical warehouse interiors, dedicated Virtual Routing Bucket isolation,
                 and 3D shelf matrix node persistence.
]]

Nyx = Nyx or {}
Nyx.Warehouses = Nyx.Warehouses or {}

Nyx.Warehouses.Loaded = {}          -- [warehouseId] = warehouseData
Nyx.Warehouses.Shelves = {}         -- [shelfId] = shelfData
Nyx.Warehouses.Nodes = {}           -- [nodeId] = nodeData
Nyx.Warehouses.Buckets = {}         -- [routingBucket] = warehouseId
Nyx.Warehouses.PlayerLocations = {} -- [src] = warehouseId

-- Table deep copy utility
local function deepCopy(orig)
    if type(orig) ~= 'table' then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == 'table' and deepCopy(v) or v
    end
    return copy
end

-- Parse JSON safely with fallback
local function safeDecode(raw, fallback)
    if not raw or raw == "" then return fallback end
    local ok, res = pcall(json.decode, raw)
    return (ok and res) and res or fallback
end

--- Synchronize a shelf snap node occupancy state across database and memory.
function Nyx.Warehouses.SetNodeOccupant(nodeId, dropId, itemData)
    local node = Nyx.Warehouses.Nodes[nodeId]
    if not node then return false, "NODE_NOT_FOUND" end

    node.occupiedDropId = dropId
    node.itemData = itemData

    -- Persist to database
    MySQL.query([[
        INSERT INTO `nyx_logistics_shelf_nodes` 
        (`node_id`, `shelf_id`, `warehouse_id`, `tier`, `slot`, `world_coords`, `heading`, `occupied_drop_id`, `routing_bucket`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE 
        `occupied_drop_id` = VALUES(`occupied_drop_id`),
        `routing_bucket` = VALUES(`routing_bucket`),
        `updated_at` = CURRENT_TIMESTAMP
    ]], {
        node.id,
        node.shelfId,
        node.warehouseId,
        node.tier,
        node.slot,
        json.encode(node.worldCoords),
        node.heading,
        dropId,
        node.routingBucket
    })

    -- Broadcast state update to clients
    TriggerClientEvent("nyx:logistics:client:shelfNodeUpdated", -1, node.warehouseId, node.shelfId, node.id, dropId, itemData)

    if Config.Debug then
        print(string.format("^2[Nyx:Warehouses] Node '%s' now occupied by drop '%s'^7", node.id, tostring(dropId)))
    end

    return true
end

--- Free a shelf snap node when a container is removed or moved away.
function Nyx.Warehouses.ClearNode(nodeId)
    local node = Nyx.Warehouses.Nodes[nodeId]
    if not node then return false, "NODE_NOT_FOUND" end

    node.occupiedDropId = nil
    node.itemData = nil

    MySQL.query([[
        UPDATE `nyx_logistics_shelf_nodes` 
        SET `occupied_drop_id` = NULL 
        WHERE `node_id` = ?
    ]], { nodeId })

    TriggerClientEvent("nyx:logistics:client:shelfNodeUpdated", -1, node.warehouseId, node.shelfId, node.id, nil, nil)

    if Config.Debug then
        print(string.format("^3[Nyx:Warehouses] Freed shelf snap node '%s'^7", nodeId))
    end

    return true
end

-- Bootloader: Hydrate warehouses, shelf matrix grids, and occupied drop associations
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end

    -- 1. Load Warehouses
    local whRows = MySQL.query.await("SELECT * FROM `nyx_logistics_warehouses`")
    if whRows then
        for _, row in ipairs(whRows) do
            local extCoords = safeDecode(row.exterior_coords, { x = 0.0, y = 0.0, z = 0.0, h = 0.0 })
            local intCoords = safeDecode(row.interior_coords, { x = 0.0, y = 0.0, z = 0.0, h = 0.0 })
            local bucket = tonumber(row.routing_bucket) or 3000

            Nyx.Warehouses.Loaded[row.warehouse_id] = {
                id = row.warehouse_id,
                name = row.name,
                owner = row.owner_faction_id,
                zoneId = row.zone_id or "zone_ls_metro",
                exteriorCoords = extCoords,
                interiorCoords = intCoords,
                routingBucket = bucket,
                isLocked = (tonumber(row.is_locked) == 1),
                shelves = {},
                nodes = {}
            }
            Nyx.Warehouses.Buckets[bucket] = row.warehouse_id

            -- Configure Virtual Routing Bucket (zero ambient population, preserve manual entities)
            if SetRoutingBucketPopulationEnabled then
                SetRoutingBucketPopulationEnabled(bucket, false)
            end
            if SetRoutingBucketEntityLockdownMode then
                SetRoutingBucketEntityLockdownMode(bucket, "relaxed")
            end
        end
    end

    -- 2. Load Shelves & Calculate 3D Matrix Nodes
    local shelfRows = MySQL.query.await("SELECT * FROM `nyx_logistics_warehouse_shelves`")
    if shelfRows then
        for _, sRow in ipairs(shelfRows) do
            local sCoords = safeDecode(sRow.coords, { x = 0.0, y = 0.0, z = 0.0 })
            local sRot = safeDecode(sRow.rotation, { heading = 0.0 })
            local sBucket = tonumber(sRow.routing_bucket) or 0

            local shelfObj = {
                id = sRow.shelf_id,
                warehouseId = sRow.warehouse_id,
                label = sRow.label or "Shelf Unit",
                model = sRow.model or "prop_rub_cabinet02",
                coords = sCoords,
                rotation = sRot,
                heading = tonumber(sRot.heading or sRot.z) or 0.0,
                tiers = tonumber(sRow.tiers) or 3,
                slotsPerTier = tonumber(sRow.slots_per_tier) or 3,
                tierSpacing = tonumber(sRow.tier_spacing) or 0.50,
                slotSpacing = tonumber(sRow.slot_spacing) or 0.55,
                tierBaseZ = tonumber(sRow.tier_base_z) or 0.35,
                depthOffset = tonumber(sRow.depth_offset) or 0.05,
                routingBucket = sBucket
            }

            Nyx.Warehouses.Shelves[sRow.shelf_id] = shelfObj

            -- Calculate 3D snap grid nodes
            local nodesMap, nodesList = Nyx.Warehouses.CalculateShelfNodes(shelfObj)
            for nodeId, nodeData in pairs(nodesMap) do
                Nyx.Warehouses.Nodes[nodeId] = nodeData
            end

            local wh = Nyx.Warehouses.Loaded[sRow.warehouse_id]
            if wh then
                wh.shelves[sRow.shelf_id] = shelfObj
                for nodeId, nodeData in pairs(nodesMap) do
                    wh.nodes[nodeId] = nodeData
                end
            end
        end
    end

    -- 3. Hydrate Occupied Drop Attachments from Database
    local dropRows = MySQL.query.await("SELECT `id`, `shelf_node_id` FROM `nyx_inventories` WHERE `shelf_node_id` IS NOT NULL AND `shelf_node_id` != ''")
    if dropRows then
        for _, dRow in ipairs(dropRows) do
            local nodeId = dRow.shelf_node_id
            if Nyx.Warehouses.Nodes[nodeId] then
                Nyx.Warehouses.Nodes[nodeId].occupiedDropId = dRow.id
            end
        end
    end

    local whCount = 0
    for _ in pairs(Nyx.Warehouses.Loaded) do whCount = whCount + 1 end
    local nodeCount = 0
    for _ in pairs(Nyx.Warehouses.Nodes) do nodeCount = nodeCount + 1 end

    print(string.format("^2[Nyx:Logistics] Loaded %d warehouses with %d physical 3D shelf matrix snap nodes.^7", whCount, nodeCount))
end)

-- RPC: Enter Warehouse Interior (Switches to Dedicated Virtual Routing Bucket)
Nyx.RPC.Register("logistics:enterWarehouse", function(src, warehouseId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local wh = Nyx.Warehouses.Loaded[warehouseId]
    if not wh then return { success = false, error = "WAREHOUSE_NOT_FOUND" } end

    local ped = GetPlayerPed(tostring(src))
    local pCoords = GetEntityCoords(ped)
    local extVec = vector3(wh.exteriorCoords.x, wh.exteriorCoords.y, wh.exteriorCoords.z)

    if #(pCoords - extVec) > 6.0 then
        return { success = false, error = "TOO_FAR_FROM_ENTRANCE" }
    end

    if wh.isLocked then
        -- Check faction access
        local playerFaction = player:getFaction()
        if not playerFaction or (wh.owner and playerFaction ~= wh.owner) then
            return { success = false, error = "WAREHOUSE_LOCKED" }
        end
    end

    -- 1. Isolate Player into Virtual Routing Bucket
    exports['nyx_core']:SetRoutingBucket(src, wh.routingBucket)

    -- 2. Teleport Ped into Warehouse Interior
    SetEntityCoords(ped, wh.interiorCoords.x, wh.interiorCoords.y, wh.interiorCoords.z, false, false, false, true)
    if wh.interiorCoords.h then
        SetEntityHeading(ped, wh.interiorCoords.h)
    end

    Nyx.Warehouses.PlayerLocations[src] = warehouseId

    -- 3. Gather drops residing in this routing bucket
    local bucketDrops = {}
    if Nyx.Drops then
        for dropId, dData in pairs(Nyx.Drops) do
            if dData.routingBucket == wh.routingBucket then
                bucketDrops[#bucketDrops + 1] = dData
            end
        end
    end

    -- 4. Sync warehouse layout and drops to client
    TriggerClientEvent("nyx:logistics:client:syncWarehouseInterior", src, wh.id, wh.routingBucket, wh.shelves, wh.nodes)
    TriggerClientEvent("nyx:inventory:client:syncDrops", src, bucketDrops)

    return {
        success = true,
        warehouseId = wh.id,
        interiorCoords = wh.interiorCoords,
        routingBucket = wh.routingBucket,
        shelves = wh.shelves,
        nodes = wh.nodes
    }
end)

-- RPC: Exit Warehouse Interior (Restores Overworld Routing Bucket 0)
Nyx.RPC.Register("logistics:exitWarehouse", function(src, warehouseId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local wh = Nyx.Warehouses.Loaded[warehouseId]
    if not wh then
        -- Lookup by player's current location if not passed
        local currentWhId = Nyx.Warehouses.PlayerLocations[src]
        if currentWhId then wh = Nyx.Warehouses.Loaded[currentWhId] end
    end
    if not wh then return { success = false, error = "WAREHOUSE_NOT_FOUND" } end

    local ped = GetPlayerPed(tostring(src))
    local pCoords = GetEntityCoords(ped)
    local intVec = vector3(wh.interiorCoords.x, wh.interiorCoords.y, wh.interiorCoords.z)

    if #(pCoords - intVec) > 10.0 then
        return { success = false, error = "TOO_FAR_FROM_EXIT" }
    end

    -- 1. Restore Public Overworld Routing Bucket 0
    exports['nyx_core']:SetDefaultBucket(src)

    -- 2. Teleport Ped back to Street Entrance
    SetEntityCoords(ped, wh.exteriorCoords.x, wh.exteriorCoords.y, wh.exteriorCoords.z, false, false, false, true)
    if wh.exteriorCoords.h then
        SetEntityHeading(ped, wh.exteriorCoords.h)
    end

    Nyx.Warehouses.PlayerLocations[src] = nil

    -- 3. Inform client to clean up interior entities
    TriggerClientEvent("nyx:logistics:client:exitWarehouseCleanup", src)

    -- 4. Re-sync Overworld Bucket 0 drops
    local overworldDrops = {}
    if Nyx.Drops then
        for dropId, dData in pairs(Nyx.Drops) do
            if not dData.routingBucket or dData.routingBucket == 0 then
                overworldDrops[#overworldDrops + 1] = dData
            end
        end
    end
    TriggerClientEvent("nyx:inventory:client:syncDrops", src, overworldDrops)

    return {
        success = true,
        exteriorCoords = wh.exteriorCoords
    }
end)

-- RPC: Query Warehouse State & Active Shelf Nodes
Nyx.RPC.Register("logistics:getWarehouseState", function(src, warehouseId)
    local wh = Nyx.Warehouses.Loaded[warehouseId]
    if not wh then return nil, "WAREHOUSE_NOT_FOUND" end

    return {
        id = wh.id,
        name = wh.name,
        zoneId = wh.zoneId,
        routingBucket = wh.routingBucket,
        isLocked = wh.isLocked,
        shelves = wh.shelves,
        nodes = wh.nodes
    }
end)

-- RPC: Dynamic Snap Node Query
Nyx.RPC.Register("logistics:getNearbySnapNode", function(src, coords, maxDist, currentDropId)
    local bucket = exports['nyx_core']:GetRoutingBucket(src)
    local warehouseId = Nyx.Warehouses.Buckets[bucket]
    if not warehouseId then return nil end

    local wh = Nyx.Warehouses.Loaded[warehouseId]
    if not wh then return nil end

    local node, dist = Nyx.Warehouses.FindNearestSnapNode(wh.nodes, coords, maxDist or 0.85, currentDropId)
    return node, dist
end)

-- Disconnect cleanup
AddEventHandler("playerDropped", function()
    local src = source
    Nyx.Warehouses.PlayerLocations[src] = nil
end)

-- Server Exports for Cross-Resource Interop
exports("GetWarehouse", function(warehouseId)
    return Nyx.Warehouses.Loaded[warehouseId]
end)

exports("GetWarehouseByBucket", function(bucketId)
    local whId = Nyx.Warehouses.Buckets[tonumber(bucketId)]
    return whId and Nyx.Warehouses.Loaded[whId] or nil
end)

exports("GetPlayerWarehouse", function(src)
    local whId = Nyx.Warehouses.PlayerLocations[tonumber(src)]
    return whId and Nyx.Warehouses.Loaded[whId] or nil
end)

exports("GetShelfNode", function(nodeId)
    return Nyx.Warehouses.Nodes[tostring(nodeId)]
end)

exports("SetShelfNodeOccupant", function(nodeId, dropId, itemData)
    return Nyx.Warehouses.SetNodeOccupant(tostring(nodeId), dropId, itemData)
end)

exports("ClearShelfNode", function(nodeId)
    return Nyx.Warehouses.ClearNode(tostring(nodeId))
end)

exports("GetAllWarehouses", function()
    return Nyx.Warehouses.Loaded
end)
