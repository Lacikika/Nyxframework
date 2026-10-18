--[[
    Nyxframework: nyx_treasury
    File: client/main.lua
    Description: Treasury client controller, transparency dashboard NUI bridge, and live ticker listeners.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}
Nyx.Treasury.IsOpen = false

-- Open Civic Transparency Dashboard
function Nyx.Treasury.OpenTerminal()
    if Nyx.Treasury.IsOpen then return end

    CreateThread(function()
        local ok, data = pcall(function()
            return exports['nyx_core']:TriggerRPCAwait("treasury:getPublicOverview")
        end)

        if not ok or not data then
            print("^1[Nyx:Treasury] Failed to fetch public treasury overview.^7")
            return
        end

        Nyx.Treasury.IsOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "OPEN_TREASURY_DASHBOARD",
            data = data
        })
    end)
end

-- Close Dashboard
function Nyx.Treasury.CloseTerminal()
    if not Nyx.Treasury.IsOpen then return end
    Nyx.Treasury.IsOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "CLOSE_TREASURY_DASHBOARD"
    })
end

-- Real-time Ledger Broadcast Listener
RegisterNetEvent("nyx:treasury:client:ledgerUpdate", function(txEntry)
    if Nyx.Treasury.IsOpen then
        SendNUIMessage({
            action = "TREASURY_TICKER_UPDATE",
            entry = txEntry
        })
    end
end)

-- NUI Callbacks
RegisterNUICallback("closeTerminal", function(_, cb)
    Nyx.Treasury.CloseTerminal()
    cb("ok")
end)

RegisterNUICallback("getLedgerPage", function(payload, cb)
    CreateThread(function()
        local page = payload and payload.page or 1
        local pageSize = payload and payload.pageSize or 20
        local category = payload and payload.category or nil

        local ok, res = pcall(function()
            return exports['nyx_core']:TriggerRPCAwait("treasury:getLedgerPage", page, pageSize, category)
        end)

        cb(ok and res or { entries = {}, totalEntries = 0 })
    end)
end)

RegisterNUICallback("getAllocations", function(_, cb)
    CreateThread(function()
        local ok, res = pcall(function()
            return exports['nyx_core']:TriggerRPCAwait("treasury:getAllocations")
        end)

        cb(ok and res or {})
    end)
end)
