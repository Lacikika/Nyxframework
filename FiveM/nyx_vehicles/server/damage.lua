--[[
    Nyxframework: nyx_vehicles
    File: server/damage.lua
    Description: Engine, body, and tire damage serialization with oxmysql debounced write batches.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}
Nyx.Vehicles.DirtyDamage = {}

-- 1. Update vehicle condition in memory and queue debounced persistence
function Nyx.Vehicles.UpdateState(identifier, conditionData, fuelLevel, coords)
    local vin = (Nyx.Vehicles.ResolveVIN and Nyx.Vehicles.ResolveVIN(identifier)) or (Nyx.Vehicles.ByPlate[identifier] or identifier)
    local active = Nyx.Vehicles.Active[vin]
    if active then
        if conditionData then active.condition = conditionData end
        if fuelLevel then active.fuelLevel = tonumber(fuelLevel) or active.fuelLevel end
        if coords then active.lastCoords = coords end
    end

    Nyx.Vehicles.DirtyDamage[vin] = {
        condition = conditionData or (active and active.condition),
        fuel = fuelLevel or (active and active.fuelLevel),
        coords = coords or (active and active.lastCoords)
    }
end

-- 2. Flush dirty vehicle damage and fuel snapshots to MySQL
function Nyx.Vehicles.FlushDamageBatch()
    local dirty = Nyx.Vehicles.DirtyDamage
    Nyx.Vehicles.DirtyDamage = {}

    local count = 0
    for vin, data in pairs(dirty) do
        count = count + 1
        MySQL.prepare([[
            UPDATE `nyx_vehicles_owned`
            SET `condition_data` = ?,
                `fuel_level` = COALESCE(?, `fuel_level`),
                `last_coords` = COALESCE(?, `last_coords`)
            WHERE `vin` = ?
        ]], {
            data.condition and json.encode(data.condition) or "{}",
            data.fuel,
            data.coords and json.encode(data.coords) or nil,
            vin
        })
    end

    if count > 0 and Config.Debug then
        print(string.format("^2[Nyx:Vehicles]^7 Flushed damage & fuel snapshots for %d vehicles.^7", count))
    end
end

-- 3. Repair vehicle authoritatively
function Nyx.Vehicles.RepairVehicle(src, vin, fullRepair)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local invId = "citizen:" .. player.citizenId
    local removed, remErr = exports['nyx_inventory']:RemoveItem(invId, "tool_repairkit", 1)
    if not removed then
        return false, "NO_REPAIR_KIT"
    end

    local cleanCondition = {
        engine = 1000.0,
        body = 1000.0,
        dirt = 0.0,
        tires = { false, false, false, false },
        doors = {},
        windows = {}
    }

    local active = Nyx.Vehicles.Active[vin]
    if active then
        active.condition = cleanCondition
        if DoesEntityExist(active.entity) then
            SetVehicleEngineHealth(active.entity, 1000.0)
            SetVehicleBodyHealth(active.entity, 1000.0)
            SetVehicleFixed(active.entity)
            SetVehicleDirtLevel(active.entity, 0.0)
        end
        TriggerClientEvent("nyx:vehicles:client:repairVehicle", -1, active.netId)
    end

    MySQL.prepare.await([[
        UPDATE `nyx_vehicles_owned`
        SET `condition_data` = ?
        WHERE `vin` = ?
    ]], { json.encode(cleanCondition), vin })

    return true, { vin = vin, condition = cleanCondition }
end
