--[[
    Nyxframework: nyx_treasury
    File: client/main.lua
    Description: Treasury client controller, transparency dashboard NUI bridge,
                 live ticker listeners, and statutory revenue sweep event handlers.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}
Nyx.Treasury.IsOpen = false

-- Open Civic Transparency Dashboard
function Nyx.Treasury.OpenTerminal(options)
    if Nyx.Treasury.IsOpen then return end

    options = options or {}

    CreateThread(function()
        local ok, data = pcall(function()
            return exports['nyx_core']:TriggerRPCAwait("treasury:getPublicOverview")
        end)

        if not ok or not data then
            print("^1[Nyx:Treasury] Failed to fetch public treasury overview.^7")
            return
        end

        Nyx.Treasury.IsOpen = true

        -- Forward through master nyx_ui single-frame CEF SPA if available
        if exports['nyx_ui'] and exports['nyx_ui'].OpenTreasuryDashboard then
            exports['nyx_ui']:OpenTreasuryDashboard(data)
            return
        end

        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "TREASURY_DASHBOARD_OPEN",
            payload = data,
            data = data
        })
    end)
end

-- Close Dashboard
function Nyx.Treasury.CloseTerminal()
    if not Nyx.Treasury.IsOpen then return end
    Nyx.Treasury.IsOpen = false

    if exports['nyx_ui'] and exports['nyx_ui'].CloseTreasuryDashboard then
        exports['nyx_ui']:CloseTreasuryDashboard()
        return
    end

    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "TREASURY_DASHBOARD_CLOSE"
    })
end

-- Real-time Ledger Broadcast Listener
RegisterNetEvent("nyx:treasury:client:ledgerUpdate", function(txEntry)
    if Nyx.Treasury.IsOpen then
        SendNUIMessage({
            action = "TREASURY_TICKER_UPDATE",
            entry = txEntry,
            payload = txEntry
        })
    end
end)

-- Real-time Automated Statutory Revenue Sweep Listener
RegisterNetEvent("nyx:treasury:client:sweepExecuted", function(sweepData)
    if Nyx.Treasury.IsOpen then
        SendNUIMessage({
            action = "TREASURY_SWEEP_UPDATE",
            sweep = sweepData,
            payload = sweepData
        })
    end
end)

-- Citizen Commands for Public Financial Transparency
RegisterCommand("treasury", function()
    Nyx.Treasury.OpenTerminal()
end, false)

RegisterCommand("cityledger", function()
    Nyx.Treasury.OpenTerminal()
end, false)

-- NUI Callbacks
RegisterNUICallback("closeTerminal", function(_, cb)
    Nyx.Treasury.CloseTerminal()
    cb("ok")
end)

RegisterNUICallback("closeTreasury", function(_, cb)
    Nyx.Treasury.CloseTerminal()
    cb("ok")
end)

RegisterNUICallback("getLedgerPage", function(payload, cb)
    CreateThread(function()
        local ok, res = pcall(function()
            return exports['nyx_core']:TriggerRPCAwait("treasury:getLedgerPage", payload)
        end)
        cb(ok and res or { success = false, entries = {}, totalEntries = 0, totalPages = 1 })
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

RegisterNUICallback("getBalanceSheet", function(_, cb)
    CreateThread(function()
        local ok, res = pcall(function()
            return exports['nyx_core']:TriggerRPCAwait("treasury:getBalanceSheet")
        end)
        cb(ok and res or { success = false })
    end)
end)

RegisterNUICallback("getRevenueSweeps", function(payload, cb)
    CreateThread(function()
        local limit = payload and payload.limit or 15
        local ok, res = pcall(function()
            return exports['nyx_core']:TriggerRPCAwait("treasury:getRevenueSweeps", limit)
        end)
        cb(ok and res or { success = false, sweeps = {} })
    end)
end)
