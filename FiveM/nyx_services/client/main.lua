--[[
    Nyxframework: nyx_services
    File: client/main.lua
    Description: Client event listeners and UI notifications for civil utilities and health services.
]]

-- Emergency Medical Care Notification
RegisterNetEvent("nyx:services:client:hospitalShortage", function(data)
    TriggerEvent("nyx:ui:notify", {
        type = "error",
        title = "MEDICAL FACILITY SHORTAGE",
        message = string.format("%s is facing critical supply depletion. Emergency logistics contracts issued.", data.hospitalLabel)
    })
end)
