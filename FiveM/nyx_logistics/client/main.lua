--[[
    Nyxframework: nyx_logistics
    File: client/main.lua
    Description: Client logistics controller, shelf sync events, and NUI bridge.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}

-- Real-time Shelf Price & Stock Update Listener
RegisterNetEvent("nyx:logistics:client:shelfUpdated", function(shelfId, newPrice, newStock)
    if Config.Debug then
        print(string.format("^4[Nyx:Logistics:Client] Shelf '%s' recalibrated: $%.2f (Stock: %d)^7", shelfId, newPrice, newStock))
    end

    SendNUIMessage({
        action = "SHELF_UPDATED",
        shelfId = shelfId,
        price = newPrice,
        stock = newStock
    })
end)

-- Shortage Freight Contract Available Notification
RegisterNetEvent("nyx:logistics:client:newContractAvailable", function(shelfId, quantity, payoutPerUnit)
    TriggerEvent("nyx:core:client:notify",
        string.format("New Hauling Contract Available! Stock: %dx items ($%.2f/unit payout)", quantity, payoutPerUnit),
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
