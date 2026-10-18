--[[
    Nyxframework: nyx_logistics
    File: server/exports.lua
    Description: Clean public server exports for logistics queries, price calculations, and purchases.
]]

Nyx = Nyx or {}

exports("GetNode", function(nodeId)
    return Nyx.Logistics.ActiveNodes[nodeId]
end)

exports("GetShelf", function(shelfId)
    return Nyx.Logistics.Shelves[shelfId]
end)

exports("CalculatePrice", function(basePrice, targetCapacity, currentStock)
    return Nyx.Logistics.CalculateShelfPrice(basePrice, targetCapacity, currentStock)
end)

exports("TriggerRegeneration", function()
    Nyx.Logistics.ProcessRegenerationTick()
end)
