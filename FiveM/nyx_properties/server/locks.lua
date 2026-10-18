--[[
    Nyxframework: nyx_properties
    File: server/locks.lua
    Description: 5-Tier RFID key verification, lock state persistence,
                 delegated access control, and judicial police breach.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}

-- 1. Check if citizen holds a key for property with minimum tier
function Nyx.Properties.HasKey(propertyId, citizenId, minTier)
    if not propertyId or not citizenId then return false, 0 end
    minTier = minTier or 1

    local row = MySQL.single.await([[
        SELECT `tier` FROM `nyx_property_keys`
        WHERE `property_id` = ? AND `citizen_id` = ?
    ]], { propertyId, citizenId })

    if row and row.tier then
        return (row.tier >= minTier), row.tier
    end

    -- Check if citizen has enforcement override (Police Chief / High Court Judge)
    local player = exports['nyx_core']:GetPlayerByCitizenId(citizenId)
    if player and player.hasPermission and player.hasPermission("emergency_enforcement") then
        return true, 5
    end

    return false, 0
end

-- 2. RPC: Toggle Doorlock State (Requires Tier >= 2)
exports['nyx_core']:RegisterRPC("properties:toggleLock", function(src, propertyId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    propertyId = tonumber(propertyId)
    local prop = Nyx.Properties.Loaded[propertyId]
    if not prop then return { success = false, error = "PROPERTY_NOT_FOUND" } end

    -- Check permission (Tier 2: Resident / Employee or higher)
    local hasKey, tier = Nyx.Properties.HasKey(propertyId, player.citizenId, 2)
    if not hasKey then
        return { success = false, error = "INSUFFICIENT_KEY_TIER" }
    end

    -- Check electrical power status for electronic maglocks & utility delinquency cut-off
    local isPowered = true
    if exports['nyx_services'] and exports['nyx_services'].IsCoordsPowered then
        isPowered = exports['nyx_services']:IsCoordsPowered(prop.entrance)
    end
    if prop.isUtilitySuspended and not prop.hasBackupGenerator then
        isPowered = false
    end

    if not isPowered and not prop.hasBackupGenerator and (prop.type == 'commercial' or prop.type == 'industrial') then
        local errReason = prop.isUtilitySuspended and "LOCK_OFFLINE_UTILITY_CUTOFF" or "LOCK_OFFLINE_NO_POWER"
        local errMsg = prop.isUtilitySuspended and "A mágneszár közműtartozás miatti áramlekapcsolás okán offline!" or "A mágneszár áramellátás hiányában nem működtethető!"
        return { success = false, error = errReason, message = errMsg }
    end

    -- Toggle state
    prop.isLocked = not prop.isLocked
    local lockDbVal = prop.isLocked and 1 or 0

    MySQL.prepare([[
        UPDATE `nyx_properties` SET `is_locked` = ? WHERE `property_id` = ?
    ]], { lockDbVal, propertyId })

    -- Audit trail
    MySQL.prepare([[
        INSERT INTO `nyx_property_audit`
            (`property_id`, `action`, `actor_citizen_id`, `notes`)
        VALUES (?, 'LOCK_TOGGLE', ?, ?)
    ]], { propertyId, player.citizenId, prop.isLocked and "Door Locked" or "Door Unlocked" })

    -- Broadcast state change to all clients
    TriggerClientEvent("nyx:properties:client:lockUpdated", -1, propertyId, prop.isLocked)

    return { success = true, propertyId = propertyId, isLocked = prop.isLocked }
end)

-- 3. RPC: Issue RFID Key to Another Citizen (Requires Tier >= 3)
exports['nyx_core']:RegisterRPC("properties:issueKey", function(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local propertyId = payload and tonumber(payload.propertyId)
    local targetCitizenId = payload and payload.targetCitizenId
    local requestedTier = payload and tonumber(payload.tier) or 1
    local label = payload and payload.label or "Kulcskártya"

    local prop = Nyx.Properties.Loaded[propertyId]
    if not prop then return { success = false, error = "PROPERTY_NOT_FOUND" } end

    -- Verify caller key tier (Must be at least Manager Tier 3, and can only issue tiers strictly below caller)
    local hasKey, callerTier = Nyx.Properties.HasKey(propertyId, player.citizenId, 3)
    if not hasKey or requestedTier >= callerTier then
        return { success = false, error = "INSUFFICIENT_AUTHORITY" }
    end

    MySQL.prepare([[
        INSERT INTO `nyx_property_keys` (`property_id`, `citizen_id`, `tier`, `label`)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `tier` = VALUES(`tier`), `label` = VALUES(`label`)
    ]], { propertyId, targetCitizenId, requestedTier, label })

    MySQL.prepare([[
        INSERT INTO `nyx_property_audit`
            (`property_id`, `action`, `actor_citizen_id`, `notes`)
        VALUES (?, 'KEY_ISSUED', ?, ?)
    ]], { propertyId, player.citizenId, string.format("Tier %d key issued to %s", requestedTier, targetCitizenId) })

    return { success = true, targetCitizenId = targetCitizenId, tier = requestedTier }
end)

-- 4. RPC: Revoke RFID Key (Requires Tier >= 3)
exports['nyx_core']:RegisterRPC("properties:revokeKey", function(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local propertyId = payload and tonumber(payload.propertyId)
    local targetCitizenId = payload and payload.targetCitizenId

    local prop = Nyx.Properties.Loaded[propertyId]
    if not prop then return { success = false, error = "PROPERTY_NOT_FOUND" } end

    local hasKey, callerTier = Nyx.Properties.HasKey(propertyId, player.citizenId, 3)
    if not hasKey then
        return { success = false, error = "INSUFFICIENT_AUTHORITY" }
    end

    MySQL.prepare([[
        DELETE FROM `nyx_property_keys`
        WHERE `property_id` = ? AND `citizen_id` = ?
    ]], { propertyId, targetCitizenId })

    MySQL.prepare([[
        INSERT INTO `nyx_property_audit`
            (`property_id`, `action`, `actor_citizen_id`, `notes`)
        VALUES (?, 'KEY_REVOKED', ?, ?)
    ]], { propertyId, player.citizenId, string.format("Key revoked from %s", targetCitizenId) })

    return { success = true, revokedCitizenId = targetCitizenId }
end)

-- 5. RPC: Emergency Judicial Police Breach
exports['nyx_core']:RegisterRPC("properties:policeBreach", function(src, propertyId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    propertyId = tonumber(propertyId)
    local prop = Nyx.Properties.Loaded[propertyId]
    if not prop then return { success = false, error = "PROPERTY_NOT_FOUND" } end

    -- Verify active search warrant from nyx_judiciary
    local hasWarrant = false
    if exports['nyx_judiciary'] and exports['nyx_judiciary'].HasActiveSearchWarrant then
        hasWarrant = exports['nyx_judiciary']:HasActiveSearchWarrant(prop.code)
    else
        hasWarrant = (player.hasPermission and player.hasPermission("police_officer"))
    end

    if not hasWarrant then
        return { success = false, error = "JUDICIAL_WARRANT_REQUIRED" }
    end

    -- Force unlock door
    prop.isLocked = false
    MySQL.prepare([[
        UPDATE `nyx_properties` SET `is_locked` = 0 WHERE `property_id` = ?
    ]], { propertyId })

    -- High-priority audit record
    MySQL.prepare([[
        INSERT INTO `nyx_property_audit`
            (`property_id`, `action`, `actor_citizen_id`, `notes`)
        VALUES (?, 'POLICE_BREACH', ?, 'Judicial search warrant breach executed')
    ]], { propertyId, player.citizenId })

    TriggerClientEvent("nyx:properties:client:lockUpdated", -1, propertyId, false)

    -- Alert property owner if online
    if prop.ownerCitizenId then
        local ownerPlayer = exports['nyx_core']:GetPlayerByCitizenId(prop.ownerCitizenId)
        if ownerPlayer then
            TriggerClientEvent("nyx:ui:notify", ownerPlayer.source, {
                type = "error",
                title = "BIZTONSÁGI RIASZTÁS",
                message = string.format("Hatósági behatolás történt az ingatlanodban (%s)!", prop.label)
            })
        end
    end

    return { success = true, propertyId = propertyId, breached = true }
end)
