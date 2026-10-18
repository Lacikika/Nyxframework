--[[
    Nyxframework: nyx_logistics
    File: client/exports.lua
    Description: Clean public client exports for shelf interaction and logistics queries.
]]

Nyx = Nyx or {}

exports("BuyFromShelf", function(shelfId, quantity)
    return exports['nyx_core']:TriggerRPCAwait("logistics:buyFromShelf", shelfId, quantity)
end)

exports("GetShelfInfo", function(shelfId)
    return exports['nyx_core']:TriggerRPCAwait("logistics:getShelfInfo", shelfId)
end)
