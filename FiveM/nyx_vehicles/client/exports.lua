--[[
    Nyxframework: nyx_vehicles
    File: client/exports.lua
    Description: Clean client exports for vehicle properties, garages, and lock checks.
]]

exports("GetGarages", function()
    return Config.Garages or {}
end)

exports("GetStorageCapacity", function(vehicleClass)
    return Config.StorageByClass[vehicleClass] or Config.DefaultStorage
end)
