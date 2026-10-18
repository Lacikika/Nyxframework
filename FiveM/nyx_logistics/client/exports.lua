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

exports("SpawnPallet", function(coords, heading)
    return Nyx.Logistics.SpawnPallet and Nyx.Logistics.SpawnPallet(coords, heading)
end)

exports("AttachPalletToVehicle", function(palletObj, vehicle, boneIndex, offset)
    return Nyx.Logistics.AttachPalletToVehicle and Nyx.Logistics.AttachPalletToVehicle(palletObj, vehicle, boneIndex, offset)
end)

exports("DetachPallet", function(palletObj)
    return Nyx.Logistics.DetachPallet and Nyx.Logistics.DetachPallet(palletObj)
end)

exports("BreachPallet", function(palletId, toolItem)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    return exports['nyx_core']:TriggerRPCAwait("logistics:breachPallet", {
        palletId = palletId,
        toolItem = toolItem or "tool_crowbar",
        coords = { x = coords.x, y = coords.y, z = coords.z }
    })
end)

exports("InspectPalletForensics", function(palletId)
    return exports['nyx_core']:TriggerRPCAwait("logistics:inspectPalletForensics", palletId)
end)

exports("GetClosestRefiningFacility", function()
    return Nyx.Logistics.GetClosestRefiningFacility and Nyx.Logistics.GetClosestRefiningFacility()
end)

exports("GetNearbyRefiningFacilities", function(maxDist)
    return Nyx.Logistics.GetNearbyRefiningFacilities and Nyx.Logistics.GetNearbyRefiningFacilities(maxDist)
end)


