--[[
    Nyxframework: nyx_inventory
    File: server/drops.lua
    Description: Spatial grid ground drops manager with entity culling, orientation persistence,
                 smart weight-tiered fallback container models, and proximity auto-merging.
]]

Nyx = Nyx or {}
Nyx.Drops = Nyx.Drops or {} -- [dropId] = { id = dropId, coords = { x, y, z }, rotation = { x, y, z, heading }, model = "prop_..." }

-- Table deep copy utility
local function deepCopy(orig)
    if type(orig) ~= 'table' then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == 'table' and deepCopy(v) or v
    end
    return copy
end

-- Sanitize rotation angles and normalize heading (0 to 360 degrees)
local function sanitizeRotation(rotation)
    local heading = 0.0
    if type(rotation) == "table" then
        heading = tonumber(rotation.heading) or tonumber(rotation.z) or 0.0
    elseif type(rotation) == "number" then
        heading = rotation
    end
    heading = (heading % 360.0 + 360.0) % 360.0
    heading = math.floor(heading * 100) / 100
    return {
        x = 0.0,
        y = 0.0,
        z = heading,
        heading = heading
    }
end

-- Register and spawn a new physical ground drop container
function Nyx.Drops.Create(coords, itemData, rotation, modelOverride, routingBucket, shelfNodeId)
    local dropUuid = Nyx.RPC.GenerateNonce():sub(1, 8)
    local dropId = string.format("drop:%s", dropUuid)

    local safeCoords = {
        x = math.floor((coords.x or 0.0) * 100) / 100,
        y = math.floor((coords.y or 0.0) * 100) / 100,
        z = math.floor(((coords.z or 70.0) + (Config.DropZOffset or -0.95)) * 100) / 100
    }
    local safeRotation = sanitizeRotation(rotation)
    local safeBucket = tonumber(routingBucket) or 0
    local safeShelfNode = (shelfNodeId and shelfNodeId ~= "") and tostring(shelfNodeId) or nil

    local container = Nyx.Inventory.NewContainer(
        dropId,
        'drop',
        Config.Containers['drop'].maxWeight,
        Config.Containers['drop'].maxSlots,
        safeCoords
    )

    if itemData then
        container:setItem(1, itemData)
    end

    -- Determine optimal 3D model
    local model = modelOverride
    if not model then
        if Nyx.Drops.ResolveModel then
            model = Nyx.Drops.ResolveModel(itemData or container)
        else
            model = Config.DropModel or "prop_paper_bag_small"
        end
    end

    container:save()

    -- Index into authoritative spatial partitioning grid
    local cellKey = nil
    if Nyx.SpatialGrid and Nyx.SpatialGrid.Insert then
        cellKey = Nyx.SpatialGrid.Insert(dropId, safeCoords, safeBucket)
    end

    local now = os.time()
    -- Persist rotation, model, routing_bucket, shelf_node_id, grid_cell, and last_decay_at to database
    MySQL.query("UPDATE `nyx_inventories` SET `rotation` = ?, `model` = ?, `routing_bucket` = ?, `shelf_node_id` = ?, `grid_cell` = ?, `last_decay_at` = ? WHERE `id` = ?", {
        json.encode(safeRotation),
        model,
        safeBucket,
        safeShelfNode,
        cellKey,
        now,
        dropId
    })

    Nyx.Drops[dropId] = {
        id = dropId,
        coords = safeCoords,
        rotation = safeRotation,
        model = model,
        routingBucket = safeBucket,
        shelfNodeId = safeShelfNode,
        gridCell = cellKey,
        lastDecayAt = now
    }

    -- Broadcast to clients within streaming range
    TriggerClientEvent("nyx:inventory:client:dropCreated", -1, dropId, safeCoords, safeRotation, model, safeBucket, safeShelfNode, cellKey)

    if Config.Debug then
        print(string.format("^2[Nyx:Drops] Created world drop '%s' [%s] at (%.2f, %.2f, %.2f) h:%.1f bucket:%d cell:%s shelf:%s^7",
            dropId, model, safeCoords.x, safeCoords.y, safeCoords.z, safeRotation.heading, safeBucket, tostring(cellKey), tostring(safeShelfNode)))
    end

    return dropId
end

-- Update spatial coordinates and orientation of an existing drop (zero-packet placement release)
function Nyx.Drops.Update(dropId, coords, rotation, shelfNodeId)
    local drop = Nyx.Drops[dropId]
    if not drop then return false, "DROP_NOT_FOUND" end

    local safeCoords = {
        x = math.floor((coords.x or drop.coords.x or 0.0) * 100) / 100,
        y = math.floor((coords.y or drop.coords.y or 0.0) * 100) / 100,
        z = math.floor((coords.z or drop.coords.z or 70.0) * 100) / 100
    }
    local safeRotation = sanitizeRotation(rotation or drop.rotation)

    if shelfNodeId ~= nil then
        if shelfNodeId == false then
            drop.shelfNodeId = nil
        else
            drop.shelfNodeId = tostring(shelfNodeId)
        end
    end

    drop.coords = safeCoords
    drop.rotation = safeRotation

    -- Update spatial grid position and cell index
    local cellKey = nil
    if Nyx.SpatialGrid and Nyx.SpatialGrid.Update then
        cellKey = Nyx.SpatialGrid.Update(dropId, safeCoords, drop.routingBucket or 0)
    end
    drop.gridCell = cellKey

    local container = Nyx.Inventories[dropId]
    if container then
        container.coords = safeCoords
        container.gridCell = cellKey
    end

    -- Update database record
    MySQL.query("UPDATE `nyx_inventories` SET `coords` = ?, `rotation` = ?, `shelf_node_id` = ?, `grid_cell` = ? WHERE `id` = ?", {
        json.encode(safeCoords),
        json.encode(safeRotation),
        drop.shelfNodeId,
        cellKey,
        dropId
    })

    -- Broadcast position update to all clients
    TriggerClientEvent("nyx:inventory:client:dropMoved", -1, dropId, safeCoords, safeRotation, drop.shelfNodeId, cellKey)

    if Config.Debug then
        print(string.format("^2[Nyx:Drops] Moved world drop '%s' to (%.2f, %.2f, %.2f) h:%.1f cell:%s shelf:%s^7",
            dropId, safeCoords.x, safeCoords.y, safeCoords.z, safeRotation.heading, tostring(cellKey), tostring(drop.shelfNodeId)))
    end

    return true
end

-- Update 3D model of an existing drop container
function Nyx.Drops.UpdateModel(dropId, newModel)
    local drop = Nyx.Drops[dropId]
    if not drop or not newModel or drop.model == newModel then return false end

    drop.model = newModel
    MySQL.query("UPDATE `nyx_inventories` SET `model` = ? WHERE `id` = ?", {
        newModel,
        dropId
    })

    TriggerClientEvent("nyx:inventory:client:dropModelUpdated", -1, dropId, newModel)

    if Config.Debug then
        print(string.format("^2[Nyx:Drops] Updated world drop '%s' model to '%s'^7", dropId, newModel))
    end

    return true
end

-- Recalculate and update the smart fallback model for an existing drop container
function Nyx.Drops.RecalculateModel(dropId)
    local drop = Nyx.Drops[dropId]
    local container = Nyx.Inventories[dropId]
    if not drop or not container or not Nyx.Drops.ResolveModel then return end

    local optimalModel = Nyx.Drops.ResolveModel(container)
    if optimalModel and optimalModel ~= drop.model then
        Nyx.Drops.UpdateModel(dropId, optimalModel)
    end
end

-- Find a candidate drop container for proximity auto-merging within 1.5m
function Nyx.Drops.FindAutoMergeTarget(coords, itemData, maxDist, excludeDropId)
    maxDist = tonumber(maxDist) or Config.DropAutoMergeDistance or 1.5
    if not coords or not coords.x or not coords.y or not coords.z then
        return nil
    end

    local cx, cy, cz = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    local neededWeight = 0
    if itemData and itemData.item_id and Nyx.Items and Nyx.Items.GetWeight then
        neededWeight = Nyx.Items.GetWeight(itemData.item_id, itemData.amount or 1)
    end

    local bestIdenticalDropId, bestIdenticalDist = nil, 999.0
    local bestCompatibleDropId, bestCompatibleDist = nil, 999.0

    local candidates = {}
    local bucket = (coords.routingBucket or coords.bucket or 0)

    if Nyx.SpatialGrid and Nyx.SpatialGrid.GetNearbyDrops then
        local nearby = Nyx.SpatialGrid.GetNearbyDrops(coords, maxDist, bucket)
        for _, n in ipairs(nearby) do
            if n.dropId ~= excludeDropId and Nyx.Drops[n.dropId] then
                candidates[#candidates + 1] = {
                    dropId = n.dropId,
                    drop = Nyx.Drops[n.dropId],
                    dist = n.distance
                }
            end
        end
    else
        for dropId, drop in pairs(Nyx.Drops) do
            if dropId ~= excludeDropId and drop.coords then
                local dx = drop.coords.x - cx
                local dy = drop.coords.y - cy
                local dz = drop.coords.z - cz
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist <= maxDist then
                    candidates[#candidates + 1] = {
                        dropId = dropId,
                        drop = drop,
                        dist = dist
                    }
                end
            end
        end
    end

    for _, cand in ipairs(candidates) do
        local dropId = cand.dropId
        local dist = cand.dist
        local container = Nyx.Inventory.Get(dropId)
        if container and container.type == "drop" and container:canHoldWeight(neededWeight) then
            local hasSlotSpace = false
            local hasIdenticalItem = false

            if itemData and itemData.item_id then
                local itemDef = Nyx.Items and Nyx.Items.Get and Nyx.Items.Get(itemData.item_id)
                local isStackable = itemDef and itemDef.stackable
                local maxStack = itemDef and itemDef.maxStack or 100

                for slot = 1, container.maxSlots do
                    local it = container.items[slot]
                    if it and it.item_id == itemData.item_id then
                        hasIdenticalItem = true
                        if isStackable and (tonumber(it.amount) or 0) < maxStack then
                            hasSlotSpace = true
                            break
                        end
                    end
                end

                if not hasSlotSpace and container:findFirstEmptySlot() ~= nil then
                    hasSlotSpace = true
                end
            else
                hasSlotSpace = (container:findFirstEmptySlot() ~= nil)
            end

            if hasSlotSpace then
                if hasIdenticalItem and dist < bestIdenticalDist then
                    bestIdenticalDropId = dropId
                    bestIdenticalDist = dist
                elseif not hasIdenticalItem and dist < bestCompatibleDist then
                    bestCompatibleDropId = dropId
                    bestCompatibleDist = dist
                end
            end
        end
    end

    -- Prioritize container containing identical item, fallback to closest compatible container
    if bestIdenticalDropId then
        return bestIdenticalDropId, bestIdenticalDist, true
    elseif bestCompatibleDropId then
        return bestCompatibleDropId, bestCompatibleDist, false
    end

    return nil
end

-- Merge an item into an existing ground drop container
function Nyx.Drops.MergeItem(targetDropId, itemData)
    local container = Nyx.Inventory.Get(targetDropId)
    if not container or not itemData or not itemData.item_id then
        return false, "INVALID_CONTAINER_OR_ITEM"
    end

    local itemDef = Nyx.Items and Nyx.Items.Get and Nyx.Items.Get(itemData.item_id)
    local isStackable = itemDef and itemDef.stackable
    local maxStack = itemDef and itemDef.maxStack or 100
    local remainingAmount = tonumber(itemData.amount) or 1

    -- 1. Merge into existing matching stacks if stackable
    if isStackable then
        for slot = 1, container.maxSlots do
            local existing = container.items[slot]
            if existing and existing.item_id == itemData.item_id then
                local currentAmt = tonumber(existing.amount) or 0
                local spaceInSlot = maxStack - currentAmt
                if spaceInSlot > 0 then
                    local added = math.min(remainingAmount, spaceInSlot)
                    existing.amount = currentAmt + added
                    container:setItem(slot, existing)
                    remainingAmount = remainingAmount - added
                    if remainingAmount <= 0 then
                        break
                    end
                end
            end
        end
    end

    -- 2. Place remaining amount into empty slots
    while remainingAmount > 0 do
        local emptySlot = container:findFirstEmptySlot()
        if not emptySlot then
            return false, "CONTAINER_FULL"
        end

        local putAmount = isStackable and math.min(remainingAmount, maxStack) or remainingAmount
        local newItem = {
            item_uuid = Nyx.RPC.GenerateNonce(),
            inventory_id = targetDropId,
            item_id = itemData.item_id,
            slot = emptySlot,
            amount = putAmount,
            metadata = (type(itemData.metadata) == "table") and deepCopy(itemData.metadata) or (itemData.metadata or {})
        }
        container:setItem(emptySlot, newItem)
        remainingAmount = remainingAmount - putAmount
    end

    container:save()

    -- 3. Recalculate smart fallback 3D model after new weight / contents
    Nyx.Drops.RecalculateModel(targetDropId)

    if Config.Debug then
        print(string.format("^2[Nyx:Drops] Auto-merged %dx %s into drop '%s'^7",
            itemData.amount or 1, itemData.item_id, targetDropId))
    end

    return true, targetDropId
end

-- Merge all contents of sourceDropId into targetDropId and remove sourceDropId
function Nyx.Drops.TryAutoMergeContainers(sourceDropId, targetDropId)
    if sourceDropId == targetDropId then return false, "SAME_CONTAINER" end
    local srcContainer = Nyx.Inventory.Get(sourceDropId)
    local dstContainer = Nyx.Inventory.Get(targetDropId)
    if not srcContainer or not dstContainer then return false, "CONTAINER_NOT_FOUND" end

    local srcWeight = srcContainer:getWeight()
    if not dstContainer:canHoldWeight(srcWeight) then
        return false, "CONTAINER_OVERWEIGHT"
    end

    local itemsToMove = {}
    for slot, item in pairs(srcContainer.items) do
        if item then
            itemsToMove[#itemsToMove + 1] = deepCopy(item)
        end
    end

    for _, it in ipairs(itemsToMove) do
        local ok, err = Nyx.Drops.MergeItem(targetDropId, it)
        if not ok then
            return false, err or "MERGE_FAILED"
        end
    end

    -- Remove emptied source container from world and database
    Nyx.Drops.Remove(sourceDropId)
    Nyx.Drops.RecalculateModel(targetDropId)

    if Config.Debug then
        print(string.format("^2[Nyx:Drops] Successfully merged container '%s' into '%s'^7",
            sourceDropId, targetDropId))
    end

    return true, targetDropId
end

-- Delete empty ground drop from world and storage
function Nyx.Drops.Remove(dropId)
    local drop = Nyx.Drops[dropId]
    if not drop then return end

    -- Free up shelf node if drop was resting on a shelf matrix
    if drop.shelfNodeId and exports['nyx_logistics'] and exports['nyx_logistics'].ClearShelfNode then
        pcall(function()
            exports['nyx_logistics']:ClearShelfNode(drop.shelfNodeId)
        end)
    end

    -- Remove from authoritative spatial grid
    if Nyx.SpatialGrid and Nyx.SpatialGrid.Remove then
        Nyx.SpatialGrid.Remove(dropId)
    end

    Nyx.Drops[dropId] = nil
    Nyx.Inventories[dropId] = nil
    Nyx.DirtyInventories[dropId] = nil

    MySQL.query("DELETE FROM `nyx_inventories` WHERE `id` = ?", { dropId })

    TriggerClientEvent("nyx:inventory:client:dropRemoved", -1, dropId)

    if Config.Debug then
        print(string.format("^3[Nyx:Drops] Removed ground drop '%s'^7", dropId))
    end
end

-- Check and cleanup drop container if empty
function Nyx.Drops.CheckCleanup(dropId)
    local container = Nyx.Inventories[dropId]
    if not container or container.type ~= "drop" then return end

    local hasItems = false
    for _, item in pairs(container.items) do
        if item then
            hasItems = true
            break
        end
    end

    if not hasItems then
        Nyx.Drops.Remove(dropId)
    else
        -- If items remain, re-evaluate fallback model (e.g. if items were taken out, box might downgrade)
        Nyx.Drops.RecalculateModel(dropId)
    end
end

-- Check and dissolve ground drop if all items are fully degraded/broken/spoiled or empty
function Nyx.Drops.CheckDecayDissolution(dropId)
    local drop = Nyx.Drops[dropId]
    local container = Nyx.Inventories[dropId]
    if not drop or not container or container.type ~= "drop" then return false end

    local itemCount = 0
    local nonDecayedCount = 0

    for _, item in pairs(container.items) do
        if item then
            itemCount = itemCount + 1
            local dur = item.metadata and tonumber(item.metadata.durability)
            if dur and dur > 0.0 and not item.metadata.isSpoiled and not item.metadata.isBroken and not item.metadata.isExpired then
                nonDecayedCount = nonDecayedCount + 1
            end
        end
    end

    -- If drop has items and ALL of them have reached 0% durability (or container is completely empty)
    if itemCount == 0 or nonDecayedCount == 0 then
        if Config.Debug then
            print(string.format("^3[Nyx:Drops] Dissolving fully degraded ground drop '%s' (items: %d, non-decayed: %d)^7",
                dropId, itemCount, nonDecayedCount))
        end

        -- Log dissolution event
        MySQL.query("INSERT INTO `nyx_inventory_decay_logs` (`inventory_id`, `item_id`, `event_type`, `previous_durability`, `new_durability`, `delta_seconds`, `container_type`) VALUES (?, ?, ?, ?, ?, ?, ?)", {
            dropId, "all", "dissolve", 0.0, 0.0, 0, "drop"
        })

        Nyx.Drops.Remove(dropId)
        return true
    end

    return false
end

-- Query drops within radius using spatial grid partitioning
function Nyx.Drops.GetDropsInRadius(coords, radius, bucket)
    if Nyx.SpatialGrid and Nyx.SpatialGrid.GetNearbyDrops then
        return Nyx.SpatialGrid.GetNearbyDrops(coords, radius, bucket)
    end

    local results = {}
    local cx, cy, cz = tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0
    radius = tonumber(radius) or 10.0
    bucket = tonumber(bucket) or 0
    for id, drop in pairs(Nyx.Drops) do
        if (drop.routingBucket or 0) == bucket and drop.coords then
            local dx = drop.coords.x - cx
            local dy = drop.coords.y - cy
            local dz = drop.coords.z - cz
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist <= radius then
                results[#results + 1] = { dropId = id, distance = dist, coords = drop.coords }
            end
        end
    end
    return results
end

-- Synchronize active drops to connecting or streaming clients, strictly isolated by Routing Bucket
RegisterNetEvent("nyx:inventory:server:requestDrops", function()
    local src = source
    local playerBucket = 0
    if exports['nyx_core'] and exports['nyx_core'].GetRoutingBucket then
        playerBucket = exports['nyx_core']:GetRoutingBucket(src) or 0
    end

    local dropList = {}
    for id, data in pairs(Nyx.Drops) do
        if (data.routingBucket or 0) == playerBucket then
            dropList[#dropList + 1] = data
        end
    end
    TriggerClientEvent("nyx:inventory:client:syncDrops", src, dropList)
end)

-- Request drops residing in specific spatial grid cells (Interest Management)
RegisterNetEvent("nyx:inventory:server:requestCellDrops", function(cellKeys)
    local src = source
    if type(cellKeys) ~= "table" then return end

    local playerBucket = 0
    if exports['nyx_core'] and exports['nyx_core'].GetRoutingBucket then
        playerBucket = exports['nyx_core']:GetRoutingBucket(src) or 0
    end

    local dropList = {}
    local seen = {}
    for _, cellKey in ipairs(cellKeys) do
        local dropIds = Nyx.SpatialGrid.GetDropsInCell(cellKey)
        for _, id in ipairs(dropIds) do
            if not seen[id] then
                seen[id] = true
                local d = Nyx.Drops[id]
                if d and (d.routingBucket or 0) == playerBucket then
                    dropList[#dropList + 1] = d
                end
            end
        end
    end

    TriggerClientEvent("nyx:inventory:client:syncCellDrops", src, dropList)
end)

-- Bootstrap and recover existing world drops from database on resource boot
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(100)
    end

    local rows = MySQL.query.await("SELECT `id`, `coords`, `rotation`, `model`, `routing_bucket`, `shelf_node_id`, `grid_cell`, `last_decay_at` FROM `nyx_inventories` WHERE `type` = 'drop'")
    if rows then
        -- Performance: Batch pre-load all world drop containers in array queries (WHERE id IN (...))
        local dropIds = {}
        for _, row in ipairs(rows) do
            if row.id and not Nyx.Inventories[row.id] then
                dropIds[#dropIds + 1] = row.id
            end
        end
        if #dropIds > 0 and Nyx.Inventory.BatchLoad then
            Nyx.Inventory.BatchLoad(dropIds)
        end

        for _, row in ipairs(rows) do
            if row.coords then
                local okCoords, parsedCoords = pcall(json.decode, row.coords)
                local okRot, parsedRot = pcall(json.decode, row.rotation or "{}")

                if okCoords and parsedCoords and parsedCoords.x and parsedCoords.y and parsedCoords.z then
                    local dropModel = row.model
                    if not dropModel or dropModel == "" then
                        local container = Nyx.Inventory.Get(row.id)
                        dropModel = (Nyx.Drops.ResolveModel and container) and Nyx.Drops.ResolveModel(container) or (Config.DropModel or "prop_paper_bag_small")
                    end

                    local bucket = tonumber(row.routing_bucket) or 0
                    local shelfNode = (row.shelf_node_id and row.shelf_node_id ~= "") and row.shelf_node_id or nil

                    -- Index into spatial grid
                    local cellKey = row.grid_cell
                    if Nyx.SpatialGrid and Nyx.SpatialGrid.Insert then
                        cellKey = Nyx.SpatialGrid.Insert(row.id, parsedCoords, bucket)
                    end

                    Nyx.Drops[row.id] = {
                        id = row.id,
                        coords = parsedCoords,
                        rotation = (okRot and parsedRot and parsedRot.heading) and parsedRot or { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 },
                        model = dropModel or Config.DropModel or "prop_paper_bag_small",
                        routingBucket = bucket,
                        shelfNodeId = shelfNode,
                        gridCell = cellKey,
                        lastDecayAt = tonumber(row.last_decay_at) or 0
                    }
                    -- Preload container
                    Nyx.Inventory.Get(row.id)
                end
            end
        end
        print(string.format("^2[Nyx:Drops] Recovered %d persistent world drops from database into spatial grid.^7", #rows))
    end
end)


