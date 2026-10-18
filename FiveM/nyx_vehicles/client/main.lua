--[[
    Nyxframework: nyx_vehicles
    File: client/main.lua
    Description: Client lifecycle listeners and garage interaction bridge.
]]

RegisterNetEvent("nyx:vehicles:client:notify", function(data)
    TriggerEvent("nyx:ui:notify", data)
end)
