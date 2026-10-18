--[[
    Nyxframework: nyx_logistics
    File: server/exports.lua
    Description: Clean public server exports for logistics queries, localized delivery zones,
                 elastic price calculations, and regional market indices.
]]

Nyx = Nyx or {}

exports("GetNode", function(nodeId)
    return Nyx.Logistics.ActiveNodes and Nyx.Logistics.ActiveNodes[nodeId]
end)

exports("GetShelf", function(shelfId)
    return Nyx.Logistics.Shelves and Nyx.Logistics.Shelves[shelfId]
end)

exports("CalculatePrice", function(basePrice, targetCapacity, currentStock, zoneId, itemId)
    return Nyx.Logistics.CalculateShelfPrice(basePrice, targetCapacity, currentStock, zoneId, itemId)
end)

exports("CalculateElasticPrice", function(basePrice, targetCapacity, currentStock, zoneId, itemId)
    return Nyx.Logistics.CalculateShelfPrice(basePrice, targetCapacity, currentStock, zoneId, itemId)
end)

exports("GetZone", function(zoneId)
    return Nyx.Logistics.GetZone and Nyx.Logistics.GetZone(zoneId)
end)

exports("GetZoneForCoords", function(coords)
    return Nyx.Logistics.ResolveZoneFromCoords and Nyx.Logistics.ResolveZoneFromCoords(coords, Nyx.Logistics.Zones)
end)

exports("GetZoneDemand", function(zoneId)
    return Nyx.Logistics.GetZoneMarketIndex and Nyx.Logistics.GetZoneMarketIndex(zoneId)
end)

exports("GetZoneMarketIndex", function(zoneId)
    return Nyx.Logistics.GetZoneMarketIndex and Nyx.Logistics.GetZoneMarketIndex(zoneId)
end)

exports("GetEffectiveDemand", function(targetCapacity, zoneId)
    if Nyx.Logistics.GetEffectiveDemand then
        return Nyx.Logistics.GetEffectiveDemand(targetCapacity, zoneId)
    end
    return targetCapacity
end)

exports("GetStockToDemandRatio", function(currentStock, effectiveDemand)
    if Nyx.Logistics.GetStockToDemandRatio then
        return Nyx.Logistics.GetStockToDemandRatio(currentStock, effectiveDemand)
    end
    effectiveDemand = math.max(1, effectiveDemand or 1)
    return (currentStock or 0) / effectiveDemand
end)

exports("TriggerRegeneration", function()
    if Nyx.Logistics.ProcessRegenerationTick then
        Nyx.Logistics.ProcessRegenerationTick()
    end
end)
