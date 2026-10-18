--[[
    Nyxframework: nyx_logistics
    File: server/exports.lua
    Description: Clean public server exports for logistics queries, localized delivery zones,
                 elastic price calculations, physical freight pallets, and industrial facilities.
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

-- Physical Freight Pallets
exports("CreateFreightPallet", function(coords, heading, bucket, initialItems, citizenId, label)
    return Nyx.Logistics.CreateFreightPallet(coords, heading, bucket, initialItems, citizenId, label)
end)

exports("AttachPalletToVehicle", function(src, palletId, vehicleNetId, targetSlot)
    return Nyx.Logistics.AttachPalletToVehicle(src, palletId, vehicleNetId, targetSlot)
end)

exports("DetachPalletFromVehicle", function(src, palletId, targetCoords, heading)
    return Nyx.Logistics.DetachPalletFromVehicle(src, palletId, targetCoords, heading)
end)

exports("SealPallet", function(src, palletId)
    return Nyx.Logistics.SealPallet(src, palletId)
end)

exports("UnsealPallet", function(src, palletId)
    return Nyx.Logistics.UnsealPallet(src, palletId)
end)

exports("BreachPallet", function(src, palletId, toolItem)
    return Nyx.Logistics.BreachPallet(src, palletId, toolItem)
end)

exports("InspectPalletForensics", function(src, palletId)
    return Nyx.Logistics.InspectPalletForensics(src, palletId)
end)

exports("GetPalletForensics", function(palletId)
    local pallet = Nyx.Logistics.Pallets and Nyx.Logistics.Pallets[palletId]
    if not pallet then return nil end
    return {
        palletId = pallet.id,
        isSealed = pallet.is_sealed,
        isTampered = pallet.is_tampered,
        sealSerial = pallet.seal_serial,
        tamperTool = pallet.tamper_tool,
        breachedAt = pallet.breached_at,
        breachedBy = pallet.breached_by_citizen_id,
        evidenceMarkers = pallet.forensic_evidence_ids or {}
    }
end)

exports("GetPallet", function(palletId)
    return Nyx.Logistics.GetPallet(palletId)
end)

exports("GetAllPallets", function()
    return Nyx.Logistics.GetAllPallets()
end)

-- Power-Dependent Industrial Facilities
exports("IsFacilityPowered", function(facilityId)
    return Nyx.Logistics.IsFacilityPowered(facilityId)
end)

exports("GetFacility", function(facilityId)
    return Nyx.Logistics.Facilities and Nyx.Logistics.Facilities[facilityId]
end)

-- 3D Warehouse Matrix & Elastic Market Monitor
exports("GetWarehouseMatrixOverview", function(warehouseId)
    return Nyx.Logistics.GetWarehouseMatrixOverview and Nyx.Logistics.GetWarehouseMatrixOverview(warehouseId)
end)

exports("GetMarketMonitorOverview", function(zoneId)
    return Nyx.Logistics.GetMarketMonitorOverview and Nyx.Logistics.GetMarketMonitorOverview(zoneId)
end)

exports("GetHaulerArbitrageRoutes", function(src)
    return Nyx.Logistics.GetHaulerArbitrageRoutes and Nyx.Logistics.GetHaulerArbitrageRoutes(src)
end)

exports("BookHaulerDispatch", function(src, payload)
    return Nyx.Logistics.BookHaulerDispatch and Nyx.Logistics.BookHaulerDispatch(src, payload)
end)

-- Physical Retail Shelves & In-World Point of Sale Displays
exports("GetRetailShelf", function(shelfId)
    local s = Nyx.Logistics.RetailShelves and Nyx.Logistics.RetailShelves[shelfId]
    if not s then return nil end
    local stock = exports['nyx_inventory']:GetItemCount(s.inventory_id, s.item_id)
    return Nyx.RetailShelves.FormatShelfDisplay(s, stock, s.current_price)
end)

exports("GetRetailShelves", function()
    local list = {}
    if Nyx.Logistics.RetailShelves then
        for _, s in pairs(Nyx.Logistics.RetailShelves) do
            local stock = exports['nyx_inventory']:GetItemCount(s.inventory_id, s.item_id)
            list[#list + 1] = Nyx.RetailShelves.FormatShelfDisplay(s, stock, s.current_price)
        end
    end
    return list
end)

exports("RestockRetailShelf", function(src, shelfId, quantity)
    return Nyx.Logistics.RestockShelf and Nyx.Logistics.RestockShelf(src, shelfId, quantity)
end)

exports("GetShelfVisualState", function(shelfId)
    local s = Nyx.Logistics.RetailShelves and Nyx.Logistics.RetailShelves[shelfId]
    if not s then return nil end
    local stock = exports['nyx_inventory']:GetItemCount(s.inventory_id, s.item_id)
    local model = Nyx.RetailShelves.ResolveShelfPropModel(s, stock)
    local state = Nyx.RetailShelves.GetFullnessState(stock, s.target_capacity)
    return {
        shelfId = shelfId,
        stock = stock,
        activeModel = model,
        fullnessState = state
    }
end)

