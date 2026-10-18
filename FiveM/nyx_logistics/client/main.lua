--[[
    Nyxframework: nyx_logistics
    File: client/main.lua
    Description: Client logistics controller, shelf sync events, and NUI bridge.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}

-- Real-time Shelf Price & Stock Update Listener
RegisterNetEvent("nyx:logistics:client:shelfUpdated", function(shelfId, newPrice, newStock, zoneId, stockToDemandRatio)
    if Config.Debug then
        print(string.format("^4[Nyx:Logistics:Client] Shelf '%s' [%s] recalibrated: $%.2f (Stock: %d, S/D Ratio: %s)^7",
            shelfId, zoneId or "metro", newPrice, newStock, tostring(stockToDemandRatio or "1.0")))
    end

    SendNUIMessage({
        action = "SHELF_UPDATED",
        shelfId = shelfId,
        price = newPrice,
        stock = newStock,
        zoneId = zoneId,
        stockToDemandRatio = stockToDemandRatio
    })
end)

-- Shortage Freight Contract Available Notification
RegisterNetEvent("nyx:logistics:client:newContractAvailable", function(payload)
    local title = type(payload) == "table" and payload.title or "Sürgősségi Fuvarozás"
    local totalPayout = type(payload) == "table" and payload.totalPayout or 0.00
    local qty = type(payload) == "table" and payload.quantity or 0

    TriggerEvent("nyx:core:client:notify",
        string.format("%s: %dx rakomány ($%.2f összdíj)", title, qty, totalPayout),
        "info"
    )
end)

-- NUI Handlers
RegisterNUICallback("buyFromShelf", function(payload, cb)
    CreateThread(function()
        local shelfId = payload and payload.shelfId
        local quantity = payload and payload.quantity or 1

        local result = exports['nyx_core']:TriggerRPCAwait("logistics:buyFromShelf", shelfId, quantity)
        cb(result or { success = false, error = "NETWORK_ERROR" })
    end)
end)
