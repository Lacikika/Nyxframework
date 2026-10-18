--[[
    Nyxframework: nyx_vehicles
    File: server/keys.lua
    Description: Dynamic key ownership, digital fobs, physical serial keys,
                 and remote door lock state toggles.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}

-- 1. Check whether a citizen possesses valid keys to a vehicle
function Nyx.Vehicles.HasKey(citizenId, vin, plate)
    if not citizenId or not vin then return false end

    -- Active vehicle fast-path
    local active = Nyx.Vehicles.Active[vin]
    if active and active.ownerCitizenId == citizenId then
        return true
    end

    -- Query vehicle record from DB
    local vehRow = MySQL.single.await([[
        SELECT `owner_citizen_id`, `faction_id` FROM `nyx_vehicles_owned` WHERE `vin` = ?
    ]], { vin })

    if not vehRow then return false end

    -- Owner check
    if vehRow.owner_citizen_id == citizenId then
        return true
    end

    -- Authorized key registry check
    local keyExists = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_vehicles_keys`
        WHERE `vin` = ? AND `holder_citizen_id` = ?
    ]], { vin, citizenId })

    if keyExists and keyExists > 0 then
        return true
    end

    -- Faction fleet membership check
    if vehRow.faction_id and exports['nyx_factions'] and exports['nyx_factions'].HasPermission then
        if exports['nyx_factions']:HasPermission(citizenId, vehRow.faction_id, "fleet:spawn") then
            return true
        end
    end

    -- Physical inventory key fob check
    local invId = string.format("char:%s:main", citizenId)
    if exports['nyx_inventory'] and exports['nyx_inventory'].GetInventory then
        local inv = exports['nyx_inventory']:GetInventory(invId)
        if inv and inv.items then
            for _, item in pairs(inv.items) do
                if item and item.item_id == (Config.Access and Config.Access.KeyItem or "car_keys") then
                    if item.metadata and item.metadata.vin == vin then
                        return true
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

    -- Check if passed netId
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
        -- 2 = locked (cannot enter), 1 = unlocked (can enter)
        SetVehicleDoorsLocked(active.entity, (newLock == 1 and 2 or 1))
    end

    MySQL.prepare.await("UPDATE `nyx_vehicles_owned` SET `lock_state` = ? WHERE `vin` = ?", { newLock, active.vin })

    -- Broadcast visual lights and remote chirp to nearby players
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

-- 3. Issue key to another citizen
function Nyx.Vehicles.GiveKey(src, targetCitId, vin, keyType)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local vehRow = MySQL.single.await("SELECT `vin`, `plate`, `owner_citizen_id` FROM `nyx_vehicles_owned` WHERE `vin` = ?", { vin })
    if not vehRow then return false, "VEHICLE_NOT_FOUND" end

    -- Verify authorizer owns vehicle or holds master key
    if vehRow.owner_citizen_id ~= player.citizenId and not Nyx.Vehicles.HasKey(player.citizenId, vin, vehRow.plate) then
        return false, "UNAUTHORIZED_KEY_ISSUER"
    end

    MySQL.prepare.await([[
        INSERT INTO `nyx_vehicles_keys` (`vin`, `plate`, `holder_citizen_id`, `key_type`)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `key_type` = VALUES(`key_type`)
    ]], {
        vin,
        vehRow.plate,
        targetCitId,
        keyType or "copy"
    })

    -- Grant physical key fob item to target's inventory
    local targetPlayer = exports['nyx_core']:GetPlayerByCitizenId(targetCitId)
    if targetPlayer and exports['nyx_inventory'] and exports['nyx_inventory'].AddItem then
        local invId = string.format("char:%s:main", targetCitId)
        exports['nyx_inventory']:AddItem(invId, Config.Access.KeyItem or "car_keys", 1, {
            vin = vin,
            plate = vehRow.plate,
            keyType = keyType or "copy"
        })
    end

    return true, {
        vin = vin,
        plate = vehRow.plate,
        holder = targetCitId,
        keyType = keyType
    }
end
