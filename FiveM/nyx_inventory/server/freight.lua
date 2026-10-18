--[[
    Nyxframework: nyx_inventory
    File: server/freight.lua
    Description: Authoritative server-side heavy freight physics engine, two-handed physical
                 carry coordination, vehicle loading, and disconnect fail-safes.
]]

Nyx = Nyx or {}
Nyx.Freight = Nyx.Freight or {}

-- Check if a drop container contains heavy freight items or exceeds 50kg threshold
function Nyx.Freight.IsHeavyDrop(dropId)
    local drop = Nyx.Drops and Nyx.Drops[dropId]
    if not drop then return false end

    local container = Nyx.Inventory.Get(dropId, 'drop')
    if not container then return false end

    -- Check cumulative container weight
    local totalWeight = container:getWeight()
    local threshold = (Config and Config.HeavyFreightThreshold) or 50000
    if totalWeight > threshold then
        return true, totalWeight
    end

    -- Check if any individual item inside is categorized as heavy freight
    for _, item in pairs(container.items) do
        if item and item.item_id then
            if Nyx.Items.IsHeavyFreight(item.item_id, item.amount or 1) then
                return true, totalWeight
            end
        end
    end

    return false, totalWeight
end

-- RPC: Start Physical Two-Handed Carry
Nyx.RPC.Register("inventory:startHeavyCarry", function(src, dropId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then
        return { success = false, error = "UNAUTHORIZED" }
    end

    if not dropId then
        return { success = false, error = "INVALID_DROP_ID" }
    end

    dropId = tostring(dropId)
    local drop = Nyx.Drops and Nyx.Drops[dropId]
    if not drop or not drop.coords then
        return { success = false, error = "DROP_NOT_FOUND" }
    end

    -- Distance validation
    local ped = GetPlayerPed(tostring(src))
    local playerCoords = GetEntityCoords(ped)
    local dropVec = vector3(drop.coords.x, drop.coords.y, drop.coords.z)
    local maxInteractDist = (Config.HeavyCarry and Config.HeavyCarry.InteractDistance) or 2.5
    if #(playerCoords - dropVec) > (maxInteractDist + 1.0) then
        return { success = false, error = "DISTANCE_TOO_FAR" }
    end

    -- Verify player is not already carrying heavy freight
    if player.isCarryingHeavyFreight then
        return { success = false, error = "ALREADY_CARRYING_FREIGHT" }
    end

    -- Verify drop is not already carried by another player
    if drop.carriedBy and drop.carriedBy ~= src then
        return { success = false, error = "ALREADY_CARRIED_BY_ANOTHER" }
    end

    -- Validate that drop qualifies as heavy freight
    local isHeavy, totalWeight = Nyx.Freight.IsHeavyDrop(dropId)
    if not isHeavy then
        return { success = false, error = "NOT_HEAVY_FREIGHT" }
    end

    -- Mutex lock container
    if not Nyx.Inventory.AcquireLock(dropId) then
        return { success = false, error = "CONTAINER_BUSY" }
    end

    drop.carriedBy = src
    local dropModel = drop.model or "prop_box_wood02a"

    -- Clear shelf node occupancy if carried off a shelf
    if drop.shelfNodeId and exports['nyx_logistics'] and exports['nyx_logistics'].ClearShelfNode then
        pcall(function()
            exports['nyx_logistics']:ClearShelfNode(drop.shelfNodeId)
        end)
        drop.shelfNodeId = nil
    end

    -- Update player object and set server-authoritative state bags
    player:setHeavyFreight(true, dropId, dropModel)

    -- Notify all clients to hide/despawn the ground prop
    TriggerClientEvent("nyx:inventory:client:dropCarried", -1, dropId, src)

    Nyx.Inventory.ReleaseLock(dropId)

    return {
        success = true,
        dropId = dropId,
        model = dropModel,
        weight = totalWeight
    }
end)

-- RPC: Drop or Place Carried Heavy Freight onto Ground or Shelf
Nyx.RPC.Register("inventory:dropHeavyCarry", function(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player or not player.isCarryingHeavyFreight then
        return { success = false, error = "NOT_CARRYING_FREIGHT" }
    end

    local dropId = player.carriedDropId
    if not dropId then
        player:setHeavyFreight(false, nil, nil)
        return { success = false, error = "NO_ATTACHED_DROP" }
    end

    local drop = Nyx.Drops and Nyx.Drops[dropId]
    if not drop then
        player:setHeavyFreight(false, nil, nil)
        return { success = false, error = "DROP_NOT_FOUND" }
    end

    local ped = GetPlayerPed(tostring(src))
    local playerCoords = GetEntityCoords(ped)

    local targetCoords = playerCoords
    local heading = GetEntityHeading(ped)
    local targetShelfNode = nil

    if type(payload) == "table" and payload.coords then
        local reqVec = vector3(payload.coords.x, payload.coords.y, payload.coords.z)
        local maxDist = (Config.HeavyCarry and Config.HeavyCarry.DropPlaceDistance) or 3.5
        if #(playerCoords - reqVec) <= (maxDist + 1.0) then
            targetCoords = reqVec
        end
        if payload.rotation then
            heading = tonumber(payload.rotation.heading) or tonumber(payload.rotation.z) or heading
        end

        -- Check shelf snapping
        if payload.shelfNodeId and exports['nyx_logistics'] and exports['nyx_logistics'].GetShelfNode then
            local node = exports['nyx_logistics']:GetShelfNode(payload.shelfNodeId)
            if node and (not node.occupiedDropId or node.occupiedDropId == dropId) then
                targetShelfNode = node
                targetCoords = vector3(node.worldCoords.x, node.worldCoords.y, node.worldCoords.z)
                heading = node.heading or heading
            end
        end
    end

    local safeCoords = {
        x = math.floor(targetCoords.x * 100) / 100,
        y = math.floor(targetCoords.y * 100) / 100,
        z = math.floor(targetCoords.z * 100) / 100
    }
    heading = (heading % 360.0 + 360.0) % 360.0
    local safeRotation = {
        x = 0.0,
        y = 0.0,
        z = math.floor(heading * 100) / 100,
        heading = math.floor(heading * 100) / 100
    }

    if not Nyx.Inventory.AcquireLock(dropId) then
        return { success = false, error = "CONTAINER_BUSY" }
    end

    drop.carriedBy = nil
    local ok, err = Nyx.Drops.Update(dropId, safeCoords, safeRotation, targetShelfNode and targetShelfNode.id or false)

    -- Claim shelf node if placed onto a shelf matrix
    if ok and targetShelfNode and exports['nyx_logistics'] and exports['nyx_logistics'].SetShelfNodeOccupant then
        pcall(function()
            exports['nyx_logistics']:SetShelfNodeOccupant(targetShelfNode.id, dropId)
        end)
    end

    -- Clear player heavy freight state bag
    player:setHeavyFreight(false, nil, nil)

    -- Broadcast world entity release to all clients
    TriggerClientEvent("nyx:inventory:client:dropReleased", -1, dropId, safeCoords, safeRotation)

    Nyx.Inventory.ReleaseLock(dropId)

    return {
        success = ok,
        dropId = dropId,
        coords = safeCoords,
        rotation = safeRotation
    }
end)

-- RPC: Load Carried Heavy Freight Directly into Vehicle Trunk / Flatbed
Nyx.RPC.Register("inventory:loadHeavyFreightToVehicle", function(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player or not player.isCarryingHeavyFreight then
        return { success = false, error = "NOT_CARRYING_FREIGHT" }
    end

    local dropId = player.carriedDropId
    if not dropId then
        player:setHeavyFreight(false, nil, nil)
        return { success = false, error = "NO_ATTACHED_DROP" }
    end

    local plate = payload and payload.plate
    if not plate or type(plate) ~= "string" or #plate < 2 then
        return { success = false, error = "INVALID_VEHICLE_PLATE" }
    end

    local ped = GetPlayerPed(tostring(src))
    local playerCoords = GetEntityCoords(ped)

    local trunkInvId = string.format("trunk:%s", plate)
    local trunkContainer = Nyx.Inventory.Get(trunkInvId, 'trunk')
    local dropContainer = Nyx.Inventory.Get(dropId, 'drop')

    if not trunkContainer or not dropContainer then
        return { success = false, error = "CONTAINER_NOT_FOUND" }
    end

    local dropWeight = dropContainer:getWeight()
    if not trunkContainer:canHoldWeight(dropWeight) then
        return { success = false, error = "VEHICLE_TRUNK_FULL" }
    end

    if not Nyx.Inventory.AcquireDualLock(dropId, trunkInvId) then
        return { success = false, error = "CONTAINER_BUSY" }
    end

    -- Transfer all items from drop container to trunk container
    local itemsToMove = {}
    for slot, item in pairs(dropContainer.items) do
        itemsToMove[#itemsToMove + 1] = { slot = slot, item = item }
    end

    local nextTrunkSlot = 1
    for _, itemEntry in ipairs(itemsToMove) do
        while trunkContainer:getItem(nextTrunkSlot) do
            nextTrunkSlot = nextTrunkSlot + 1
        end
        if nextTrunkSlot <= trunkContainer.maxSlots then
            dropContainer:removeItem(itemEntry.slot)
            trunkContainer:setItem(nextTrunkSlot, itemEntry.item)
            nextTrunkSlot = nextTrunkSlot + 1
        end
    end

    -- Reset player heavy freight state bag
    player:setHeavyFreight(false, nil, nil)

    -- Delete the emptied ground drop container
    Nyx.Drops.Delete(dropId)

    -- Broadcast world entity release to all clients
    TriggerClientEvent("nyx:inventory:client:dropCarried", -1, dropId, nil)

    Nyx.Inventory.ReleaseDualLock(dropId, trunkInvId)

    return { success = true, plate = plate }
end)

-- Disconnect Fail-Safe: Automatically drop carried crate on ground if player disconnects
AddEventHandler("playerDropped", function()
    local src = source
    local player = exports['nyx_core']:GetPlayer(src)
    if player and player.isCarryingHeavyFreight and player.carriedDropId then
        local dropId = player.carriedDropId
        local drop = Nyx.Drops and Nyx.Drops[dropId]
        if drop then
            drop.carriedBy = nil
            local ped = GetPlayerPed(tostring(src))
            local coords = GetEntityCoords(ped)
            local safeCoords = {
                x = math.floor(coords.x * 100) / 100,
                y = math.floor(coords.y * 100) / 100,
                z = math.floor(coords.z * 100) / 100
            }
            local safeRot = { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 }
            Nyx.Drops.Update(dropId, safeCoords, safeRot)
            TriggerClientEvent("nyx:inventory:client:dropReleased", -1, dropId, safeCoords, safeRot)
        end
        player:setHeavyFreight(false, nil, nil)
    end
end)
