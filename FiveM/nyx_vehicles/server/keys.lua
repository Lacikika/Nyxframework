--[[
    Nyxframework: nyx_vehicles
    File: server/keys.lua
    Description: Dynamic key ownership, physical laser-cut keys (item_vehicle_key),
                 corporate fleet RFID transponder cards, lockpicking & hotwire forensics,
                 and latent fingerprint integration with nyx_judiciary.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}

-- Helper: Generate UUIDv4
local function generateUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

-- 1. Check whether a citizen possesses valid keys or RFID access to a vehicle
function Nyx.Vehicles.HasKey(citizenId, vin, plate)
    if not citizenId or not vin then return false end

    -- Active vehicle fast-path
    local active = Nyx.Vehicles.Active[vin]
    if active and active.ownerCitizenId == citizenId then
        return true
    end

    -- Query vehicle record from DB
    local vehRow = MySQL.single.await([[
        SELECT `owner_citizen_id`, `faction_id`, `plate` FROM `nyx_vehicles_owned` WHERE `vin` = ?
    ]], { vin })

    if not vehRow then return false end
    local vPlate = plate or vehRow.plate

    -- 1. Owner check
    if vehRow.owner_citizen_id == citizenId then
        return true
    end

    -- 2. Authorized key registry check
    local keyExists = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_vehicles_keys`
        WHERE `vin` = ? AND `holder_citizen_id` = ?
    ]], { vin, citizenId })

    if keyExists and tonumber(keyExists) > 0 then
        return true
    end

    -- 3. Faction fleet membership / RBAC check
    if vehRow.faction_id and exports['nyx_factions'] and exports['nyx_factions'].HasPermission then
        if exports['nyx_factions']:HasPermission(citizenId, vehRow.faction_id, "fleet:spawn") or
           exports['nyx_factions']:HasPermission(citizenId, vehRow.faction_id, "fleet:use") then
            return true
        end
    end

    -- 4. Corporate RFID token database check
    if vehRow.faction_id then
        local rfidDbCheck = MySQL.scalar.await([[
            SELECT COUNT(*) FROM `nyx_vehicles_rfid_tokens`
            WHERE `faction_id` = ? AND `holder_citizen_id` = ? AND `is_revoked` = 0
              AND (`expires_at` IS NULL OR `expires_at` > CURRENT_TIMESTAMP)
        ]], { vehRow.faction_id, citizenId })

        if rfidDbCheck and tonumber(rfidDbCheck) > 0 then
            return true
        end
    end

    -- 5. Physical inventory key & RFID fob check
    local invId = string.format("char:%s:main", citizenId)
    if exports['nyx_inventory'] and exports['nyx_inventory'].GetInventory then
        local inv = exports['nyx_inventory']:GetInventory(invId)
        if inv and inv.items then
            for _, item in pairs(inv.items) do
                if item and item.item_id then
                    -- Check physical vehicle key
                    if item.item_id == "item_vehicle_key" or item.item_id == "car_keys" then
                        if Nyx.VehicleKeys and Nyx.VehicleKeys.ValidateKeyMatch then
                            local ok = Nyx.VehicleKeys.ValidateKeyMatch(item, vin, vPlate)
                            if ok then return true end
                        elseif item.metadata and (item.metadata.vin == vin or item.metadata.plate == vPlate) then
                            return true
                        end
                    end

                    -- Check corporate fleet RFID card
                    if item.item_id == "rfid_fleet_card" and vehRow.faction_id then
                        if Nyx.VehicleKeys and Nyx.VehicleKeys.ValidateRfidAccess then
                            local ok = Nyx.VehicleKeys.ValidateRfidAccess(item, vehRow.faction_id, os.time(), "driver")
                            if ok then return true end
                        elseif item.metadata and item.metadata.factionId == vehRow.faction_id and not item.metadata.isRevoked then
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

-- 2. Toggle vehicle door lock status
function Nyx.Vehicles.ToggleLock(src, vinOrNetId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local vin = vinOrNetId
    local active = nil

    if type(vinOrNetId) == "number" or tonumber(vinOrNetId) then
        vin = Nyx.Vehicles.ByNetId[tonumber(vinOrNetId)]
    end

    active = Nyx.Vehicles.Active[vin]

    -- Query DB if not in active cache
    if not active then
        local row = MySQL.single.await("SELECT `vin`, `plate`, `lock_state`, `owner_citizen_id` FROM `nyx_vehicles_owned` WHERE `vin` = ?", { vin })
        if not row then return false, "VEHICLE_NOT_FOUND" end

        if not Nyx.Vehicles.HasKey(player.citizenId, row.vin, row.plate) then
            return false, "NO_KEY"
        end

        local newLock = (tonumber(row.lock_state) == 1) and 0 or 1
        MySQL.prepare.await("UPDATE `nyx_vehicles_owned` SET `lock_state` = ? WHERE `vin` = ?", { newLock, vin })
        return true, { isLocked = (newLock == 1), plate = row.plate, vin = vin }
    end

    -- Active entity verification
    if not Nyx.Vehicles.HasKey(player.citizenId, active.vin, active.plate) then
        return false, "NO_KEY"
    end

    local newLock = (active.lockState == 1) and 0 or 1
    active.lockState = newLock

    if DoesEntityExist(active.entity) then
        SetVehicleDoorsLocked(active.entity, (newLock == 1 and 2 or 1))
    end

    MySQL.prepare.await("UPDATE `nyx_vehicles_owned` SET `lock_state` = ? WHERE `vin` = ?", { newLock, active.vin })

    TriggerClientEvent("nyx:vehicles:client:lockToggled", -1, {
        netId = active.netId,
        isLocked = (newLock == 1),
        coords = GetEntityCoords(active.entity)
    })

    return true, {
        isLocked = (newLock == 1),
        plate = active.plate,
        vin = active.vin
    }
end

-- 3. Check Ignition Authorization (Keys, RFID, or Hotwired)
function Nyx.Vehicles.CheckIgnition(src, vinOrNetId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local vin = vinOrNetId
    if type(vinOrNetId) == "number" or tonumber(vinOrNetId) then
        vin = Nyx.Vehicles.ByNetId[tonumber(vinOrNetId)]
    end

    local active = Nyx.Vehicles.Active[vin]
    local plate = active and active.plate or nil

    -- 1. Check if vehicle was hotwired in this active session
    if active and active.hotwired == true then
        return true, { authorized = true, method = "hotwired", vin = vin, plate = plate }
    end

    -- 2. Check if player has valid key / RFID
    local hasKey = Nyx.Vehicles.HasKey(player.citizenId, vin, plate)
    if hasKey then
        return true, { authorized = true, method = "key_or_token", vin = vin, plate = plate }
    end

    return true, { authorized = false, reason = "NO_KEY", vin = vin, plate = plate }
end

-- 4. Attempt Vehicle Door Lockpicking with Latent Forensic Fingerprint Logging
function Nyx.Vehicles.AttemptLockpick(src, netId, useGloves)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local entity = NetworkGetEntityFromNetworkId(tonumber(netId))
    if not DoesEntityExist(entity) then
        return false, "VEHICLE_NOT_FOUND"
    end

    local vin = Nyx.Vehicles.ByNetId[tonumber(netId)]
    local active = Nyx.Vehicles.Active[vin]
    local plate = active and active.plate or GetVehicleNumberPlateText(entity)

    -- Verify player possesses lockpick
    local invId = string.format("char:%s:main", player.citizenId)
    local hasLockpick = false
    local lockpickItemName = "tool_lockpick"

    if exports['nyx_inventory'] and exports['nyx_inventory'].GetInventory then
        local inv = exports['nyx_inventory']:GetInventory(invId)
        if inv and inv.items then
            for _, item in pairs(inv.items) do
                if item and (item.item_id == "tool_lockpick" or item.item_id == "tool_lockpick_advanced") then
                    hasLockpick = true
                    lockpickItemName = item.item_id
                    break
                end
            end
        end
    else
        hasLockpick = true
    end

    if not hasLockpick then
        return false, "NO_LOCKPICK_TOOL"
    end

    -- Calculate lockpick probability
    local vehClass = GetVehicleClass(entity)
    local secUpgrade = 0
    local chances = Nyx.VehicleKeys.CalculateLockpickChance(lockpickItemName, vehClass, secUpgrade)

    local roll = math.random()
    local isSuccess = roll <= chances.successChance

    -- Roll pick breakage
    local breakRoll = math.random()
    local isBroken = breakRoll <= chances.breakChance
    if isBroken and exports['nyx_inventory'] and exports['nyx_inventory'].RemoveItem then
        exports['nyx_inventory']:RemoveItem(invId, lockpickItemName, 1)
    end

    -- Roll alarm trigger
    local alarmRoll = math.random()
    local alarmThreshold = isSuccess and chances.alarmChanceSuccess or chances.alarmChanceFail
    local isAlarm = alarmRoll <= alarmThreshold

    local vehCoords = GetEntityCoords(entity)

    -- Forensics: Glove verification
    local hasGloves = (useGloves == true)
    if not hasGloves and player.getMetadata then
        hasGloves = (player:getMetadata("glovesEquipped") == true)
    end

    -- Check inventory for examination gloves if useGloves requested
    if useGloves and exports['nyx_inventory'] and exports['nyx_inventory'].GetInventory then
        local inv = exports['nyx_inventory']:GetInventory(invId)
        local foundGloves = false
        if inv and inv.items then
            for _, item in pairs(inv.items) do
                if item and (item.item_id == "latex_gloves" or item.item_id == "nitrile_gloves") then
                    foundGloves = true
                    break
                end
            end
        end
        hasGloves = foundGloves
    end

    local trace = Nyx.VehicleKeys.DetermineForensicTrace(hasGloves, player.citizenId, { x = vehCoords.x, y = vehCoords.y, z = vehCoords.z })
    local evidenceId = nil
    local evidenceHash = nil

    if trace.leavesFingerprint then
        if exports['nyx_judiciary'] and exports['nyx_judiciary'].RegisterFingerprintEvent then
            local eId, eHash = exports['nyx_judiciary']:RegisterFingerprintEvent(src, "vehicle_door_lock", vehCoords)
            evidenceId = eId
            evidenceHash = eHash
        else
            evidenceId = generateUUID()
            evidenceHash = trace.hash
        end
    end

    -- Record attempt in database audit ledger
    local attemptUuid = generateUUID()
    MySQL.prepare.await([[
        INSERT INTO `nyx_vehicles_lockpick_attempts`
            (`attempt_uuid`, `vin`, `plate`, `citizen_id`, `action_type`, `success`,
             `alarm_triggered`, `tool_used`, `tool_broken`, `had_gloves`,
             `fingerprint_evidence_id`, `fingerprint_hash`, `coords`)
        VALUES (?, ?, ?, ?, 'door_lockpick', ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        attemptUuid,
        vin or ("UNREGISTERED-" .. plate),
        plate,
        player.citizenId,
        isSuccess and 1 or 0,
        isAlarm and 1 or 0,
        lockpickItemName,
        isBroken and 1 or 0,
        hasGloves and 1 or 0,
        evidenceId,
        evidenceHash,
        json.encode({ x = vehCoords.x, y = vehCoords.y, z = vehCoords.z })
    })

    -- Handle outcome
    if isSuccess then
        if active then
            active.lockState = 0
        end
        SetVehicleDoorsLocked(entity, 1)
        if vin then
            MySQL.prepare.await("UPDATE `nyx_vehicles_owned` SET `lock_state` = 0 WHERE `vin` = ?", { vin })
        end

        TriggerClientEvent("nyx:vehicles:client:lockToggled", -1, {
            netId = tonumber(netId),
            isLocked = false,
            coords = vehCoords
        })
    end

    if isAlarm then
        if active then active.alarmState = 1 end
        TriggerClientEvent("nyx:vehicles:client:alarmTriggered", -1, {
            netId = tonumber(netId),
            coords = vehCoords,
            plate = plate
        })

        if exports['nyx_mdt'] and exports['nyx_mdt'].CreateDispatchCall then
            exports['nyx_mdt']:CreateDispatchCall("10-99", "Vehicle Tampering / Alarm", vehCoords, {
                plate = plate,
                model = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(entity)))
            })
        end
    end

    return true, {
        unlocked = isSuccess,
        toolBroken = isBroken,
        alarmTriggered = isAlarm,
        fingerprintLeft = trace.leavesFingerprint,
        evidenceId = evidenceId,
        plate = plate,
        vin = vin
    }
end

-- 5. Attempt Ignition Hotwiring
function Nyx.Vehicles.AttemptHotwire(src, netId, useGloves)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local entity = NetworkGetEntityFromNetworkId(tonumber(netId))
    if not DoesEntityExist(entity) then
        return false, "VEHICLE_NOT_FOUND"
    end

    local vin = Nyx.Vehicles.ByNetId[tonumber(netId)]
    local active = Nyx.Vehicles.Active[vin]
    local plate = active and active.plate or GetVehicleNumberPlateText(entity)

    -- Hotwire base probability: 45% success
    local roll = math.random()
    local isSuccess = roll <= 0.45

    local vehCoords = GetEntityCoords(entity)

    -- Glove check
    local hasGloves = (useGloves == true)
    if not hasGloves and player.getMetadata then
        hasGloves = (player:getMetadata("glovesEquipped") == true)
    end

    local trace = Nyx.VehicleKeys.DetermineForensicTrace(hasGloves, player.citizenId, { x = vehCoords.x, y = vehCoords.y, z = vehCoords.z })
    local evidenceId = nil
    local evidenceHash = nil

    if trace.leavesFingerprint then
        if exports['nyx_judiciary'] and exports['nyx_judiciary'].RegisterFingerprintEvent then
            local eId, eHash = exports['nyx_judiciary']:RegisterFingerprintEvent(src, "ignition_steering_column", vehCoords)
            evidenceId = eId
            evidenceHash = eHash
        else
            evidenceId = generateUUID()
            evidenceHash = trace.hash
        end
    end

    local isAlarm = (not isSuccess) and (math.random() <= 0.40)

    -- Record hotwire attempt in audit ledger
    local attemptUuid = generateUUID()
    MySQL.prepare.await([[
        INSERT INTO `nyx_vehicles_lockpick_attempts`
            (`attempt_uuid`, `vin`, `plate`, `citizen_id`, `action_type`, `success`,
             `alarm_triggered`, `tool_used`, `tool_broken`, `had_gloves`,
             `fingerprint_evidence_id`, `fingerprint_hash`, `coords`)
        VALUES (?, ?, ?, ?, 'ignition_hotwire', ?, ?, 'hotwire_wires', 0, ?, ?, ?, ?)
    ]], {
        attemptUuid,
        vin or ("UNREGISTERED-" .. plate),
        plate,
        player.citizenId,
        isSuccess and 1 or 0,
        isAlarm and 1 or 0,
        hasGloves and 1 or 0,
        evidenceId,
        evidenceHash,
        json.encode({ x = vehCoords.x, y = vehCoords.y, z = vehCoords.z })
    })

    if isSuccess then
        if active then
            active.hotwired = true
        end
        if vin then
            MySQL.prepare.await("UPDATE `nyx_vehicles_owned` SET `hotwired` = 1 WHERE `vin` = ?", { vin })
        end
    end

    if isAlarm then
        TriggerClientEvent("nyx:vehicles:client:alarmTriggered", -1, {
            netId = tonumber(netId),
            coords = vehCoords,
            plate = plate
        })
    end

    return true, {
        hotwired = isSuccess,
        alarmTriggered = isAlarm,
        fingerprintLeft = trace.leavesFingerprint,
        evidenceId = evidenceId,
        plate = plate,
        vin = vin
    }
end

-- 6. Issue Physical Laser-Cut Key (item_vehicle_key)
function Nyx.Vehicles.IssuePhysicalKey(src, vin, targetCitId, keyType)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local vehRow = MySQL.single.await("SELECT `vin`, `plate`, `owner_citizen_id`, `model_name` FROM `nyx_vehicles_owned` WHERE `vin` = ?", { vin })
    if not vehRow then return false, "VEHICLE_NOT_FOUND" end

    -- Verify authorizer owns vehicle or holds master key
    if vehRow.owner_citizen_id ~= player.citizenId and not Nyx.Vehicles.HasKey(player.citizenId, vin, vehRow.plate) then
        return false, "UNAUTHORIZED_KEY_ISSUER"
    end

    local kType = keyType or "copy"
    local payload = {
        vin = vin,
        plate = vehRow.plate,
        keyType = kType,
        targetCitizenId = targetCitId or player.citizenId
    }

    local valid, err = Nyx.VehicleKeys.ValidateKeyCreationPayload(payload)
    if not valid then
        return false, err
    end

    -- Insert or update key assignment in database
    MySQL.prepare.await([[
        INSERT INTO `nyx_vehicles_keys` (`vin`, `plate`, `holder_citizen_id`, `key_type`)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `key_type` = VALUES(`key_type`)
    ]], {
        vin,
        vehRow.plate,
        payload.targetCitizenId,
        kType
    })

    -- Grant physical item_vehicle_key to recipient's inventory
    local targetPlayer = exports['nyx_core']:GetPlayerByCitizenId(payload.targetCitizenId)
    if targetPlayer and exports['nyx_inventory'] and exports['nyx_inventory'].AddItem then
        local invId = string.format("char:%s:main", payload.targetCitizenId)
        exports['nyx_inventory']:AddItem(invId, "item_vehicle_key", 1, {
            vin = vin,
            plate = vehRow.plate,
            keyType = kType,
            label = string.format("%s (%s)", vehRow.model_name or "Vehicle", vehRow.plate),
            issuedAt = os.time(),
            issuerCitizenId = player.citizenId
        })
    end

    return true, {
        vin = vin,
        plate = vehRow.plate,
        holder = payload.targetCitizenId,
        keyType = kType
    }
end

-- Backward compatibility alias
Nyx.Vehicles.GiveKey = Nyx.Vehicles.IssuePhysicalKey

-- 7. Issue Corporate Fleet RFID Proximity Token
function Nyx.Vehicles.IssueRfidToken(src, factionId, targetCitId, accessLevel, label)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    -- Verify corporate fleet management permission
    if exports['nyx_factions'] and exports['nyx_factions'].HasPermission then
        if not exports['nyx_factions']:HasPermission(player.citizenId, factionId, "fleet:manage") and
           not exports['nyx_factions']:HasPermission(player.citizenId, factionId, "fleet:*") then
            return false, "UNAUTHORIZED_FLEET_MANAGER"
        end
    end

    local payload = {
        factionId = factionId,
        targetCitizenId = targetCitId or player.citizenId,
        accessLevel = accessLevel or "driver",
        label = label or "Corporate Fleet Keycard"
    }

    local valid, err = Nyx.VehicleKeys.ValidateRfidCreationPayload(payload)
    if not valid then
        return false, err
    end

    local tokenUuid = "rfid-" .. generateUUID()

    MySQL.prepare.await([[
        INSERT INTO `nyx_vehicles_rfid_tokens`
            (`token_uuid`, `faction_id`, `holder_citizen_id`, `access_level`, `label`, `is_revoked`)
        VALUES (?, ?, ?, ?, ?, 0)
    ]], {
        tokenUuid,
        payload.factionId,
        payload.targetCitizenId,
        payload.accessLevel,
        payload.label
    })

    -- Grant physical rfid_fleet_card to recipient
    local targetPlayer = exports['nyx_core']:GetPlayerByCitizenId(payload.targetCitizenId)
    if targetPlayer and exports['nyx_inventory'] and exports['nyx_inventory'].AddItem then
        local invId = string.format("char:%s:main", payload.targetCitizenId)
        exports['nyx_inventory']:AddItem(invId, "rfid_fleet_card", 1, {
            tokenUuid = tokenUuid,
            factionId = payload.factionId,
            accessLevel = payload.accessLevel,
            label = payload.label,
            isRevoked = false,
            issuedAt = os.time(),
            issuerCitizenId = player.citizenId
        })
    end

    return true, {
        tokenUuid = tokenUuid,
        factionId = payload.factionId,
        holder = payload.targetCitizenId,
        accessLevel = payload.accessLevel,
        label = payload.label
    }
end

-- 8. Revoke Corporate Fleet RFID Token
function Nyx.Vehicles.RevokeRfidToken(src, tokenUuid, reason)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local row = MySQL.single.await([[
        SELECT `token_id`, `faction_id`, `is_revoked` FROM `nyx_vehicles_rfid_tokens` WHERE `token_uuid` = ?
    ]], { tokenUuid })

    if not row then
        return false, "TOKEN_NOT_FOUND"
    end

    -- Verify manager permission
    if exports['nyx_factions'] and exports['nyx_factions'].HasPermission then
        if not exports['nyx_factions']:HasPermission(player.citizenId, row.faction_id, "fleet:manage") and
           not exports['nyx_factions']:HasPermission(player.citizenId, row.faction_id, "fleet:*") then
            return false, "UNAUTHORIZED_FLEET_MANAGER"
        end
    end

    MySQL.prepare.await([[
        UPDATE `nyx_vehicles_rfid_tokens`
        SET `is_revoked` = 1, `revoked_by` = ?, `revocation_reason` = ?
        WHERE `token_uuid` = ?
    ]], { player.citizenId, reason or "Revoked by fleet manager", tokenUuid })

    return true, { tokenUuid = tokenUuid, isRevoked = true }
end

-- 9. Query Lockpick Audit History for Detectives & Police MDT
function Nyx.Vehicles.GetLockpickHistory(vin)
    if not vin then return {} end
    local rows = MySQL.query.await([[
        SELECT `attempt_uuid`, `vin`, `plate`, `citizen_id`, `action_type`, `success`,
               `alarm_triggered`, `tool_used`, `tool_broken`, `had_gloves`,
               `fingerprint_evidence_id`, `fingerprint_hash`, `attempted_at`
        FROM `nyx_vehicles_lockpick_attempts`
        WHERE `vin` = ?
        ORDER BY `attempted_at` DESC
        LIMIT 20
    ]], { vin })

    return rows or {}
end

-- 10. Register RPC Handlers for Vehicles Key & Forensics Pipeline
CreateThread(function()
    Wait(500)
    if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
        exports['nyx_core']:RegisterRPC("vehicles:checkIgnition", function(src, vinOrNetId)
            local ok, res = Nyx.Vehicles.CheckIgnition(src, vinOrNetId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        exports['nyx_core']:RegisterRPC("vehicles:attemptLockpick", function(src, netId, useGloves)
            local ok, res = Nyx.Vehicles.AttemptLockpick(src, netId, useGloves)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        exports['nyx_core']:RegisterRPC("vehicles:attemptHotwire", function(src, netId, useGloves)
            local ok, res = Nyx.Vehicles.AttemptHotwire(src, netId, useGloves)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        exports['nyx_core']:RegisterRPC("vehicles:issuePhysicalKey", function(src, vin, targetCitId, keyType)
            local ok, res = Nyx.Vehicles.IssuePhysicalKey(src, vin, targetCitId, keyType)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        exports['nyx_core']:RegisterRPC("vehicles:issueRfidToken", function(src, factionId, targetCitId, accessLevel, label)
            local ok, res = Nyx.Vehicles.IssueRfidToken(src, factionId, targetCitId, accessLevel, label)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        exports['nyx_core']:RegisterRPC("vehicles:revokeRfidToken", function(src, tokenUuid, reason)
            local ok, res = Nyx.Vehicles.RevokeRfidToken(src, tokenUuid, reason)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        exports['nyx_core']:RegisterRPC("vehicles:getLockpickHistory", function(src, vin)
            local history = Nyx.Vehicles.GetLockpickHistory(vin)
            return { success = true, history = history }
        end)
    end
end)
