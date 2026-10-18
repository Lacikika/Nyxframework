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
function Nyx.Drops.Create(coords, itemData, rotation, modelOverride)
    local dropUuid = Nyx.RPC.GenerateNonce():sub(1, 8)
    local dropId = string.format("drop:%s", dropUuid)

    local safeCoords = {
        x = math.floor((coords.x or 0.0) * 100) / 100,
        y = math.floor((coords.y or 0.0) * 100) / 100,
        z = math.floor(((coords.z or 70.0) + (Config.DropZOffset or -0.95)) * 100) / 100
    }
    local safeRotation = sanitizeRotation(rotation)

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

    -- Persist rotation and model to database
    MySQL.query("UPDATE `nyx_inventories` SET `rotation` = ?, `model` = ? WHERE `id` = ?", {
        json.encode(safeRotation),
        model,
        dropId
    })

    Nyx.Drops[dropId] = {
        id = dropId,
        coords = safeCoords,
        rotation = safeRotation,
        model = model
    }

    -- Broadcast to clients within streaming range
    TriggerClientEvent("nyx:inventory:client:dropCreated", -1, dropId, safeCoords, safeRotation, model)

    if Config.Debug then
        print(string.format("^2[Nyx:Drops] Created world drop '%s' [%s] at (%.2f, %.2f, %.2f) h:%.1f^7",
            dropId, model, safeCoords.x, safeCoords.y, safeCoords.z, safeRotation.heading))
    end

    return dropId
end

-- Update spatial coordinates and orientation of an existing drop (zero-packet placement release)
function Nyx.Drops.Update(dropId, coords, rotation)
    local drop = Nyx.Drops[dropId]
    if not drop then return false, "DROP_NOT_FOUND" end

    local safeCoords = {
        x = math.floor((coords.x or drop.coords.x or 0.0) * 100) / 100,
        y = math.floor((coords.y or drop.coords.y or 0.0) * 100) / 100,
        z = math.floor((coords.z or drop.coords.z or 70.0) * 100) / 100
    }
    local safeRotation = sanitizeRotation(rotation or drop.rotation)

    drop.coords = safeCoords
    drop.rotation = safeRotation

    local container = Nyx.Inventories[dropId]
    if container then
        container.coords = safeCoords
    end

    -- Update database record
    MySQL.query("UPDATE `nyx_inventories` SET `coords` = ?, `rotation` = ? WHERE `id` = ?", {
        json.encode(safeCoords),
        json.encode(safeRotation),
        dropId
    })

    -- Broadcast position update to all clients
    TriggerClientEvent("nyx:inventory:client:dropMoved", -1, dropId, safeCoords, safeRotation)

    if Config.Debug then
        print(string.format("^2[Nyx:Drops] Moved world drop '%s' to (%.2f, %.2f, %.2f) h:%.1f^7",
            dropId, safeCoords.x, safeCoords.y, safeCoords.z, safeRotation.heading))
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

    for dropId, drop in pairs(Nyx.Drops) do
        if dropId ~= excludeDropId and drop.coords then
            local dx = drop.coords.x - cx
            local dy = drop.coords.y - cy
            local dz = drop.coords.z - cz
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

            if dist <= maxDist then
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

    Nyx.Drops[dropId] = nil
    Nyx.Inventories[dropId] = nil
    Nyx.DirtyInventories[dropId] = nil

    MySQL.query("DELETE FROM `nyx_inventories` WHERE `id` = ?", { dropId })

    TriggerClientEvent("nyx:inventory:client:dropRemoved", -1, dropId)

    if Config.Debug then
        print(string.format("^3[Nyx:Drops] Removed empty ground drop '%s'^7", dropId))
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

-- Synchronize active drops to connecting or streaming clients
RegisterNetEvent("nyx:inventory:server:requestDrops", function()
    local src = source
    local dropList = {}
    for id, data in pairs(Nyx.Drops) do
        dropList[#dropList + 1] = data
    end
    TriggerClientEvent("nyx:inventory:client:syncDrops", src, dropList)
end)

-- Bootstrap and recover existing world drops from database on resource boot
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(100)
    end

    local rows = MySQL.query.await("SELECT `id`, `coords`, `rotation`, `model` FROM `nyx_inventories` WHERE `type` = 'drop'")
    if rows then
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

                    Nyx.Drops[row.id] = {
                        id = row.id,
                        coords = parsedCoords,
                        rotation = (okRot and parsedRot and parsedRot.heading) and parsedRot or { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 },
                        model = dropModel or Config.DropModel or "prop_paper_bag_small"
                    }
                    -- Preload container
                    Nyx.Inventory.Get(row.id)
                end
            end
        end
        print(string.format("^2[Nyx:Drops] Recovered %d persistent world drops from database.^7", #rows))
    end
end)
