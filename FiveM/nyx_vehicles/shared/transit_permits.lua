--[[
    Nyxframework: nyx_vehicles
    File: shared/transit_permits.lua
    Description: Pure deterministic formulas and helper functions for commercial transit permits,
                 heavy-haul fee evaluation, permit validity checks, overweight surcharge scaling,
                 and MDT violation classification.
]]

Nyx = Nyx or {}
Nyx.TransitPermits = Nyx.TransitPermits or {}

-- Round value cleanly to exact two decimal places (cents)
function Nyx.TransitPermits.RoundToCent(amount)
    amount = tonumber(amount) or 0.0
    return math.floor(amount * 100.0 + 0.5) / 100.0
end

-- Base Permit Pricing Schedules (in Dollars)
Nyx.TransitPermits.BasePermitFees = {
    ['SINGLE_TRIP']        = 150.00,
    ['DAILY_PASS']         = 450.00,
    ['ANNUAL_HEAVY_HAUL']  = 2500.00
}

-- Base Weight Thresholds covered by permit types (in kg)
Nyx.TransitPermits.PermitWeightCapacities = {
    ['SINGLE_TRIP']        = 25000.0,
    ['DAILY_PASS']         = 35000.0,
    ['ANNUAL_HEAVY_HAUL']  = 60000.0
}

-- Permit Duration in Seconds
Nyx.TransitPermits.PermitDurationsSeconds = {
    ['SINGLE_TRIP']        = 86400,    -- 24 hours
    ['DAILY_PASS']         = 86400,    -- 24 hours
    ['ANNUAL_HEAVY_HAUL']  = 31536000 -- 365 days
}

--- Pure calculation for commercial transit permit fees including heavy-haul weight surcharges
--- @param permitType string ('SINGLE_TRIP', 'DAILY_PASS', 'ANNUAL_HEAVY_HAUL')
--- @param requestedMaxWeightKg number Requested max weight capacity in kg
--- @param statutoryTaxRate number Dynamic statutory transit tax modifier (default 1.0)
--- @return number totalFee Total permit fee rounded to cent
--- @return number surcharge Portion of fee from weight surcharge
function Nyx.TransitPermits.CalculatePermitFee(permitType, requestedMaxWeightKg, statutoryTaxRate)
    permitType = tostring(permitType or 'SINGLE_TRIP')
    requestedMaxWeightKg = tonumber(requestedMaxWeightKg) or 25000.0
    statutoryTaxRate = tonumber(statutoryTaxRate) or 1.00

    local baseFee = Nyx.TransitPermits.BasePermitFees[permitType] or 150.00
    local baseCap = Nyx.TransitPermits.PermitWeightCapacities[permitType] or 25000.0

    local excessWeightKg = math.max(0.0, requestedMaxWeightKg - baseCap)
    -- Heavy-haul surcharge: $0.05 per excess kg over base permit capacity
    local surcharge = excessWeightKg * 0.05

    local grossFee = (baseFee + surcharge) * math.max(0.1, statutoryTaxRate)
    return Nyx.TransitPermits.RoundToCent(grossFee), Nyx.TransitPermits.RoundToCent(surcharge)
end

--- Evaluate whether an active permit covers a measured vehicle gross weight
--- @param permitRecord table Permit SQL record (or nil if no active permit)
--- @param measuredWeightKg number Measured vehicle gross weight in kg
--- @param currentTimestampEpoch number Current epoch timestamp in seconds
--- @return boolean isValid True if permit is valid and covers weight
--- @return string status ('VALID', 'NO_PERMIT', 'EXPIRED', 'WEIGHT_EXCEEDED')
function Nyx.TransitPermits.EvaluatePermitValidity(permitRecord, measuredWeightKg, currentTimestampEpoch)
    measuredWeightKg = tonumber(measuredWeightKg) or 0.0
    currentTimestampEpoch = tonumber(currentTimestampEpoch) or os.time()

    if not permitRecord or type(permitRecord) ~= "table" then
        return false, "NO_PERMIT"
    end

    if permitRecord.status and permitRecord.status ~= "ACTIVE" then
        return false, "EXPIRED"
    end

    local expiryEpoch = tonumber(permitRecord.expires_at_epoch) or 0
    if expiryEpoch > 0 and currentTimestampEpoch >= expiryEpoch then
        return false, "EXPIRED"
    end

    local permittedCapKg = tonumber(permitRecord.max_weight_capacity_kg) or 25000.0
    if measuredWeightKg > permittedCapKg then
        return false, "WEIGHT_EXCEEDED"
    end

    return true, "VALID"
end

--- Classify violation outcome and statutory fine for transit scale or highway ANPR checks
--- @param validityStatus string ('NO_PERMIT', 'EXPIRED', 'WEIGHT_EXCEEDED')
--- @param measuredWeightKg number Measured gross weight
--- @param permittedWeightKg number Permitted weight limit
--- @param didBypass boolean Whether vehicle bypassed scale
--- @return string violationType ('NO_PERMIT', 'WEIGHT_EXCEEDED', 'PERMIT_EXPIRED', 'BYPASS_UNLICENSED')
--- @return number fine Statutory fine amount in dollars
function Nyx.TransitPermits.ClassifyViolationAndFine(validityStatus, measuredWeightKg, permittedWeightKg, didBypass)
    measuredWeightKg = tonumber(measuredWeightKg) or 0.0
    permittedWeightKg = tonumber(permittedWeightKg) or 15000.0

    if didBypass and validityStatus ~= "VALID" then
        return "BYPASS_UNLICENSED", 1500.00
    end

    if validityStatus == "NO_PERMIT" then
        return "NO_PERMIT", 750.00
    elseif validityStatus == "EXPIRED" then
        return "PERMIT_EXPIRED", 500.00
    elseif validityStatus == "WEIGHT_EXCEEDED" then
        local excessKg = math.max(0.0, measuredWeightKg - permittedWeightKg)
        local fine = 500.00 + (excessKg * 3.00) -- $500 base + $3.00/kg excess over permitted limit
        return "WEIGHT_EXCEEDED", Nyx.TransitPermits.RoundToCent(fine)
    end

    return "NONE", 0.00
end
