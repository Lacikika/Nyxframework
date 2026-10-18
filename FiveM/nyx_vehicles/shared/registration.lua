--[[
    Nyxframework: nyx_vehicles
    File: shared/registration.lua
    Description: Pure Lua 5.4 vehicle registration lifecycle, renewal fee calculations,
                 statutory late penalties, and impound release validation.
]]

Nyx = Nyx or {}
Nyx.Registration = Nyx.Registration or {}

Nyx.Registration.DURATION_SECONDS = 14 * 86400 -- 14 Days (1,209,600s)

Nyx.Registration.CLASS_FEES = {
    ["motorcycle"] = 150.00,
    ["compact"]    = 250.00,
    ["sedan"]      = 250.00,
    ["coupe"]      = 250.00,
    ["suv"]        = 250.00,
    ["sports"]     = 500.00,
    ["super"]      = 500.00,
    ["commercial"] = 450.00,
    ["industrial"] = 450.00,
    ["default"]    = 250.00
}

--- Evaluates registration status (valid, expired, suspended) based on timestamp.
--- @param rawStatus string
--- @param expiresAt number
--- @param currentTime number
--- @return string ("valid", "expired", "suspended")
function Nyx.Registration.EvaluateStatus(rawStatus, expiresAt, currentTime)
    if rawStatus == "suspended" then
        return "suspended"
    end

    local exp = tonumber(expiresAt) or 0
    local now = tonumber(currentTime) or os.time()

    if exp > now then
        return "valid"
    end

    return "expired"
end

--- Computes renewal fee, late statutory surcharge (+20%), and per-day expired penalties.
--- @param modelClass string
--- @param isExpired boolean
--- @param daysExpired number
--- @return table
function Nyx.Registration.CalculateRenewalFee(modelClass, isExpired, daysExpired)
    local cls = modelClass and string.lower(modelClass) or "default"
    local base = Nyx.Registration.CLASS_FEES[cls] or Nyx.Registration.CLASS_FEES["default"]

    local latePenalty = 0.00
    local days = math.max(0, math.floor(tonumber(daysExpired) or 0))

    if isExpired then
        local flatLate = math.floor(((base * 0.20) * 100) + 0.5) / 100
        local dailyPenalty = math.floor(((days * 5.00) * 100) + 0.5) / 100
        latePenalty = math.floor(((flatLate + dailyPenalty) * 100) + 0.5) / 100
    end

    local total = math.floor(((base + latePenalty) * 100) + 0.5) / 100

    return {
        baseFee = base,
        latePenalty = latePenalty,
        daysExpired = days,
        totalFee = total,
        isExpired = isExpired == true,
        durationSeconds = Nyx.Registration.DURATION_SECONDS
    }
end

--- Validates if a vehicle can be released from an impound lot under current fiscal tier.
--- @param vehicleData table
--- @param fiscalTier string
--- @return boolean canRelease
--- @return string|nil reason
function Nyx.Registration.CanReleaseFromImpound(vehicleData, fiscalTier)
    if not vehicleData then
        return false, "VEHICLE_NOT_FOUND"
    end

    if vehicleData.storage_state ~= "impounded" then
        return false, "VEHICLE_NOT_IMPOUNDED"
    end

    -- If city is bankrupt, check if impound lots are locked or allow emergency release
    if fiscalTier == "bankrupt" and vehicleData.emergencyLocked then
        return false, "IMPOUND_COMPOUND_LOCKED_MUNICIPAL_INSOLVENCY"
    end

    return true, nil
end
