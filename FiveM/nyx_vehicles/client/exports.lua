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

exports("ToggleVehicleLock", function()
    ExecuteCommand("nyx_toggle_vehicle_lock")
end)

exports("LockpickVehicle", function(useGloves)
    ExecuteCommand("lockpickvehicle " .. (useGloves and "gloves" or ""))
end)

exports("HotwireVehicle", function(useGloves)
    ExecuteCommand("hotwire " .. (useGloves and "gloves" or ""))
end)

