--[[
    Nyxframework: nyx_treasury
    File: server/circuit.lua
    Description: Server-side fiscal circuit breaker engine, rolling outflow velocity
                 tracker, state bag synchronizer, and crisis state machine.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}

Nyx.Treasury.Circuit = {
    tripped = false,
    trippedAt = 0,
    tripReason = nil,
    state = "SOLVENT",
    rollingOutflows = {},
    lastAutoResetAttempt = 0
}

-- Check if fiscal circuit breaker is currently active
function Nyx.Treasury.IsCircuitTripped()
    return Nyx.Treasury.Circuit.tripped == true
end

-- Retrieve current fiscal crisis state
function Nyx.Treasury.GetFiscalState()
    return Nyx.Treasury.Circuit.state or "SOLVENT"
end

-- Calculate current drain velocity from rolling window
function Nyx.Treasury.GetDrainVelocity()
    local windowSec = (Config.Circuit and Config.Circuit.RollingWindowSeconds) or 600
    local now = os.time()
    return Nyx.Circuit.CalculateDrainVelocity(Nyx.Treasury.Circuit.rollingOutflows, windowSec, now)
end

-- Retrieve comprehensive circuit telemetry
function Nyx.Treasury.GetCircuitTelemetry()
    local masterReserve = Nyx.Treasury.GetBalance(Config.Accounts.Master or "gov:city:master")
    local velocity = Nyx.Treasury.GetDrainVelocity()
    local wageMult, wageStatus = Nyx.Treasury.GetWageMultiplier()

    return {
        tripped = Nyx.Treasury.Circuit.tripped,
        trippedAt = Nyx.Treasury.Circuit.trippedAt,
        tripReason = Nyx.Treasury.Circuit.tripReason,
        fiscalState = Nyx.Treasury.Circuit.state,
        masterReserve = masterReserve,
        targetReserve = Config.TargetReserve or 5000000.00,
        cautionReserve = Config.CautionReserve or 2500000.00,
        recoveryReserve = Config.RecoveryReserve or 1000000.00,
        criticalReserve = Config.CriticalReserve or 500000.00,
        drainVelocity = velocity,
        maxRollingOutflow = (Config.Circuit and Config.Circuit.MaxRollingOutflow) or 750000.00,
        maxSingleTransaction = (Config.Circuit and Config.Circuit.MaxSingleTransaction) or 500000.00,
        wageMultiplier = wageMult,
        wageStatus = wageStatus,
        municipalDegraded = (Nyx.Treasury.Circuit.state == "CRITICAL_DEFICIT" or Nyx.Treasury.Circuit.tripped)
    }
end

-- Synchronize fiscal state to server-authoritative replicated OneSync State Bags
local function syncFiscalStateBags()
    local state = Nyx.Treasury.Circuit.state
    local isDegraded = (state == "CRITICAL_DEFICIT" or Nyx.Treasury.Circuit.tripped)
    local wageMult, wageStatus = Nyx.Treasury.GetWageMultiplier()

    GlobalState.fiscalState = state
    GlobalState.municipalDegraded = isDegraded
    GlobalState.fiscalCircuitBreaker = {
        tripped = Nyx.Treasury.Circuit.tripped,
        trippedAt = Nyx.Treasury.Circuit.trippedAt,
        reason = Nyx.Treasury.Circuit.tripReason,
        state = state,
        wageMultiplier = wageMult,
        wageStatus = wageStatus,
        updatedAt = os.time()
    }
end

-- Trip the fiscal circuit breaker
function Nyx.Treasury.TripCircuitBreaker(reason, authorizedBy, metadata)
    reason = tostring(reason or "UNSPECIFIED_CRISIS")
    authorizedBy = tostring(authorizedBy or "SYSTEM")

    local previousState = Nyx.Treasury.Circuit.state
    Nyx.Treasury.Circuit.tripped = true
    Nyx.Treasury.Circuit.trippedAt = os.time()
    Nyx.Treasury.Circuit.tripReason = reason
    Nyx.Treasury.Circuit.state = "CIRCUIT_TRIPPED"

    local masterReserve = Nyx.Treasury.GetBalance(Config.Accounts.Master or "gov:city:master")
    local velocity = Nyx.Treasury.GetDrainVelocity()

    print(string.format("^1[Nyx:Treasury:CIRCUIT] *** FISCAL CIRCUIT BREAKER TRIPPED *** Reason: %s | Master Reserve: $%.2f | Outflow: $%.2f^7",
        reason, masterReserve, velocity.totalOutflow))

    -- Persist circuit audit log
    pcall(function()
        MySQL.prepare.await([[
            INSERT INTO `nyx_treasury_circuit_logs`
            (`event_type`, `previous_state`, `new_state`, `trigger_reason`, `master_reserve`, `drain_velocity`, `authorized_by`)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], {
            "CIRCUIT_TRIPPED",
            previousState,
            "CIRCUIT_TRIPPED",
            reason,
            masterReserve,
            velocity.velocityPerHour,
            authorizedBy
        })
    end)

    syncFiscalStateBags()

    -- Server event notification
    TriggerEvent("nyx:treasury:circuitTripped", reason, masterReserve, velocity)

    -- Broadcast to clients
    TriggerClientEvent("nyx:core:client:notify", -1,
        string.format("MUNICIPAL ALERT: Fiscal circuit breaker tripped (%s)! Discretionary spending frozen.", reason),
        "error"
    )

    return true
end

-- Reset the fiscal circuit breaker (manual or automatic)
function Nyx.Treasury.ResetCircuitBreaker(authorizedBy, reason)
    if not Nyx.Treasury.Circuit.tripped then
        return false, "CIRCUIT_NOT_TRIPPED"
    end

    authorizedBy = tostring(authorizedBy or "SYSTEM")
    reason = tostring(reason or "MANUAL_OVERRIDE")

    local previousState = Nyx.Treasury.Circuit.state
    Nyx.Treasury.Circuit.tripped = false
    Nyx.Treasury.Circuit.trippedAt = 0
    Nyx.Treasury.Circuit.tripReason = nil

    local masterReserve = Nyx.Treasury.GetBalance(Config.Accounts.Master or "gov:city:master")
    local targetReserve = tonumber(Config.TargetReserve) or 5000000.00
    local critReserve = tonumber(Config.CriticalReserve) or 500000.00
    local cautionReserve = tonumber(Config.CautionReserve) or (targetReserve * 0.50)

    local newState = Nyx.Circuit.DetermineFiscalState(masterReserve, targetReserve, critReserve, cautionReserve, false)
    Nyx.Treasury.Circuit.state = newState

    local velocity = Nyx.Treasury.GetDrainVelocity()

    print(string.format("^2[Nyx:Treasury:CIRCUIT] Fiscal circuit breaker RESET by %s. New State: %s | Reserve: $%.2f^7",
        authorizedBy, newState, masterReserve))

    -- Persist reset audit log
    pcall(function()
        MySQL.prepare.await([[
            INSERT INTO `nyx_treasury_circuit_logs`
            (`event_type`, `previous_state`, `new_state`, `trigger_reason`, `master_reserve`, `drain_velocity`, `authorized_by`)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], {
            "CIRCUIT_RESET",
            previousState,
            newState,
            reason,
            masterReserve,
            velocity.velocityPerHour,
            authorizedBy
        })
    end)

    syncFiscalStateBags()

    -- Server event notification
    TriggerEvent("nyx:treasury:circuitReset", newState, masterReserve, authorizedBy)

    -- Broadcast to clients
    TriggerClientEvent("nyx:core:client:notify", -1,
        string.format("MUNICIPAL NOTICE: Fiscal circuit breaker reset. City finances restored to '%s'.", newState),
        "info"
    )

    return true, newState
end

-- Record an outgoing municipal transaction in the rolling window
function Nyx.Treasury.RecordMunicipalOutflow(debitAccount, creditAccount, amount, category, authorizedBy)
    amount = tonumber(amount) or 0.00
    if amount <= 0.00 then return end

    local now = os.time()
    local outflows = Nyx.Treasury.Circuit.rollingOutflows

    outflows[#outflows + 1] = {
        amount = amount,
        timestamp = now,
        debitAccount = debitAccount,
        creditAccount = creditAccount,
        category = category,
        authorizedBy = authorizedBy
    }

    -- Evaluate whether rolling outflow triggers circuit trip
    local windowSec = (Config.Circuit and Config.Circuit.RollingWindowSeconds) or 600
    local velocity = Nyx.Circuit.CalculateDrainVelocity(outflows, windowSec, now)
    Nyx.Treasury.Circuit.rollingOutflows = velocity.activeOutflows

    local masterReserve = Nyx.Treasury.GetBalance(Config.Accounts.Master or "gov:city:master")
    local critReserve = tonumber(Config.CriticalReserve) or 500000.00
    local maxRolling = (Config.Circuit and Config.Circuit.MaxRollingOutflow) or 750000.00
    local maxSingle = (Config.Circuit and Config.Circuit.MaxSingleTransaction) or 500000.00

    if not Nyx.Treasury.Circuit.tripped then
        local shouldTrip, tripReason = Nyx.Circuit.EvaluateCircuitTrip({
            currentReserve = masterReserve,
            criticalReserve = critReserve,
            rollingOutflow = velocity.totalOutflow,
            maxRollingOutflow = maxRolling,
            singleTxAmount = amount,
            maxSingleTransaction = maxSingle,
            isCurrentlyTripped = false
        })

        if shouldTrip then
            Nyx.Treasury.TripCircuitBreaker(tripReason, authorizedBy or "OUTFLOW_MONITOR")
        end
    end
end

-- Periodic background evaluation and health sweeper
function Nyx.Treasury.EvaluateFiscalHealth()
    local now = os.time()
    local windowSec = (Config.Circuit and Config.Circuit.RollingWindowSeconds) or 600
    local velocity = Nyx.Circuit.CalculateDrainVelocity(Nyx.Treasury.Circuit.rollingOutflows, windowSec, now)
    Nyx.Treasury.Circuit.rollingOutflows = velocity.activeOutflows

    local masterReserve = Nyx.Treasury.GetBalance(Config.Accounts.Master or "gov:city:master")
    local targetReserve = tonumber(Config.TargetReserve) or 5000000.00
    local critReserve = tonumber(Config.CriticalReserve) or 500000.00
    local cautionReserve = tonumber(Config.CautionReserve) or (targetReserve * 0.50)
    local recoveryReserve = tonumber(Config.RecoveryReserve) or 1000000.00
    local maxRolling = (Config.Circuit and Config.Circuit.MaxRollingOutflow) or 750000.00

    if Nyx.Treasury.Circuit.tripped then
        -- Check automated recovery eligibility
        local canReset, resetReason = Nyx.Circuit.CanAutoResetCircuit({
            currentReserve = masterReserve,
            recoveryReserve = recoveryReserve,
            rollingOutflow = velocity.totalOutflow,
            maxRollingOutflow = maxRolling,
            hysteresisMargin = (Config.Circuit and Config.Circuit.HysteresisRecoveryMargin) or 0.75,
            trippedAt = Nyx.Treasury.Circuit.trippedAt,
            cooldownSeconds = (Config.Circuit and Config.Circuit.AutoResetCooldown) or 300,
            now = now
        })

        if canReset then
            Nyx.Treasury.ResetCircuitBreaker("SYSTEM_AUTO_RECOVERY", "Solvency recovered and drain velocity stabilized")
        end
    else
        -- Check if critical reserve depletion occurred outside direct transfers
        if masterReserve <= critReserve then
            Nyx.Treasury.TripCircuitBreaker("CRITICAL_RESERVE_DEPLETED", "SYSTEM_HEALTH_CHECK")
        else
            local previousState = Nyx.Treasury.Circuit.state
            local newState = Nyx.Circuit.DetermineFiscalState(masterReserve, targetReserve, critReserve, cautionReserve, false)
            if previousState ~= newState then
                Nyx.Treasury.Circuit.state = newState
                print(string.format("^3[Nyx:Treasury:STATE] Fiscal state shifted: %s -> %s (Reserve: $%.2f)^7",
                    previousState, newState, masterReserve))
            end
        end
    end

    syncFiscalStateBags()
end

-- Administrative Console / Chat Commands
RegisterCommand("fiscalstatus", function(src, args)
    local telemetry = Nyx.Treasury.GetCircuitTelemetry()
    local msg = string.format([[
^5=== NYXFRAMEWORK MUNICIPAL FISCAL STATUS ===^7
Fiscal State:        ^3%s^7
Circuit Tripped:     %s
Trip Reason:         ^1%s^7
Master Reserve:      ^2$%.2f^7 (Target: $%.2f | Critical: $%.2f)
10m Drain Velocity:  ^3$%.2f^7 / hr ($%.2f in window, %d TXs)
Wage Multiplier:     ^3%.0f%%^7 (%s)
Municipal Degraded:  %s
^5===========================================^7
]],
        telemetry.fiscalState,
        telemetry.tripped and "^1YES^7" or "^2NO^7",
        telemetry.tripReason or "N/A",
        telemetry.masterReserve,
        telemetry.targetReserve,
        telemetry.criticalReserve,
        telemetry.drainVelocity.velocityPerHour,
        telemetry.drainVelocity.totalOutflow,
        telemetry.drainVelocity.count,
        telemetry.wageMultiplier * 100,
        telemetry.wageStatus,
        telemetry.municipalDegraded and "^1YES (Austerity Active)^7" or "^2NO^7"
    )

    if src == 0 then
        print(msg)
    else
        TriggerClientEvent("chat:addMessage", src, {
            color = { 70, 130, 180 },
            multiline = true,
            args = { "Municipal Treasury", msg }
        })
    end
end, false)

RegisterCommand("resettreasurycircuit", function(src, args)
    local authorized = (src == 0)
    local authorizedBy = "SERVER_CONSOLE"

    if src > 0 then
        local player = exports['nyx_core']:GetPlayer(src)
        if player and (player:hasPermission("admin") or player:hasPermission("mayor") or player:hasPermission("treasurer")) then
            authorized = true
            authorizedBy = player.citizenId or string.format("src:%d", src)
        end
    end

    if not authorized then
        if src > 0 then
            TriggerClientEvent("nyx:core:client:notify", src, "Unauthorized to reset fiscal circuit breaker.", "error")
        end
        return
    end

    local reason = args[1] and table.concat(args, " ") or "Executive authorization"
    local ok, newState = Nyx.Treasury.ResetCircuitBreaker(authorizedBy, reason)
    if not ok then
        local err = string.format("Circuit reset failed: %s", tostring(newState))
        if src == 0 then print(err) else TriggerClientEvent("nyx:core:client:notify", src, err, "error") end
    end
end, false)

RegisterCommand("triptreasurycircuit", function(src, args)
    local authorized = (src == 0)
    local authorizedBy = "SERVER_CONSOLE"

    if src > 0 then
        local player = exports['nyx_core']:GetPlayer(src)
        if player and player:hasPermission("admin") then
            authorized = true
            authorizedBy = player.citizenId or string.format("src:%d", src)
        end
    end

    if not authorized then return end

    local reason = args[1] and table.concat(args, " ") or "Manual administrative drill"
    Nyx.Treasury.TripCircuitBreaker(reason, authorizedBy)
end, false)

-- Background Evaluator Thread (every 10 seconds)
CreateThread(function()
    while true do
        Wait(10000)
        pcall(Nyx.Treasury.EvaluateFiscalHealth)
    end
end)
