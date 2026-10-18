--[[
    Nyxframework: nyx_treasury
    File: shared/circuit.lua
    Description: Pure Lua 5.4 deterministic fiscal circuit protection and
                 logarithmic public wage scaling algorithms.
]]

Nyx = Nyx or {}
Nyx.Circuit = {}

-- Calculate logarithmic wage scale multiplier
-- Formula: Smooth logarithmic curve between CriticalReserve and TargetReserve
function Nyx.Circuit.CalculateWageMultiplier(currentReserve, targetReserve, criticalReserve, cautionReserve, opts)
    currentReserve = tonumber(currentReserve) or 0.00
    targetReserve = tonumber(targetReserve) or 5000000.00
    criticalReserve = tonumber(criticalReserve) or 500000.00
    cautionReserve = tonumber(cautionReserve) or (targetReserve * 0.50)
    opts = opts or {}

    local floor = tonumber(opts.austerityFloor) or 0.10
    local critMultiplier = tonumber(opts.criticalMultiplier) or 0.00

    -- Boundary condition: Fully solvent
    if currentReserve >= targetReserve then
        return 1.00, "SOLVENT", currentReserve
    end

    -- Boundary condition: At or below critical reserve
    if currentReserve <= criticalReserve then
        return critMultiplier, "CRITICAL_FREEZE", currentReserve
    end

    -- Smooth logarithmic scaling:
    -- Ratio of reserve above critical: r = currentReserve / criticalReserve > 1
    -- R_target = targetReserve / criticalReserve > 1
    -- logScale = ln(r) / ln(R_target) in range (0, 1)
    local logRatio = math.log(currentReserve / criticalReserve)
    local logMax = math.log(targetReserve / criticalReserve)
    local normalized = (logMax > 0) and (logRatio / logMax) or 0.00

    -- Smoothly apply floor as the lower boundary:
    -- multiplier = floor + (1.0 - floor) * normalized
    local scaled = floor + ((1.00 - floor) * normalized)
    local clamped = math.max(floor, math.min(1.00, scaled))
    local multiplier = math.floor(clamped * 100) / 100

    local status = (currentReserve < cautionReserve) and "AUSTERITY" or "THROTTLED"
    return multiplier, status, currentReserve
end

-- Determine overall municipal fiscal state
function Nyx.Circuit.DetermineFiscalState(currentReserve, targetReserve, criticalReserve, cautionReserve, isCircuitTripped)
    currentReserve = tonumber(currentReserve) or 0.00
    targetReserve = tonumber(targetReserve) or 5000000.00
    criticalReserve = tonumber(criticalReserve) or 500000.00
    cautionReserve = tonumber(cautionReserve) or (targetReserve * 0.50)

    if isCircuitTripped then
        return "CIRCUIT_TRIPPED"
    end

    if currentReserve <= criticalReserve then
        return "CRITICAL_DEFICIT"
    end

    if currentReserve < cautionReserve then
        return "AUSTERITY"
    end

    if currentReserve < targetReserve then
        return "THROTTLED"
    end

    return "SOLVENT"
end

-- Filter and calculate rolling outflow velocity across sliding time window
function Nyx.Circuit.CalculateDrainVelocity(outflows, windowSeconds, now)
    windowSeconds = tonumber(windowSeconds) or 600
    now = tonumber(now) or os.time()
    local cutoff = now - windowSeconds

    local activeOutflows = {}
    local totalOutflow = 0.00
    local count = 0

    if outflows then
        for _, entry in ipairs(outflows) do
            local ts = tonumber(entry.timestamp) or 0
            local amt = tonumber(entry.amount) or 0.00
            if ts >= cutoff and amt > 0 then
                activeOutflows[#activeOutflows + 1] = entry
                totalOutflow = totalOutflow + amt
                count = count + 1
            end
        end
    end

    local velocityPerSecond = (windowSeconds > 0) and (totalOutflow / windowSeconds) or 0.00
    local velocityPerHour = velocityPerSecond * 3600.00

    return {
        totalOutflow = math.floor(totalOutflow * 100) / 100,
        velocityPerSecond = math.floor(velocityPerSecond * 100) / 100,
        velocityPerHour = math.floor(velocityPerHour * 100) / 100,
        windowSeconds = windowSeconds,
        count = count,
        activeOutflows = activeOutflows
    }
end

-- Evaluate conditions for tripping the fiscal circuit breaker
function Nyx.Circuit.EvaluateCircuitTrip(params)
    params = params or {}
    local currentReserve = tonumber(params.currentReserve) or 0.00
    local criticalReserve = tonumber(params.criticalReserve) or 500000.00
    local rollingOutflow = tonumber(params.rollingOutflow) or 0.00
    local maxRollingOutflow = tonumber(params.maxRollingOutflow) or 750000.00
    local singleTxAmount = tonumber(params.singleTxAmount) or 0.00
    local maxSingleTransaction = tonumber(params.maxSingleTransaction) or 500000.00
    local isCurrentlyTripped = params.isCurrentlyTripped == true

    -- Condition 1: Critical Reserve Depleted
    if currentReserve <= criticalReserve then
        return true, "CRITICAL_RESERVE_DEPLETED", {
            currentReserve = currentReserve,
            criticalReserve = criticalReserve
        }
    end

    -- Condition 2: Burst Drain Velocity Exceeded
    if rollingOutflow > maxRollingOutflow then
        return true, "BURST_DRAIN_VELOCITY_EXCEEDED", {
            rollingOutflow = rollingOutflow,
            maxRollingOutflow = maxRollingOutflow
        }
    end

    -- Condition 3: Single Transaction Outlay Cap Exceeded (without override)
    if singleTxAmount > 0 and singleTxAmount > maxSingleTransaction then
        return true, "SINGLE_TRANSACTION_CAP_EXCEEDED", {
            singleTxAmount = singleTxAmount,
            maxSingleTransaction = maxSingleTransaction
        }
    end

    -- If already tripped, maintain trip state until reset
    if isCurrentlyTripped then
        return true, "TRIPPED_MANUAL_OR_COOLDOWN", {}
    end

    return false, "NORMAL", {}
end

-- Evaluate conditions for automatic circuit breaker recovery / reset
function Nyx.Circuit.CanAutoResetCircuit(params)
    params = params or {}
    local currentReserve = tonumber(params.currentReserve) or 0.00
    local recoveryReserve = tonumber(params.recoveryReserve) or 1000000.00
    local rollingOutflow = tonumber(params.rollingOutflow) or 0.00
    local maxRollingOutflow = tonumber(params.maxRollingOutflow) or 750000.00
    local hysteresisMargin = tonumber(params.hysteresisMargin) or 0.75
    local trippedAt = tonumber(params.trippedAt) or 0
    local cooldownSeconds = tonumber(params.cooldownSeconds) or 300
    local now = tonumber(params.now) or os.time()

    -- 1. Reserve Solvency Gate
    if currentReserve < recoveryReserve then
        return false, "INSUFFICIENT_RESERVE_FOR_RESET", {
            current = currentReserve,
            required = recoveryReserve
        }
    end

    -- 2. Outflow Velocity Stabilization Gate (must drop below hysteresis threshold)
    local allowedOutflow = maxRollingOutflow * hysteresisMargin
    if rollingOutflow > allowedOutflow then
        return false, "DRAIN_VELOCITY_STILL_ELEVATED", {
            current = rollingOutflow,
            threshold = allowedOutflow
        }
    end

    -- 3. Minimum Cooldown Gate
    local elapsed = now - trippedAt
    if elapsed < cooldownSeconds then
        return false, "COOLDOWN_ACTIVE", {
            elapsed = elapsed,
            cooldown = cooldownSeconds
        }
    end

    return true, "RECOVERY_CONDITIONS_MET", {
        reserve = currentReserve,
        outflow = rollingOutflow,
        elapsed = elapsed
    }
end

-- Calculate emergency subvention from municipal master reserve to an underfunded department
function Nyx.Circuit.CalculateSubvention(deptBalance, requiredPayroll, masterReserve, criticalReserve)
    deptBalance = math.max(0.00, tonumber(deptBalance) or 0.00)
    requiredPayroll = math.max(0.00, tonumber(requiredPayroll) or 0.00)
    masterReserve = math.max(0.00, tonumber(masterReserve) or 0.00)
    criticalReserve = math.max(0.00, tonumber(criticalReserve) or 500000.00)

    local deficit = math.max(0.00, requiredPayroll - deptBalance)
    if deficit <= 0.00 then
        return 0.00, "DEPARTMENT_SOLVENT", 0.00
    end

    local availableMasterSurplus = math.max(0.00, masterReserve - criticalReserve)
    if availableMasterSurplus <= 0.00 then
        return 0.00, "INSUFFICIENT_MASTER_SURPLUS", deficit
    end

    local grant = math.min(deficit, availableMasterSurplus)
    grant = math.floor(grant * 100) / 100

    local status = (grant >= deficit) and "FULL_SUBVENTION" or "PARTIAL_SUBVENTION"
    return grant, status, deficit
end
