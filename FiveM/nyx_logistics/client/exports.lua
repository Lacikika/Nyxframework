--[[
    Nyxframework: nyx_logistics
    File: client/exports.lua
    Description: Clean public client exports for shelf interaction, delivery zones, and logistics queries.
]]

Nyx = Nyx or {}

exports("BuyFromShelf", function(shelfId, quantity)
    return exports['nyx_core']:TriggerRPCAwait("logistics:buyFromShelf", shelfId, quantity)
end)

exports("GetShelfInfo", function(shelfId)
    return exports['nyx_core']:TriggerRPCAwait("logistics:getShelfInfo", shelfId)
end)

exports("GetCurrentZone", function()
    return Nyx.Logistics.GetCurrentZone and Nyx.Logistics.GetCurrentZone() or "zone_ls_metro"
end)

exports("GetZoneForCoords", function(coords)
    return Nyx.Logistics.ResolveZoneFromCoords and Nyx.Logistics.ResolveZoneFromCoords(coords, Nyx.Logistics.DefaultZones)
end)
