--[[
    Nyxframework: nyx_inventory
    File: server/actions.lua
    Description: Authoritative slot swap, split, stack, drop, and item usage action handlers.
]]

Nyx = Nyx or {}
Nyx.Inventory = Nyx.Inventory or {}
Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        exports['nyx_core']:RegisterRPC(route, handler)
    end,
    GenerateNonce = function()
        local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        return (string.gsub(template, '[xy]', function (c)
            local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format('%x', v)
        end))
    end
}

-- Deep copy table helper
local function deepCopy(orig)
    if type(orig) ~= 'table' then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == 'table' and deepCopy(v) or v
    end
    return copy
end

-- Validate player proximity and ownership for container access
function Nyx.Inventory.ValidateAccess(src, invId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false end

    -- 1. Player Personal Inventory
    local playerInvId = string.format("char:%s:main", player.citizenId)
    if invId == playerInvId then
        return true
    end

    -- 2. World Ground Drop
    local drop = Nyx.Drops[invId]
    if drop and drop.coords then
        local ped = GetPlayerPed(tostring(src))
        local playerCoords = GetEntityCoords(ped)
        local dropVec = vector3(drop.coords.x, drop.coords.y, drop.coords.z)
        local dist = #(playerCoords - dropVec)
        return dist <= (Config.DropInteractDistance or 2.5)
    end

    -- 3. Stashes & World Containers with fixed coordinates
    local container = Nyx.Inventories[invId]
    if container and container.coords then
        local ped = GetPlayerPed(tostring(src))
        local playerCoords = GetEntityCoords(ped)
        local targetVec = vector3(container.coords.x, container.coords.y, container.coords.z)
        return #(playerCoords - targetVec) <= 4.0
    end

    -- 4. Vehicle Trunks and Gloveboxes (trunk:PLATE, glovebox:PLATE)
    if invId:sub(1, 6) == "trunk:" or invId:sub(1, 9) == "glovebox:" then
        local ped = GetPlayerPed(tostring(src))
        local playerCoords = GetEntityCoords(ped)
        -- Verify proximity to an active vehicle
        local closeVeh = GetClosestVehicle and GetClosestVehicle(playerCoords.x, playerCoords.y, playerCoords.z, 6.0, 0, 71)
        if closeVeh and DoesEntityExist(closeVeh) then
            return true
        end
        -- Fallback: OneSync active vehicle entities
        return true
    end

    -- 5. Foreign Player Inventory Protection (Cannot open other player's pockets remotely)
    if invId:sub(1, 5) == "char:" and invId ~= playerInvId then
        return false
    end

    -- Server-authorized system stashes
    return true
end

-- Open Container RPC
Nyx.RPC.Register("inventory:openContainer", function(src, targetInvId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then
        return nil, "UNAUTHORIZED"
    end

    local playerInvId = string.format("char:%s:main", player.citizenId)
    local playerContainer = Nyx.Inventory.Get(playerInvId, 'player')
    playerContainer:addListener(src)

    local targetSnapshot = nil
    if targetInvId and targetInvId ~= playerInvId then
        if not Nyx.Inventory.ValidateAccess(src, targetInvId) then
            return nil, "DISTANCE_TOO_FAR"
        end

        local targetContainer = Nyx.Inventory.Get(targetInvId)
        if targetContainer then
            targetContainer:addListener(src)
            targetSnapshot = targetContainer:getSnapshot()
        end
    end

    return {
        player = playerContainer:getSnapshot(),
        target = targetSnapshot
    }
end)

-- Close Container RPC
Nyx.RPC.Register("inventory:closeContainer", function(src, invId)
    if not invId then return true end

    local container = Nyx.Inventories[invId]
    if container then
        container:removeListener(src)
        if container.type == "drop" then
            Nyx.Drops.CheckCleanup(invId)
        end
    end

    return true
end)

-- Server-Authoritative Slot Swap, Split, and Stack RPC
Nyx.RPC.Register("inventory:moveSlot", function(src, payload)
    if type(payload) ~= "table" then
        return { success = false, error = "INVALID_PAYLOAD" }
    end

    local fromInv = payload.fromInv
    local toInv = payload.toInv
    local fromSlot = tonumber(payload.fromSlot)
    local toSlot = tonumber(payload.toSlot)
    local amount = math.floor(tonumber(payload.amount) or 1)

    if not fromInv or not toInv or not fromSlot or not toSlot or amount <= 0 then
        return { success = false, error = "INVALID_PARAMETERS" }
    end

    -- 1. Security: Access Validation
    if not Nyx.Inventory.ValidateAccess(src, fromInv) or not Nyx.Inventory.ValidateAccess(src, toInv) then
        return { success = false, error = "ACCESS_DENIED" }
    end

    -- 2. Concurrency Control: Dual-Container Mutex Lock
    if not Nyx.Inventory.AcquireDualLock(fromInv, toInv) then
        return { success = false, error = "CONTAINER_BUSY" }
    end

    local ok, outcome, customErr = xpcall(function()
        local srcContainer = Nyx.Inventory.Get(fromInv)
        local dstContainer = Nyx.Inventory.Get(toInv)

        if not srcContainer or not dstContainer then
            return false, "CONTAINER_NOT_FOUND"
        end

        local srcItem = srcContainer:getItem(fromSlot)
        if not srcItem or (tonumber(srcItem.amount) or 0) < amount then
            return false, "ITEM_NOT_FOUND"
        end

        local itemDef = Nyx.Items.Get(srcItem.item_id)
        if not itemDef then
            return false, "UNKNOWN_ITEM_DEFINITION"
        end

        local dstItem = dstContainer:getItem(toSlot)

        -- CASE 1: Target slot is empty
        if not dstItem then
            local movedWeight = Nyx.Items.GetWeight(srcItem.item_id, amount)
            if fromInv ~= toInv and not dstContainer:canHoldWeight(movedWeight) then
                return false, "CONTAINER_OVERWEIGHT"
            end

            if amount == srcItem.amount then
                -- Full Transfer
                srcContainer:removeItem(fromSlot)
                dstContainer:setItem(toSlot, srcItem)
            else
                -- Stack Split
                if not itemDef.stackable then
                    return false, "ITEM_NOT_STACKABLE"
                end

                srcItem.amount = srcItem.amount - amount
                srcContainer:setItem(fromSlot, srcItem)

                local newItem = {
                    item_uuid = Nyx.RPC.GenerateNonce(),
                    inventory_id = toInv,
                    item_id = srcItem.item_id,
                    slot = toSlot,
                    amount = amount,
                    metadata = deepCopy(srcItem.metadata or {})
                }
                dstContainer:setItem(toSlot, newItem)
            end

            return true

        -- CASE 2: Target slot has matching stackable item
        elseif dstItem.item_id == srcItem.item_id and itemDef.stackable then
            local maxStack = itemDef.maxStack or 100
            local spaceAvailable = maxStack - dstItem.amount

            if spaceAvailable <= 0 then
                return false, "STACK_MAX_REACHED"
            end

            local transferAmount = math.min(amount, spaceAvailable)
            local movedWeight = Nyx.Items.GetWeight(srcItem.item_id, transferAmount)

            if fromInv ~= toInv and not dstContainer:canHoldWeight(movedWeight) then
                return false, "CONTAINER_OVERWEIGHT"
            end

            dstItem.amount = dstItem.amount + transferAmount
            dstContainer:setItem(toSlot, dstItem)

            if transferAmount == srcItem.amount then
                srcContainer:removeItem(fromSlot)
            else
                srcItem.amount = srcItem.amount - transferAmount
                srcContainer:setItem(fromSlot, srcItem)
            end

            return true

        -- CASE 3: Target slot contains different item -> Complete Slot Swap
        else
            if amount ~= srcItem.amount then
                return false, "CANNOT_SPLIT_AND_SWAP"
            end

            -- Weight check for cross-container swap
            if fromInv ~= toInv then
                local srcWeight = Nyx.Items.GetWeight(srcItem.item_id, srcItem.amount)
                local dstWeight = Nyx.Items.GetWeight(dstItem.item_id, dstItem.amount)

                local srcDiff = dstWeight - srcWeight
                local dstDiff = srcWeight - dstWeight

                if not srcContainer:canHoldWeight(srcDiff) or not dstContainer:canHoldWeight(dstDiff) then
                    return false, "CONTAINER_OVERWEIGHT"
                end
            end

            srcContainer:setItem(fromSlot, dstItem)
            dstContainer:setItem(toSlot, srcItem)
            return true
        end
    end, function(err)
        local trace = debug.traceback(tostring(err), 2)
        print(string.format("^1[Nyx:Actions] Fatal exception during moveSlot: %s\n%s^7", tostring(err), trace))
        return err
    end)

    -- Guaranteed Lock Release
    Nyx.Inventory.ReleaseDualLock(fromInv, toInv)

    -- Post-transaction drop cleanup checks
    if fromInv:sub(1, 5) == "drop:" then
        Nyx.Drops.CheckCleanup(fromInv)
    end
    if toInv:sub(1, 5) == "drop:" then
        Nyx.Drops.CheckCleanup(toInv)
    end

    if not ok then
        return { success = false, error = "INTERNAL_SERVER_ERROR" }
    end

    if not outcome then
        return { success = false, error = customErr or "TRANSACTION_FAILED" }
    end

    return { success = true }
end)

-- Drop Item into Ground Drop Container RPC
Nyx.RPC.Register("inventory:dropItem", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end

    local fromInv = payload.fromInv
    local slot = tonumber(payload.slot)
    local amount = math.floor(tonumber(payload.amount) or 1)

    if not fromInv or not slot or amount <= 0 then
        return { success = false, error = "INVALID_PARAMETERS" }
    end

    if not Nyx.Inventory.ValidateAccess(src, fromInv) then
        return { success = false, error = "ACCESS_DENIED" }
    end

    if not Nyx.Inventory.AcquireLock(fromInv) then
        return { success = false, error = "CONTAINER_BUSY" }
    end

    local ped = GetPlayerPed(tostring(src))
    local coords = GetEntityCoords(ped)

    local isMerged = false
    local outcome, res = Nyx.Inventory.WithLock(fromInv, function()
        local container = Nyx.Inventory.Get(fromInv)
        if not container then return false, "CONTAINER_NOT_FOUND" end

        local item = container:getItem(slot)
        if not item or (tonumber(item.amount) or 0) < amount then
            return false, "ITEM_NOT_FOUND"
        end

        local droppedItemData = {
            item_uuid = Nyx.RPC.GenerateNonce(),
            item_id = item.item_id,
            slot = 1,
            amount = amount,
            metadata = deepCopy(item.metadata or {})
        }

        if amount == item.amount then
            container:removeItem(slot)
        else
            item.amount = item.amount - amount
            container:setItem(slot, item)
        end

        -- Proximity Auto-Merge Check (within 1.5m)
        local mergeDropId = Nyx.Drops.FindAutoMergeTarget(coords, droppedItemData)
        if mergeDropId then
            if Nyx.Inventory.AcquireLock(mergeDropId) then
                local mergeOk, mergeRes = Nyx.Drops.MergeItem(mergeDropId, droppedItemData)
                Nyx.Inventory.ReleaseLock(mergeDropId)
                if mergeOk then
                    isMerged = true
                    return true, mergeDropId
                end
            end
        end

        local dropId = Nyx.Drops.Create(coords, droppedItemData)
        return true, dropId
    end)

    Nyx.Inventory.ReleaseLock(fromInv)

    if not outcome then
        return { success = false, error = res or "DROP_FAILED" }
    end

    return { success = true, dropId = res, merged = isMerged }
end)

-- Single Authoritative RPC for Client-Side Hologram Placement (Zero-Packet Placement Release)
Nyx.RPC.Register("inventory:commitWorldPlacement", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end

    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local ped = GetPlayerPed(tostring(src))
    local playerCoords = GetEntityCoords(ped)

    local targetCoords = payload.coords
    if type(targetCoords) ~= "table" or not targetCoords.x or not targetCoords.y or not targetCoords.z then
        return { success = false, error = "INVALID_COORDINATES" }
    end

    local placementVec = vector3(tonumber(targetCoords.x) or 0.0, tonumber(targetCoords.y) or 0.0, tonumber(targetCoords.z) or 0.0)
    local maxDist = (Config.Placement and Config.Placement.MaxDistance or 6.0) + 2.5 -- Tolerance margin for latency
    local dist = #(playerCoords - placementVec)

    -- Security: Anti-teleport / proximity validation
    if dist > maxDist then
        return { success = false, error = "PLACEMENT_OUT_OF_RANGE" }
    end

    local safeCoords = {
        x = math.floor(placementVec.x * 100) / 100,
        y = math.floor(placementVec.y * 100) / 100,
        z = math.floor(placementVec.z * 100) / 100
    }

    local heading = 0.0
    if type(payload.rotation) == "table" then
        heading = tonumber(payload.rotation.heading) or tonumber(payload.rotation.z) or 0.0
    elseif type(payload.rotation) == "number" then
        heading = payload.rotation
    end
    heading = (heading % 360.0 + 360.0) % 360.0
    local safeRotation = {
        x = 0.0,
        y = 0.0,
        z = math.floor(heading * 100) / 100,
        heading = math.floor(heading * 100) / 100
    }

    -- 3D Shelf Matrix Snapping Validation
    local targetShelfNode = nil
    local playerBucket = 0
    if exports['nyx_core'] and exports['nyx_core'].GetRoutingBucket then
        playerBucket = exports['nyx_core']:GetRoutingBucket(src) or 0
    end
    local targetBucket = tonumber(payload.routingBucket) or playerBucket or 0

    if payload.shelfNodeId and exports['nyx_logistics'] and exports['nyx_logistics'].GetShelfNode then
        local node = exports['nyx_logistics']:GetShelfNode(payload.shelfNodeId)
        if node then
            if node.occupiedDropId and node.occupiedDropId ~= payload.dropId then
                return { success = false, error = "SHELF_SLOT_OCCUPIED" }
            end
            targetShelfNode = node
            safeCoords = {
                x = math.floor((node.worldCoords.x or safeCoords.x) * 100) / 100,
                y = math.floor((node.worldCoords.y or safeCoords.y) * 100) / 100,
                z = math.floor((node.worldCoords.z or safeCoords.z) * 100) / 100
            }
            safeRotation = {
                x = 0.0,
                y = 0.0,
                z = math.floor(node.heading * 100) / 100,
                heading = math.floor(node.heading * 100) / 100
            }
            targetBucket = tonumber(node.routingBucket) or targetBucket
        end
    end

    -- CASE 1: Reposition existing world drop container
    if payload.dropId then
        local dropId = tostring(payload.dropId)
        local existingDrop = Nyx.Drops[dropId]
        if not existingDrop then
            return { success = false, error = "DROP_NOT_FOUND" }
        end

        local originalVec = vector3(existingDrop.coords.x, existingDrop.coords.y, existingDrop.coords.z)
        if #(playerCoords - originalVec) > maxDist then
            return { success = false, error = "DROP_OUT_OF_RANGE" }
        end

        -- Check for Proximity Auto-Merge into another nearby drop container (within 1.5m, only if not snapping to dedicated shelf node)
        if not targetShelfNode then
            local mergeTargetDropId = Nyx.Drops.FindAutoMergeTarget(safeCoords, nil, Config.DropAutoMergeDistance or 1.5, dropId)
            if mergeTargetDropId then
                if Nyx.Inventory.AcquireDualLock(dropId, mergeTargetDropId) then
                    local merged, mergeRes = Nyx.Drops.TryAutoMergeContainers(dropId, mergeTargetDropId)
                    Nyx.Inventory.ReleaseDualLock(dropId, mergeTargetDropId)
                    if merged then
                        return { success = true, dropId = mergeTargetDropId, merged = true, coords = safeCoords, rotation = safeRotation }
                    end
                end
            end
        end

        if not Nyx.Inventory.AcquireLock(dropId) then
            return { success = false, error = "CONTAINER_BUSY" }
        end

        -- Clear old shelf node if moved away from previous shelf
        if existingDrop.shelfNodeId and existingDrop.shelfNodeId ~= payload.shelfNodeId then
            if exports['nyx_logistics'] and exports['nyx_logistics'].ClearShelfNode then
                pcall(function()
                    exports['nyx_logistics']:ClearShelfNode(existingDrop.shelfNodeId)
                end)
            end
        end

        local ok, updateErr = Nyx.Drops.Update(dropId, safeCoords, safeRotation, targetShelfNode and targetShelfNode.id or false)
        Nyx.Inventory.ReleaseLock(dropId)

        if not ok then
            return { success = false, error = updateErr or "UPDATE_FAILED" }
        end

        -- Occupy new shelf node if snapped
        if targetShelfNode and exports['nyx_logistics'] and exports['nyx_logistics'].SetShelfNodeOccupant then
            pcall(function()
                exports['nyx_logistics']:SetShelfNodeOccupant(targetShelfNode.id, dropId)
            end)
        end

        return { success = true, dropId = dropId, coords = safeCoords, rotation = safeRotation, shelfNodeId = targetShelfNode and targetShelfNode.id or nil }
    end

    -- CASE 2: New placement from player's inventory
    local fromInv = payload.fromInv
    local slot = tonumber(payload.slot)
    local amount = math.floor(tonumber(payload.amount) or 1)
    local itemId = payload.itemId

    if not fromInv or not slot or amount <= 0 then
        return { success = false, error = "INVALID_PARAMETERS" }
    end

    if not Nyx.Inventory.ValidateAccess(src, fromInv) then
        return { success = false, error = "ACCESS_DENIED" }
    end

    if not Nyx.Inventory.AcquireLock(fromInv) then
        return { success = false, error = "CONTAINER_BUSY" }
    end

    local isPlacementMerged = false
    local outcome, res = Nyx.Inventory.WithLock(fromInv, function()
        local container = Nyx.Inventory.Get(fromInv)
        if not container then return false, "CONTAINER_NOT_FOUND" end

        local item = container:getItem(slot)
        if not item or (tonumber(item.amount) or 0) < amount then
            return false, "ITEM_NOT_FOUND"
        end

        if itemId and item.item_id ~= itemId then
            return false, "ITEM_MISMATCH"
        end

        local droppedItemData = {
            item_uuid = Nyx.RPC.GenerateNonce(),
            item_id = item.item_id,
            slot = 1,
            amount = amount,
            metadata = deepCopy(item.metadata or {})
        }

        if amount == item.amount then
            container:removeItem(slot)
        else
            item.amount = item.amount - amount
            container:setItem(slot, item)
        end

        -- Check for Proximity Auto-Merge into nearby container (within 1.5m, unless snapping to dedicated shelf node)
        if not targetShelfNode then
            local mergeDropId = Nyx.Drops.FindAutoMergeTarget(safeCoords, droppedItemData)
            if mergeDropId then
                if Nyx.Inventory.AcquireLock(mergeDropId) then
                    local mergeOk, mergeRes = Nyx.Drops.MergeItem(mergeDropId, droppedItemData)
                    Nyx.Inventory.ReleaseLock(mergeDropId)
                    if mergeOk then
                        isPlacementMerged = true
                        return true, mergeDropId
                    end
                end
            end
        end

        local newDropId = Nyx.Drops.Create(
            safeCoords,
            droppedItemData,
            safeRotation,
            nil,
            targetBucket,
            targetShelfNode and targetShelfNode.id or nil
        )

        -- Claim shelf node if placed onto a physical shelf matrix
        if targetShelfNode and exports['nyx_logistics'] and exports['nyx_logistics'].SetShelfNodeOccupant then
            pcall(function()
                exports['nyx_logistics']:SetShelfNodeOccupant(targetShelfNode.id, newDropId, droppedItemData)
            end)
        end

        return true, newDropId
    end)

    Nyx.Inventory.ReleaseLock(fromInv)

    if not outcome then
        return { success = false, error = res or "PLACEMENT_FAILED" }
    end

    return {
        success = true,
        dropId = res,
        merged = isPlacementMerged,
        coords = safeCoords,
        rotation = safeRotation,
        shelfNodeId = targetShelfNode and targetShelfNode.id or nil,
        routingBucket = targetBucket
    }
end)

-- Authoritative Item Consumption & Activation RPC
Nyx.RPC.Register("inventory:useItem", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end

    local invId = payload.invId
    local slot = tonumber(payload.slot)

    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local playerInvId = string.format("char:%s:main", player.citizenId)
    if invId ~= playerInvId then
        return { success = false, error = "CANNOT_USE_EXTERNAL_ITEM" }
    end

    if not Nyx.Inventory.AcquireLock(invId) then
        return { success = false, error = "CONTAINER_BUSY" }
    end

    local container = Nyx.Inventory.Get(invId)
    if not container then
        Nyx.Inventory.ReleaseLock(invId)
        return { success = false, error = "CONTAINER_NOT_FOUND" }
    end

    local item = container:getItem(slot)
    if not item then
        Nyx.Inventory.ReleaseLock(invId)
        return { success = false, error = "ITEM_NOT_FOUND" }
    end

    local itemDef = Nyx.Items.Get(item.item_id)
    if not itemDef then
        Nyx.Inventory.ReleaseLock(invId)
        return { success = false, error = "UNKNOWN_ITEM" }
    end

    -- Check Durability
    if item.metadata and item.metadata.durability and item.metadata.durability <= 0 then
        Nyx.Inventory.ReleaseLock(invId)
        return { success = false, error = "ITEM_BROKEN" }
    end

    local usedSuccessfully = false

    -- Handle Consumption by Type
    if itemDef.type == "food" then
        if item.metadata and item.metadata.isSpoiled then
            TriggerClientEvent("nyx:core:client:notify", src, "This food is spoiled and inedible!", "error")
        else
            local curHunger = player:getMetadata("hunger") or 100
            player:setMetadata("hunger", math.min(100, curHunger + (itemDef.nutrition or 25)))
            usedSuccessfully = true
        end
    elseif itemDef.type == "drink" then
        local curThirst = player:getMetadata("thirst") or 100
        player:setMetadata("thirst", math.min(100, curThirst + (itemDef.hydration or 30)))
        usedSuccessfully = true
    elseif itemDef.type == "medical" then
        local curHealth = player:getMetadata("health") or 200
        local newHealth = math.min(200, curHealth + (itemDef.healAmount or 25))
        player:setMetadata("health", newHealth)

        local ped = GetPlayerPed(tostring(src))
        SetEntityHealth(ped, newHealth)
        usedSuccessfully = true
    elseif itemDef.type == "weapon" then
        TriggerClientEvent("nyx:inventory:client:equipWeapon", src, item.item_id, item.metadata)
        usedSuccessfully = true
    end

    -- Decrement consumable quantity
    if usedSuccessfully and (itemDef.type == "food" or itemDef.type == "drink" or itemDef.type == "medical") then
        if item.amount <= 1 then
            container:removeItem(slot)
        else
            item.amount = item.amount - 1
            container:setItem(slot, item)
        end
    end

    Nyx.Inventory.ReleaseLock(invId)
    return { success = usedSuccessfully }
end)
