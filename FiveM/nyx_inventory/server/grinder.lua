--[[
    Nyxframework: nyx_inventory
    File: server/grinder.lua
    Description: Authoritative server-side weapon serial number grinding,
                 tool wear deduction, disk consumption, forensic contamination,
                 and database audit synchronization.
]]

Nyx = Nyx or {}
Nyx.Inventory = Nyx.Inventory or {}
Nyx.SerialGrind = Nyx.SerialGrind or {}

-- 1. Helper: Locate item in container by itemId
local function findItemByItemId(container, itemId)
    if not container or not container.items then return nil, nil end
    for slot, item in pairs(container.items) do
        if item and item.item_id == itemId then
            return item, slot
        end
    end
    return nil, nil
end

-- 2. Authoritative Grind Function
function Nyx.SerialGrind.ExecuteGrind(invId, weaponSlot, toolSlot, diskSlot, src)
    local container = Nyx.Inventory.Get(invId)
    if not container then
        return false, "CONTAINER_NOT_FOUND"
    end

    if not Nyx.Inventory.AcquireLock(invId) then
        return false, "CONTAINER_BUSY"
    end

    local success, res = pcall(function()
        local weaponItem = container:getItem(weaponSlot)
        if not weaponItem then
            return false, "WEAPON_NOT_FOUND"
        end

        local toolItem = container:getItem(toolSlot)
        if not toolItem then
            return false, "TOOL_NOT_FOUND"
        end

        local toolProfile = Nyx.SerialGrind.Tools[toolItem.item_id]
        if not toolProfile then
            return false, "INVALID_TOOL_PROFILE"
        end

        local diskItem = nil
        if toolProfile.requiresDisk then
            if diskSlot then
                diskItem = container:getItem(diskSlot)
            else
                diskItem, diskSlot = findItemByItemId(container, toolProfile.diskItem)
            end
        end

        local canGrind, err = Nyx.SerialGrind.CanGrindWeapon(weaponItem, toolItem, diskItem)
        if not canGrind then
            return false, err
        end

        -- Check if player is wearing examination/forensic gloves
        local hasGloves = false
        local player = src and exports['nyx_core']:GetPlayer(src)
        if player then
            hasGloves = (player:getMetadata("wearingGloves") == true) or
                        (player:getMetadata("glovesEquipped") == true)
            if not hasGloves then
                local g1 = findItemByItemId(container, 'latex_gloves')
                local g2 = findItemByItemId(container, 'nitrile_gloves')
                hasGloves = (g1 ~= nil or g2 ~= nil)
            end
        end

        -- Calculate outcome
        local outcome = Nyx.SerialGrind.CalculateGrindOutcome(weaponItem, toolItem, {
            hasGloves = hasGloves,
            seed = os.time() + (src or 0)
        })

        -- Mutate Weapon Item Metadata
        weaponItem.metadata = weaponItem.metadata or {}
        local originalSerial = weaponItem.metadata.serialNumber or outcome.originalSerial
        local weaponUuid = weaponItem.item_uuid or Nyx.RPC.GenerateNonce()

        weaponItem.metadata.originalSerial = originalSerial
        weaponItem.metadata.serialNumber = outcome.scratchedSerial
        weaponItem.metadata.scratched = true
        weaponItem.metadata.grindQuality = outcome.grindQuality
        weaponItem.metadata.grindedAt = os.time()
        weaponItem.metadata.grindedBy = player and player.citizenId or "UNKNOWN"
        weaponItem.metadata.durability = outcome.remainingWeaponDurability

        container:setItem(weaponSlot, weaponItem)

        -- Deduct Tool Wear & Handle Breakage
        if outcome.isToolBroken then
            container:removeItem(toolSlot)
        else
            toolItem.metadata = toolItem.metadata or {}
            toolItem.metadata.durability = outcome.remainingToolDurability
            container:setItem(toolSlot, toolItem)
        end

        -- Deduct Grinding Disk
        if outcome.consumedDisk and diskItem and diskSlot then
            if diskItem.amount <= 1 then
                container:removeItem(diskSlot)
            else
                diskItem.amount = diskItem.amount - 1
                container:setItem(diskSlot, diskItem)
            end
        end

        container:save()

        -- Persist to Database Audit Table
        MySQL.Async.execute([[
            INSERT INTO `nyx_inventory_ground_weapons`
                (`weapon_uuid`, `weapon_item`, `original_serial`, `grind_quality`, `grinded_by_citizen_id`, `grinded_at`, `tool_serial`)
            VALUES
                (?, ?, ?, ?, ?, NOW(), ?)
            ON DUPLICATE KEY UPDATE
                `grind_quality` = VALUES(`grind_quality`),
                `grinded_at` = NOW()
        ]], {
            weaponUuid,
            weaponItem.item_id,
            originalSerial,
            outcome.grindQuality,
            player and player.citizenId or nil,
            outcome.toolSerial
        })

        -- Forensic Scene Contamination
        if src and player then
            local ped = GetPlayerPed(tostring(src))
            local coords = (ped and DoesEntityExist(ped)) and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0)

            -- 1. Deposit Mechanical Toolmark Evidence Striation
            if exports['nyx_judiciary'] and exports['nyx_judiciary'].RegisterToolmarkEvent then
                pcall(function()
                    exports['nyx_judiciary']:RegisterToolmarkEvent(src, "tool_angle_grinder", "Firearm Stamped Serial Number Plate", coords, outcome.toolSerial)
                end)
            end

            -- 2. Deposit Latent Fingerprint if operating bare-handed
            if outcome.fingerprintLeft and exports['nyx_judiciary'] and exports['nyx_judiciary'].RegisterFingerprintEvent then
                pcall(function()
                    exports['nyx_judiciary']:RegisterFingerprintEvent(src, coords)
                end)
            end

            -- 3. Deposit Biological DNA / Blood if operator sustained laceration
            if outcome.dnaLeft and exports['nyx_judiciary'] and exports['nyx_judiciary'].RegisterTraumaEvent then
                pcall(function()
                    exports['nyx_judiciary']:RegisterTraumaEvent(src, src, "abrasion", coords)
                end)
            end

            -- 4. Broadcast Acoustic Grinder Whine & Sparks to Nearby Clients
            TriggerClientEvent("nyx:inventory:client:weaponGrinded", -1, {
                coords = { x = coords.x, y = coords.y, z = coords.z },
                radius = outcome.noiseRadius
            })
        end

        return true, outcome, weaponItem
    end)

    Nyx.Inventory.ReleaseLock(invId)
    if not success then
        return false, res
    end
    return res, select(2, pcall(function() return res end))
end

-- 3. RPC Endpoint: inventory:grindWeaponSerial
Nyx.RPC.Register("inventory:grindWeaponSerial", function(src, payload)
    local valid, err = Nyx.SerialGrind.ValidatePayload(payload)
    if not valid then
        return nil, err
    end

    local player = exports['nyx_core']:GetPlayer(src)
    if not player then
        return nil, "UNAUTHORIZED"
    end

    local invId = payload.invId or string.format("char:%s:main", player.citizenId)
    if not Nyx.Inventory.ValidateAccess(src, invId) then
        return nil, "ACCESS_DENIED"
    end

    local ok, outcomeOrErr, weaponItem = Nyx.SerialGrind.ExecuteGrind(invId, payload.weaponSlot, payload.toolSlot, payload.diskSlot, src)
    if not ok then
        return nil, outcomeOrErr
    end

    return {
        success = true,
        outcome = outcomeOrErr,
        weapon = weaponItem
    }
end)
