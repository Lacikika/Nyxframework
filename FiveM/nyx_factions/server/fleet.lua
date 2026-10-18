--[[
    Nyxframework: nyx_factions
    File: server/fleet.lua
    Description: Commercial fleet management, depot check-out/check-in engine,
                 and mechanical condition serialization.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}

-- Utility: Generate 17-character vehicle identification number (VIN)
local function generateVIN()
    local chars = "0123456789ABCDEFGHJKLMNPRSTUVWXYZ"
    local res = { "1", "N", "Y", "X" }
    for i = 5, 17 do
        local r = math.random(1, #chars)
        res[i] = chars:sub(r, r)
    end
    return table.concat(res)
end

-- Utility: Generate commercial vehicle plate (e.g. "CORP 102")
local function generatePlate(prefix)
    local num = math.random(100, 999)
    local p = prefix and string.upper(prefix:sub(1, 4)) or "NYX"
    return string.format("%s %d", p, num)
end

-- 1. Register a new commercial utility vehicle to a faction
function Nyx.Factions.RegisterVehicle(actorCitizenId, factionId, modelHash, depotId, customPlate)
    if actorCitizenId ~= "SYSTEM" and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "fleet:manage") then
        return false, "INSUFFICIENT_PERMISSIONS_FLEET_MANAGE"
    end

    local faction = Nyx.Factions.GetFaction(factionId)
    if not faction then return false, "FACTION_NOT_FOUND" end

    local vin = generateVIN()
    local plate = customPlate or generatePlate(faction.charter_type)

    local defaultCondition = {
        engine = 1000.0,
        body = 1000.0,
        fuel = 100.0
    }

    local insertOk = MySQL.prepare.await([[
        INSERT INTO `nyx_factions_fleet`
            (`vin`, `plate`, `faction_id`, `model_hash`, `parking_depot_id`, `storage_state`, `condition_data`)
        VALUES (?, ?, ?, ?, ?, 'stored', ?)
    ]], {
        vin,
        plate,
        factionId,
        tonumber(modelHash) or `burrito`,
        depotId or "depot_port_ls",
        json.encode(defaultCondition)
    })

    if not insertOk then
        return false, "DATABASE_ERROR"
    end

    return true, {
        vin = vin,
        plate = plate,
        modelHash = modelHash,
        depotId = depotId,
        condition = defaultCondition
    }
end

-- 2. Spawn / Check out vehicle from commercial depot
function Nyx.Factions.SpawnVehicle(src, factionId, vin, depotId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    if not Nyx.Factions.HasPermission(player.citizenId, factionId, "fleet:spawn") then
        return false, "INSUFFICIENT_PERMISSIONS"
    end

    local vehRow = MySQL.single.await([[
        SELECT * FROM `nyx_factions_fleet`
        WHERE `vin` = ? AND `faction_id` = ?
    ]], { vin, factionId })

    if not vehRow then
        return false, "VEHICLE_NOT_FOUND"
    end

    if vehRow.storage_state ~= "stored" then
        return false, "VEHICLE_ALREADY_ACTIVE_OR_IMPOUNDED"
    end

    local depot = Config.FleetDepots and Config.FleetDepots[depotId]
    if not depot then
        return false, "INVALID_DEPOT"
    end

    -- Update storage state to active
    MySQL.prepare.await([[
        UPDATE `nyx_factions_fleet`
        SET `storage_state` = 'active'
        WHERE `vin` = ?
    ]], { vin })

    local cond = { engine = 1000.0, body = 1000.0, fuel = 100.0 }
    if type(vehRow.condition_data) == "string" then
        local ok, parsed = pcall(json.decode, vehRow.condition_data)
        if ok and type(parsed) == "table" then cond = parsed end
    elseif type(vehRow.condition_data) == "table" then
        cond = vehRow.condition_data
    end

    return true, {
        vin = vehRow.vin,
        plate = vehRow.plate,
        modelHash = vehRow.model_hash,
        spawnPoint = depot.spawnPoint,
        condition = cond
    }
end

-- 3. Store / Check in vehicle to commercial depot with damage serialization
function Nyx.Factions.StoreVehicle(src, factionId, vin, depotId, conditionData)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local vehRow = MySQL.single.await([[
        SELECT `vin`, `storage_state` FROM `nyx_factions_fleet`
        WHERE `vin` = ? AND `faction_id` = ?
    ]], { vin, factionId })

    if not vehRow then return false, "VEHICLE_NOT_FOUND" end

    local cond = conditionData or { engine = 1000.0, body = 1000.0, fuel = 100.0 }

    MySQL.prepare.await([[
        UPDATE `nyx_factions_fleet`
        SET `storage_state` = 'stored',
            `parking_depot_id` = ?,
            `condition_data` = ?
        WHERE `vin` = ?
    ]], {
        depotId,
        json.encode(cond),
        vin
    })

    return true, {
        vin = vin,
        storedAt = depotId,
        condition = cond
    }
end

-- 4. Query all commercial fleet vehicles owned by faction
function Nyx.Factions.GetFactionFleet(factionId)
    local rows = MySQL.query.await([[
        SELECT * FROM `nyx_factions_fleet`
        WHERE `faction_id` = ?
        ORDER BY `storage_state` ASC, `plate` ASC
    ]], { factionId })

    local fleet = {}
    for _, r in ipairs(rows or {}) do
        local cond = {}
        if type(r.condition_data) == "string" then
            local ok, parsed = pcall(json.decode, r.condition_data)
            if ok and type(parsed) == "table" then cond = parsed end
        elseif type(r.condition_data) == "table" then
            cond = r.condition_data
        end

        table.insert(fleet, {
            vin = r.vin,
            plate = r.plate,
            factionId = r.faction_id,
            modelHash = r.model_hash,
            depotId = r.parking_depot_id,
            storageState = r.storage_state,
            condition = cond
        })
    end

    return fleet
end
