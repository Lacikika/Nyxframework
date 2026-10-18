--[[
    Nyxframework: nyx_services
    File: server/main.lua
    Description: Core server initialization, background grid ticks, utility billing schedules,
                 and RPC registration.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}

local servicesLoaded = false
local function loadServicesData()
    if servicesLoaded then return end
    servicesLoaded = true
    -- 1. Load substations and hospitals from database
    Nyx.Services.LoadSubstations()
    Nyx.Services.LoadHospitals()
end

-- Staggered initialization listener (Stage 3: Civil Infrastructure)
AddEventHandler("nyx:core:init:nyx_services", function()
    loadServicesData()
end)

CreateThread(function()
    print("^4[Nyx:Services]^7 Initializing Civil Infrastructure & Public Utilities...^7")

    -- Register RPC routes
    if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
        -- Query substations
        exports['nyx_core']:RegisterRPC("services:getSubstations", function(src)
            return { success = true, substations = Nyx.Services.GetAllSubstations() }
        end)

        -- Refuel substation
        exports['nyx_core']:RegisterRPC("services:refuelSubstation", function(src, substationId)
            local ok, res = Nyx.Services.RefuelSubstation(src, substationId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Repair substation
        exports['nyx_core']:RegisterRPC("services:repairSubstation", function(src, substationId)
            local ok, res = Nyx.Services.RepairSubstation(src, substationId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Query hospitals
        exports['nyx_core']:RegisterRPC("services:getHospitals", function(src)
            return { success = true, hospitals = Nyx.Services.GetAllHospitals() }
        end)

        -- Process patient revival
        exports['nyx_core']:RegisterRPC("services:processRevival", function(src, hospitalId, requiresSurgery)
            local ok, res = Nyx.Services.ProcessRevival(src, hospitalId, requiresSurgery)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Restock hospital
        exports['nyx_core']:RegisterRPC("services:restockHospital", function(src, hospitalId, item, amount)
            local ok, res = Nyx.Services.RestockHospital(src, hospitalId, item, amount)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Pay utility arrears
        exports['nyx_core']:RegisterRPC("services:payUtilityBill", function(src, meterId, amount)
            local ok, res = Nyx.Services.PayUtilityBill(src, meterId, amount)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Query utility meter
        exports['nyx_core']:RegisterRPC("services:getMeter", function(src, meterId)
            local m = Nyx.Services.GetMeter(meterId)
            return { success = (m ~= nil), meter = m }
        end)

        -- Query substation diagnostics telemetry
        exports['nyx_core']:RegisterRPC("services:getDiagnostics", function(src, substationId)
            local diag = Nyx.Services.GetSubstationDiagnostics(substationId)
            return { success = (diag ~= nil), data = diag, error = (not diag and "SUBSTATION_NOT_FOUND" or nil) }
        end)

        -- Reset substation circuit breaker
        exports['nyx_core']:RegisterRPC("services:resetBreaker", function(src, substationId)
            local ok, res = Nyx.Services.ResetCircuitBreaker(src, substationId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Trigger substation failure simulation (admin only)
        exports['nyx_core']:RegisterRPC("services:triggerFailure", function(src, substationId, reason)
            local player = Nyx.GetPlayer(src)
            if not player or not player.hasPermission or not player.hasPermission("admin") then
                return { success = false, error = "UNAUTHORIZED" }
            end
            local ok, res = Nyx.Services.TriggerSubstationFailure(substationId, reason, player.citizenId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Restore substation grid power (admin only)
        exports['nyx_core']:RegisterRPC("services:restoreGrid", function(src, substationId)
            local player = Nyx.GetPlayer(src)
            if not player or not player.hasPermission or not player.hasPermission("admin") then
                return { success = false, error = "UNAUTHORIZED" }
            end
            local s = Nyx.Services.Substations[substationId]
            if not s then return { success = false, error = "SUBSTATION_NOT_FOUND" } end
            s.fuelLevel = 100.00
            s.conditionHealth = 100.00
            s.breakerTripped = false
            s.failureReason = nil
            evaluateSubstationState(s, false)
            return { success = true, substationId = substationId, isBlackout = s.isBlackout }
        end)
    end

    -- Await nyx_core database ready signal with fallback
    CreateThread(function()
        while not (exports['nyx_core'] and exports['nyx_core']:IsDatabaseReady()) do
            Wait(50)
        end
        Wait(350)
        if not servicesLoaded then
            loadServicesData()
        end
    end)

    -- 3. Power Grid Consumption Tick Loop (Every 60 seconds)
    CreateThread(function()
        while true do
            Wait(60000)
            Nyx.Services.PowerGridTick()
        end
    end)

    -- 4. Metered Utility Billing Cycle Loop (Every 30 minutes)
    CreateThread(function()
        while true do
            Wait(Config.Billing and (Config.Billing.BillingCycleInterval * 1000) or 1800000)
            Nyx.Services.ProcessUtilityBillingCycle()
        end
    end)

    print("^2[Nyx:Services]^7 Online and authoritative.^7")
end)

-- Sync active blackout zones to connecting client
RegisterNetEvent("nyx:services:server:requestGridSync", function()
    local src = source
    local blackouts = {}
    for id, s in pairs(Nyx.Services.Substations) do
        if s.isBlackout then
            table.insert(blackouts, {
                substationId = id,
                coords = { x = s.coords.x, y = s.coords.y, z = s.coords.z },
                radius = s.radius
            })
        end
    end
    TriggerClientEvent("nyx:services:client:initialGridSync", src, blackouts)
end)

-- Console / Chat Command: View Municipal Power Grid Status
RegisterCommand("gridstatus", function(source, args)
    local msg = "^5=== MUNICIPAL POWER GRID TELEMETRY ===^7\n"
    for id, s in pairs(Nyx.Services.Substations) do
        local stateStr = s.isBlackout and "^1[BLACKOUT]^7" or "^2[ONLINE]^7"
        local breakerStr = s.breakerTripped and "^1[TRIPPED]^7" or "^2[NORMAL]^7"
        msg = msg .. string.format("• %s (%s): %s | Fuel: %.1f%% | Condition: %.1f%% | Breaker: %s | Load: %.1f MW\n",
            s.label, id, stateStr, s.fuelLevel, s.conditionHealth, breakerStr, s.peakLoadMw or 45.0)
    end
    msg = msg .. "^5=======================================^7"

    if source == 0 then
        print(msg)
    else
        TriggerClientEvent("chat:addMessage", source, {
            color = { 70, 180, 255 },
            multiline = true,
            args = { "PowerGrid", msg }
        })
    end
end, false)

-- Admin / Console Command: Simulate Regional Substation Blackout / Failure
RegisterCommand("blackout", function(source, args)
    local subId = args[1]
    local reason = args[2] or "admin_simulation"

    if source ~= 0 then
        local player = Nyx.GetPlayer(source)
        if not player or not player.hasPermission or not player.hasPermission("admin") then
            TriggerClientEvent("nyx:ui:notify", source, { type = "error", title = "UNAUTHORIZED", message = "Permission denied." })
            return
        end
    end

    if not subId then
        print("^3Usage: /blackout <substationId> [reason]^7")
        return
    end

    local ok, res = Nyx.Services.TriggerSubstationFailure(subId, reason, source == 0 and "SERVER_CONSOLE" or "ADMIN")
    if ok then
        print(string.format("^1[Nyx:Services] Blackout triggered on substation '%s' (Reason: %s)^7", subId, reason))
    else
        print(string.format("^1[Nyx:Services] Failed to trigger blackout: %s^7", tostring(res)))
    end
end, true)

-- Admin / Console Command: Restore Grid Power
RegisterCommand("restoregrid", function(source, args)
    local subId = args[1]

    if source ~= 0 then
        local player = Nyx.GetPlayer(source)
        if not player or not player.hasPermission or not player.hasPermission("admin") then
            TriggerClientEvent("nyx:ui:notify", source, { type = "error", title = "UNAUTHORIZED", message = "Permission denied." })
            return
        end
    end

    if not subId or subId == "all" then
        for id, s in pairs(Nyx.Services.Substations) do
            s.fuelLevel = 100.00
            s.conditionHealth = 100.00
            s.breakerTripped = false
            s.failureReason = nil
            evaluateSubstationState(s, false)
        end
        print("^2[Nyx:Services] Full municipal power grid energized and restored to 100% across all sectors!^7")
    else
        local s = Nyx.Services.Substations[subId]
        if s then
            s.fuelLevel = 100.00
            s.conditionHealth = 100.00
            s.breakerTripped = false
            s.failureReason = nil
            evaluateSubstationState(s, false)
            print(string.format("^2[Nyx:Services] Substation '%s' restored to 100%% capacity!^7", subId))
        else
            print(string.format("^1[Nyx:Services] Substation '%s' not found!^7", tostring(subId)))
        end
    end
end, true)

-- Admin / Maintenance Command: Reset Tripped Circuit Breaker
RegisterCommand("resetbreaker", function(source, args)
    local subId = args[1]
    if not subId then
        print("^3Usage: /resetbreaker <substationId>^7")
        return
    end

    if source == 0 then
        local s = Nyx.Services.Substations[subId]
        if s then
            s.breakerTripped = false
            s.failureReason = nil
            evaluateSubstationState(s, false)
            print(string.format("^2[Nyx:Services] Circuit breaker manually reset on '%s'^7", subId))
        else
            print("^1[Nyx:Services] Substation not found.^7")
        end
    else
        local ok, res = Nyx.Services.ResetCircuitBreaker(source, subId)
        if ok then
            TriggerClientEvent("nyx:ui:notify", source, {
                type = "success",
                title = "BREAKER RESET",
                message = "Substation circuit breaker successfully closed and energized."
            })
        else
            TriggerClientEvent("nyx:ui:notify", source, {
                type = "error",
                title = "BREAKER RESET FAILED",
                message = string.format("Cannot reset breaker: %s", tostring(res))
            })
        end
    end
end, false)
