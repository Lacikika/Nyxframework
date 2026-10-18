--[[
    Nyxframework: nyx_vehicles
    File: server/spawner.lua
    Description: Authoritative vehicle spawning, netId assignment, routing bucket management,
                 and despawn state persistence.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}
Nyx.Vehicles.Active = {}    -- [vin] = { entity, netId, vin, plate, modelHash, modelName, owner, faction, fuel, condition, lockState }
Nyx.Vehicles.ByEntity = {}  -- [entity] = vin
Nyx.Vehicles.ByNetId = {}   -- [netId] = vin
Nyx.Vehicles.ByPlate = {}   -- [plate] = vin

-- Utility: Generate 17-character VIN
function Nyx.Vehicles.GenerateVIN()
    local chars = "0123456789ABCDEFGHJKLMNPRSTUVWXYZ"
    local res = { "1", "N", "Y", "X" }
    for i = 5, 17 do
        local r = math.random(1, #chars)
        res[i] = chars:sub(r, r)
    end
    return table.concat(res)
end

-- Utility: Generate formatted license plate
function Nyx.Vehicles.GeneratePlate(prefix)
    local num = math.random(100, 999)
    local p = prefix and string.upper(prefix:sub(1, 4)) or "NYX"
    return string.format("%s %d", p, num)
end

-- 1. Spawn vehicle authoritatively on server
function Nyx.Vehicles.SpawnVehicle(src, vin, targetCoords, targetHeading)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local row = MySQL.single.await([[
        SELECT * FROM `nyx_vehicles_owned` WHERE `vin` = ?
    ]], { vin })

    if not row then return false, "VEHICLE_NOT_FOUND" end

    if row.storage_state == "out" and Nyx.Vehicles.Active[vin] then
        return false, "VEHICLE_ALREADY_SPAWNED"
    end

    if row.storage_state == "impounded" then
        return false, "VEHICLE_IMPOUNDED"
    end

    if row.storage_state == "destroyed" then
        return false, "VEHICLE_TOTALED"
    end

    -- Authorization check
    local hasAccess = Nyx.Vehicles.HasKey(player.citizenId, row.vin, row.plate)
    if not hasAccess and row.owner_citizen_id ~= player.citizenId then
        return false, "ACCESS_DENIED_NO_KEY"
    end

    -- Determine spawn point
    local spawnCoords = targetCoords
    local spawnHeading = targetHeading or 0.0
    if not spawnCoords then
        local garage = Config.Garages[row.garage_id] or Config.Garages['legion_square']
        if garage and garage.spawnPoint then
            spawnCoords = vector3(garage.spawnPoint.x, garage.spawnPoint.y, garage.spawnPoint.z)
            spawnHeading = garage.spawnPoint.w or 0.0
        else
            spawnCoords = vector3(215.5, -805.0, 30.8)
        end
    end

    -- Create vehicle server entity
    local modelHash = tonumber(row.model_hash)
    local vehEntity = CreateVehicle(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnHeading, true, true)

    local timeout = 50
    while not DoesEntityExist(vehEntity) and timeout > 0 do
        Wait(50)
        timeout = timeout - 1
    end

    if not DoesEntityExist(vehEntity) then
        return false, "SERVER_ENTITY_CREATION_FAILED"
    end

    -- Configure authoritative vehicle properties
    SetVehicleNumberPlateText(vehEntity, row.plate)
    local playerBucket = GetPlayerRoutingBucket(tostring(src))
    SetEntityRoutingBucket(vehEntity, playerBucket)

    local lockState = tonumber(row.lock_state) or 1
    SetVehicleDoorsLocked(vehEntity, (lockState == 1 and 2 or 1))

    local netId = NetworkGetNetworkIdFromEntity(vehEntity)

    local condition = {
        engine = 1000.0,
        body = 1000.0,
        dirt = 0.0,
        tires = { false, false, false, false },
        doors = {},
        windows = {}
    }
    if type(row.condition_data) == "string" then
        local ok, parsed = pcall(json.decode, row.condition_data)
        if ok and type(parsed) == "table" then condition = parsed end
    elseif type(row.condition_data) == "table" then
        condition = row.condition_data
    end

    -- Bind trunk and glovebox containers into nyx_inventory
    local trunkId = "trunk:" .. row.plate
    local gloveboxId = "glovebox:" .. row.plate
    local classStorage = Config.DefaultStorage

    if exports['nyx_inventory'] and exports['nyx_inventory'].GetInventory then
        exports['nyx_inventory']:GetInventory(trunkId, 'trunk')
        exports['nyx_inventory']:GetInventory(gloveboxId, 'glovebox')
    end

    -- Update memory tracking
    local activeData = {
        entity = vehEntity,
        netId = netId,
        vin = row.vin,
        plate = row.plate,
        modelHash = modelHash,
        modelName = row.model_name,
        ownerCitizenId = row.owner_citizen_id,
        factionId = row.faction_id,
        fuelLevel = tonumber(row.fuel_level) or 65.0,
        condition = condition,
        lockState = lockState,
        routingBucket = playerBucket
    }

    Nyx.Vehicles.Active[row.vin] = activeData
    Nyx.Vehicles.ByEntity[vehEntity] = row.vin
    Nyx.Vehicles.ByNetId[netId] = row.vin
    Nyx.Vehicles.ByPlate[row.plate] = row.vin

    -- Mark storage state as out
    MySQL.prepare.await([[
        UPDATE `nyx_vehicles_owned`
        SET `storage_state` = 'out'
        WHERE `vin` = ?
    ]], { row.vin })

    -- Synchronize physical condition to spawner client
    TriggerClientEvent("nyx:vehicles:client:applyVehicleState", src, {
        netId = netId,
        condition = condition,
        fuelLevel = activeData.fuelLevel,
        plate = row.plate,
        lockState = lockState
    })

    if Config.Debug then
        print(string.format("^2[Nyx:Vehicles]^7 Spawned %s [%s] (NetID: %d, VIN: %s)^7",
            row.model_name, row.plate, netId, row.vin))
    end

    return true, activeData
end

-- 2. Despawn vehicle authoritatively and save final state
function Nyx.Vehicles.DespawnVehicle(src, vin, garageId)
    local active = Nyx.Vehicles.Active[vin]
    if not active then
        return false, "VEHICLE_NOT_ACTIVE"
    end

    local finalCoords = nil
    if DoesEntityExist(active.entity) then
        local c = GetEntityCoords(active.entity)
        local h = GetEntityHeading(active.entity)
        finalCoords = { x = c.x, y = c.y, z = c.z, heading = h }
        DeleteEntity(active.entity)
    end

    local assignedGarage = garageId or "legion_square"

    MySQL.prepare.await([[
        UPDATE `nyx_vehicles_owned`
        SET `storage_state` = 'stored',
            `garage_id` = ?,
            `fuel_level` = ?,
            `lock_state` = ?,
            `last_coords` = ?,
            `condition_data` = ?
        WHERE `vin` = ?
    ]], {
        assignedGarage,
        active.fuelLevel,
        active.lockState,
        finalCoords and json.encode(finalCoords) or nil,
        json.encode(active.condition),
        vin
    })

    -- Clean up memory lookup tables
    if active.entity then Nyx.Vehicles.ByEntity[active.entity] = nil end
    if active.netId then Nyx.Vehicles.ByNetId[active.netId] = nil end
    if active.plate then Nyx.Vehicles.ByPlate[active.plate] = nil end
    Nyx.Vehicles.Active[vin] = nil

    return true, { vin = vin, garage = assignedGarage }
end

-- 3. Query all vehicles owned by a citizen
function Nyx.Vehicles.GetPlayerVehicles(citizenId)
    local rows = MySQL.query.await([[
        SELECT `vin`, `plate`, `model_name`, `model_hash`, `garage_id`, `storage_state`,
               `fuel_level`, `lock_state`, `condition_data`, `created_at`
        FROM `nyx_vehicles_owned`
        WHERE `owner_citizen_id` = ?
        ORDER BY `created_at` DESC
    ]], { citizenId })

    return rows or {}
end
