--[[
    Nyxframework: nyx_inventory
    File: client/exports.lua
    Description: Clean public client exports for interface control and state checks.
]]

Nyx = Nyx or {}

exports("OpenInventory", function(targetInvId)
    Nyx.Inventory.Open(targetInvId)
end)

exports("CloseInventory", function()
    Nyx.Inventory.Close()
end)

exports("IsInventoryOpen", function()
    return Nyx.Inventory.IsOpen
end)

exports("GetPlayerWeight", function()
    return Nyx.Inventory.Weight or { current = 0, max = 30000, ratio = 0.0 }
end)
