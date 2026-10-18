--[[
    Nyxframework: nyx_inventory
    File: server/exports.lua
    Description: Clean public server exports for item management, queries, and container mutations.
]]

Nyx = Nyx or {}

-- Get or load a container
exports("GetInventory", function(invId)
    return Nyx.Inventory.Get(invId)
end)

-- Get personal inventory for a player
exports("GetPlayerInventory", function(src)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return nil end
    local invId = string.format("char:%s:main", player.citizenId)
    return Nyx.Inventory.Get(invId, 'player')
end)

-- Check if container contains item in required quantity
exports("HasItem", function(invId, itemId, requiredAmount)
    requiredAmount = tonumber(requiredAmount) or 1
    local container = Nyx.Inventory.Get(invId)
    if not container then return false end

    local count = 0
    for _, item in pairs(container.items) do
        if item and item.item_id == itemId then
            count = count + (tonumber(item.amount) or 1)
            if count >= requiredAmount then
                return true
            end
        end
    end
    return false
end)

-- Get total quantity of item in container
exports("GetItemCount", function(invId, itemId)
    local container = Nyx.Inventory.Get(invId)
    if not container then return 0 end

    local count = 0
    for _, item in pairs(container.items) do
        if item and item.item_id == itemId then
            count = count + (tonumber(item.amount) or 1)
        end
    end
    return count
end)

-- Authoritatively add item to container
exports("AddItem", function(invId, itemId, amount, metadata, targetSlot)
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false, "INVALID_AMOUNT" end

    local itemDef = Nyx.Items.Get(itemId)
    if not itemDef then return false, "UNKNOWN_ITEM" end

    local container = Nyx.Inventory.Get(invId)
    if not container then return false, "CONTAINER_NOT_FOUND" end

    local totalWeight = Nyx.Items.GetWeight(itemId, amount)
    if not container:canHoldWeight(totalWeight) then
        return false, "CONTAINER_OVERWEIGHT"
    end

    if not Nyx.Inventory.AcquireLock(invId) then
        return false, "CONTAINER_BUSY"
    end

    local success, res = pcall(function()
        local meta = metadata or Nyx.Items.CreateDefaultMetadata(itemId)

        -- If specific slot requested
        if targetSlot then
            targetSlot = tonumber(targetSlot)
            local existing = container:getItem(targetSlot)
            if not existing then
                container:setItem(targetSlot, {
                    item_uuid = Nyx.RPC.GenerateNonce(),
                    item_id = itemId,
                    slot = targetSlot,
                    amount = amount,
                    metadata = meta
                })
                return true
            elseif existing.item_id == itemId and itemDef.stackable then
                local maxStack = itemDef.maxStack or 100
                if (existing.amount + amount) <= maxStack then
                    existing.amount = existing.amount + amount
                    container:setItem(targetSlot, existing)
                    return true
                end
            end
        end

        -- Stack into existing slots if stackable
        if itemDef.stackable then
            for slot, existing in pairs(container.items) do
                if existing and existing.item_id == itemId then
                    local maxStack = itemDef.maxStack or 100
                    local space = maxStack - existing.amount
                    if space > 0 then
                        local toAdd = math.min(space, amount)
                        existing.amount = existing.amount + toAdd
                        container:setItem(slot, existing)
                        amount = amount - toAdd
                        if amount <= 0 then
                            return true
                        end
                    end
                end
            end
        end

        -- Place remainder in empty slot
        while amount > 0 do
            local emptySlot = container:findFirstEmptySlot()
            if not emptySlot then
                return false, "INVENTORY_FULL_SLOTS"
            end

            local maxStack = itemDef.stackable and (itemDef.maxStack or 100) or 1
            local toAdd = math.min(maxStack, amount)

            container:setItem(emptySlot, {
                item_uuid = Nyx.RPC.GenerateNonce(),
                item_id = itemId,
                slot = emptySlot,
                amount = toAdd,
                metadata = deepCopy(meta)
            })

            amount = amount - toAdd
        end

        return true
    end)

    Nyx.Inventory.ReleaseLock(invId)
    return success and res, res
end)

-- Authoritatively remove item from container
exports("RemoveItem", function(invId, itemId, amount, specificSlot)
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false, "INVALID_AMOUNT" end

    local container = Nyx.Inventory.Get(invId)
    if not container then return false, "CONTAINER_NOT_FOUND" end

    if not Nyx.Inventory.AcquireLock(invId) then
        return false, "CONTAINER_BUSY"
    end

    local success, res = pcall(function()
        if specificSlot then
            local item = container:getItem(specificSlot)
            if not item or item.item_id ~= itemId or item.amount < amount then
                return false, "INSUFFICIENT_ITEM"
            end

            if item.amount == amount then
                container:removeItem(specificSlot)
            else
                item.amount = item.amount - amount
                container:setItem(specificSlot, item)
            end
            return true
        end

        -- General removal across multiple slots
        local count = 0
        for _, item in pairs(container.items) do
            if item and item.item_id == itemId then
                count = count + item.amount
            end
        end

        if count < amount then
            return false, "INSUFFICIENT_ITEM"
        end

        local remaining = amount
        for slot, item in pairs(container.items) do
            if item and item.item_id == itemId then
                if item.amount <= remaining then
                    remaining = remaining - item.amount
                    container:removeItem(slot)
                else
                    item.amount = item.amount - remaining
                    container:setItem(slot, item)
                    remaining = 0
                end

                if remaining <= 0 then break end
            end
        end

        return true
    end)

    Nyx.Inventory.ReleaseLock(invId)
    return success and res, res
end)

-- Create physical ground drop
exports("CreateDrop", function(coords, itemData)
    return Nyx.Drops.Create(coords, itemData)
end)

-- Register or ensure custom container exists
exports("RegisterContainer", function(invId, label, maxWeight, maxSlots, coords)
    if not invId then return nil end
    local container = Nyx.Inventory.Get(invId)
    if not container then
        container = Nyx.Inventory.NewContainer(invId, "stash", maxWeight, maxSlots, coords)
        container:save()
    else
        if maxWeight then container.maxWeight = tonumber(maxWeight) end
        if maxSlots then container.maxSlots = tonumber(maxSlots) end
        container:save()
    end
    return container
end)

-- Batch load multiple containers in array queries (WHERE id IN (...)) to eliminate sequential database latency
exports("BatchLoadInventories", function(containerIds, autoCreateType)
    if type(containerIds) ~= "table" then return {}, 0, 0, 0 end
    return Nyx.Inventory.BatchLoad(containerIds, { autoCreateType = autoCreateType })
end)

-- Preload containers into memory cache (alias for BatchLoadInventories)
exports("PreloadInventories", function(containerIds)
    if type(containerIds) ~= "table" then return {}, 0, 0, 0 end
    return Nyx.Inventory.BatchLoad(containerIds)
end)

-- Get batch of containers as a key-value dictionary [id] = container
exports("GetInventoriesBatch", function(containerIds)
    if type(containerIds) ~= "table" then return {}, 0, 0, 0 end
    local results = Nyx.Inventory.BatchLoad(containerIds)
    return results
end)

-- Batch register or ensure multiple custom containers exist without sequential queries
exports("RegisterContainersBatch", function(containerDefs)
    if type(containerDefs) ~= "table" then return {} end

    local ids = {}
    for _, def in ipairs(containerDefs) do
        if def.id then
            ids[#ids + 1] = def.id
        end
    end

    local loaded = Nyx.Inventory.BatchLoad(ids, { autoCreateType = "stash" })

    for _, def in ipairs(containerDefs) do
        local container = loaded[def.id]
        if container then
            local modified = false
            if def.maxWeight and container.maxWeight ~= tonumber(def.maxWeight) then
                container.maxWeight = tonumber(def.maxWeight)
                modified = true
            end
            if def.maxSlots and container.maxSlots ~= tonumber(def.maxSlots) then
                container.maxSlots = tonumber(def.maxSlots)
                modified = true
            end
            if def.coords and not container.coords then
                container.coords = def.coords
                modified = true
            end
            if modified then
                container:save()
            end
        end
    end

    return loaded
end)


-- Query player inventory weight and capacity
exports("GetPlayerWeight", function(src)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return 0, 30000, 0.0 end

    local invId = string.format("char:%s:main", player.citizenId)
    local container = Nyx.Inventories[invId] or Nyx.Inventory.Get(invId, 'player')
    if not container then return 0, 30000, 0.0 end

    local cur = container:getWeight()
    local maxW = container.maxWeight
    return cur, maxW, cur / math.max(1, maxW)
end)

-- Force immediate weight synchronization for player
exports("SyncPlayerWeight", function(src)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false end

    local invId = string.format("char:%s:main", player.citizenId)
    local container = Nyx.Inventories[invId] or Nyx.Inventory.Get(invId, 'player')
    if not container then return false end

    container:syncWeightToCore()
    return true
end)

-- Query nearby ground drops using spatial grid partitioning
exports("GetNearbyGroundDrops", function(coords, radius, bucket)
    if Nyx.Drops and Nyx.Drops.GetDropsInRadius then
        return Nyx.Drops.GetDropsInRadius(coords, radius, bucket)
    end
    return {}
end)

-- Query spatial partitioning grid statistics
exports("GetSpatialGridStats", function()
    if Nyx.SpatialGrid and Nyx.SpatialGrid.GetStats then
        return Nyx.SpatialGrid.GetStats()
    end
    return { totalCells = 0, totalDrops = 0 }
end)

-- Programmatic item repair export
exports("RepairItem", function(invId, targetSlot, toolSlot)
    local container = Nyx.Inventory.Get(invId)
    if not container then return false, "CONTAINER_NOT_FOUND" end

    local targetItem = container:getItem(targetSlot)
    local toolItem = container:getItem(toolSlot)
    if not targetItem or not toolItem then return false, "ITEM_NOT_FOUND" end

    if not Nyx.Decay or not Nyx.Decay.CanRepairItem(targetItem) then
        return false, "NOT_REPAIRABLE"
    end

    local gain, newDur, newMaxDur = Nyx.Decay.CalculateRepairGain(targetItem, toolItem)
    if gain <= 0 then return false, "ALREADY_MAX_DURABILITY" end

    targetItem.metadata.durability = newDur
    targetItem.metadata.maxDurability = newMaxDur
    targetItem.metadata.isBroken = false
    targetItem.metadata.lastDecay = os.time()
    container:setItem(targetSlot, targetItem)

    if toolItem.amount <= 1 then
        container:removeItem(toolSlot)
    else
        toolItem.amount = toolItem.amount - 1
        container:setItem(toolSlot, toolItem)
    end

    container:save()
    return true, newDur, gain
end)


