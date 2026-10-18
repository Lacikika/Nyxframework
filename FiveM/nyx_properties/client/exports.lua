--[[
    Nyxframework: nyx_properties
    File: client/exports.lua
    Description: Public client exports for checking current interior and toggling locks.
]]

exports('GetCurrentPropertyId', function()
    return Nyx.Properties.CurrentPropertyId
end)

exports('EnterProperty', function(propertyId)
    Nyx.Properties.Enter(propertyId)
end)

exports('ExitProperty', function(propertyId)
    Nyx.Properties.Exit(propertyId)
end)

exports('ToggleLock', function(propertyId)
    Nyx.Properties.ToggleLock(propertyId)
end)
