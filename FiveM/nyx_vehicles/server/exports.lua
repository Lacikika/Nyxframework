--[[
    Nyxframework: nyx_vehicles
    File: server/exports.lua
    Description: Clean public server exports for vehicle lifecycle, storage, and access keys.
]]

Nyx = Nyx or {}

exports("SpawnVehicle", function(src, vin, coords, heading)
    return Nyx.Vehicles.SpawnVehicle(src, vin, coords, heading)
end)

exports("DespawnVehicle", function(src, vin, garageId)
    return Nyx.Vehicles.DespawnVehicle(src, vin, garageId)
end)

exports("HasKey", function(citizenId, vin, plate)
    return Nyx.Vehicles.HasKey(citizenId, vin, plate)
end)

exports("ToggleLock", function(src, vinOrNetId)
    return Nyx.Vehicles.ToggleLock(src, vinOrNetId)
end)

exports("RepairVehicle", function(src, vin, fullRepair)
    return Nyx.Vehicles.RepairVehicle(src, vin, fullRepair)
end)

exports("GetActiveVehicle", function(vinOrNetId)
    local vin = vinOrNetId
    if type(vinOrNetId) == "number" or tonumber(vinOrNetId) then
        vin = Nyx.Vehicles.ByNetId[tonumber(vinOrNetId)]
    end
    return vin and Nyx.Vehicles.Active[vin] or nil
end)

exports("GetPlayerVehicles", function(citizenId)
    return Nyx.Vehicles.GetPlayerVehicles(citizenId)
end)
