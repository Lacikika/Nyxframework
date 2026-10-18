--[[
    Nyxframework: nyx_properties
    File: shared/taxation.lua
    Description: Pure Lua 5.4 Progressive Property Millage & Dynamic Land Maintenance Engine.
                 Features exponential holding taxation (1.5^(N-1)), land footprint taxation ($/m^2),
                 blight condition penalties, delinquency state machine, and closed-loop revenue splits.
]]

Nyx = Nyx or {}
Nyx.Taxation = {}

-- Helper: Round to nearest cent with integer precision
local function roundToCent(val)
    val = tonumber(val) or 0.0
    return math.floor(val * 100.0 + 0.5) / 100.0
end

-- 1. Progressive Holding Multiplier: 1.5^(PropertiesOwned - 1)
-- Discourages monopolistic property accumulation by scaling holding costs exponentially.
function Nyx.Taxation.CalculateHoldingMultiplier(propertiesOwned, baseRate, maxMultiplier)
    propertiesOwned = math.max(1, math.floor(tonumber(propertiesOwned) or 1))
    baseRate = tonumber(baseRate) or (Config.Taxation and Config.Taxation.ProgressiveHoldingBase) or 1.50
    maxMultiplier = tonumber(maxMultiplier) or (Config.Taxation and Config.Taxation.MaxHoldingMultiplier) or 10.00

    if propertiesOwned <= 1 then
        return 1.0000
    end

    local rawMultiplier = baseRate ^ (propertiesOwned - 1)
    local clamped = math.min(maxMultiplier, math.max(1.0000, rawMultiplier))
    return math.floor(clamped * 10000 + 0.5) / 10000
end

-- 2. Effective Millage Tax Rate (with statutory maximum cap clamping)
function Nyx.Taxation.CalculateEffectiveMillageRate(baseRate, propertiesOwned, maxRate, holdingBase)
    baseRate = math.max(0.0, tonumber(baseRate) or 0.0150)
    maxRate = tonumber(maxRate) or (Config.Taxation and Config.Taxation.MaxEffectiveMillageRate) or 0.1000

    local multiplier = Nyx.Taxation.CalculateHoldingMultiplier(propertiesOwned, holdingBase)
    local effective = math.min(maxRate, baseRate * multiplier)
    return math.floor(effective * 10000 + 0.5) / 10000
end

-- 3. Millage Tax Calculation (Cent-Precision)
function Nyx.Taxation.CalculateMillageTax(propertyPrice, effectiveMillageRate)
    propertyPrice = math.max(0.0, tonumber(propertyPrice) or 0.0)
    effectiveMillageRate = math.max(0.0, tonumber(effectiveMillageRate) or 0.0)

    local rawTax = propertyPrice * effectiveMillageRate
    return roundToCent(rawTax)
end

-- 4. Dilapidation & Blight Condition Surcharge Factor
-- Neglected buildings impose externalities on neighborhood infrastructure, incurring up to +50% blight tax.
function Nyx.Taxation.CalculateConditionBlightFactor(condition, maxBlightSurcharge)
    condition = math.max(0.0, math.min(100.0, tonumber(condition) or 100.0))
    maxBlightSurcharge = tonumber(maxBlightSurcharge) or (Config.Taxation and Config.Taxation.MaxBlightSurcharge) or 0.50

    local dilapidationRatio = (100.0 - condition) / 100.0
    local blightFactor = 1.0 + (dilapidationRatio * maxBlightSurcharge)
    return math.floor(blightFactor * 10000 + 0.5) / 10000
end

-- 5. Dynamic Land Footprint Maintenance Tax ($/m^2)
function Nyx.Taxation.CalculateLandMaintenanceTax(landAreaSqm, propertyType, zoneId, condition, customConfig)
    landAreaSqm = math.max(0.0, tonumber(landAreaSqm) or 100.0)
    propertyType = tostring(propertyType or 'residential')
    zoneId = tostring(zoneId or 'zone_ls_metro')

    local cfg = customConfig or (Config and Config.Taxation) or {}
    local rates = cfg.LandMaintenanceRates or {
        ['residential'] = 1.20,
        ['commercial'] = 2.50,
        ['industrial'] = 3.20
    }
    local baseRatePerSqm = tonumber(rates[propertyType]) or 1.20

    local zones = cfg.ZoneSurcharges or {
        ['zone_ls_metro'] = 0.15,
        ['zone_port_industrial'] = 0.10,
        ['zone_sandy_shores'] = 0.00,
        ['zone_paleto_bay'] = 0.00
    }
    local zoneSurcharge = tonumber(zones[zoneId]) or 0.0
    local zoneMultiplier = 1.0 + zoneSurcharge

    local blightFactor = Nyx.Taxation.CalculateConditionBlightFactor(condition, cfg.MaxBlightSurcharge)

    local rawTax = landAreaSqm * baseRatePerSqm * zoneMultiplier * blightFactor
    local roundedTax = roundToCent(rawTax)

    return roundedTax, baseRatePerSqm, zoneMultiplier, blightFactor
end

-- 6. Delinquency State Machine Evaluation
-- Maps consecutive missed billing cycles into progressive enforcement tiers
function Nyx.Taxation.EvaluateDelinquencyTier(consecutiveMissedCycles)
    local cycles = math.max(0, math.floor(tonumber(consecutiveMissedCycles) or 0))

    if cycles == 0 then
        return 0, "GOOD_STANDING"
    elseif cycles == 1 then
        return 1, "NOTICE_GRACE"
    elseif cycles == 2 then
        return 2, "LATE_PENALIZED"
    elseif cycles == 3 then
        return 3, "FORECLOSURE_WARNING"
    else
        return 4, "FORFEITURE_AUCTION"
    end
end

-- 7. Delinquency Late Penalty Calculation
function Nyx.Taxation.CalculateDelinquencyPenalty(delinquencyTier, overdueArrears, customRates)
    local tier = tonumber(delinquencyTier) or 0
    local arrears = math.max(0.0, tonumber(overdueArrears) or 0.0)

    if tier <= 1 or arrears <= 0.0 then
        return 0.00, 0.0
    end

    local rate = 0.10
    if tier == 2 then
        rate = 0.10 -- 10% late fee
    elseif tier >= 3 then
        rate = 0.25 -- 25% foreclosure / delinquency penalty
    end

    local penalty = roundToCent(arrears * rate)
    return penalty, rate
end

-- 8. Comprehensive Property Tax Assessment Aggregator
function Nyx.Taxation.CalculateTotalAssessment(params)
    params = params or {}
    local price = tonumber(params.price) or 0.00
    local baseMillageRate = tonumber(params.baseMillageRate) or (Config.Millage and Config.Millage.DefaultMillageRate) or 0.0150
    local propertiesOwned = tonumber(params.propertiesOwned) or 1
    local landAreaSqm = tonumber(params.landAreaSqm) or 100.00
    local propertyType = params.propertyType or "residential"
    local zoneId = params.zoneId or "zone_ls_metro"
    local condition = tonumber(params.condition) or 100.00
    local overdueArrears = tonumber(params.overdueArrears) or 0.00
    local missedCycles = tonumber(params.missedCycles) or 0

    local holdingMultiplier = Nyx.Taxation.CalculateHoldingMultiplier(propertiesOwned)
    local effectiveMillageRate = Nyx.Taxation.CalculateEffectiveMillageRate(baseMillageRate, propertiesOwned)
    local millageTax = Nyx.Taxation.CalculateMillageTax(price, effectiveMillageRate)

    local maintenanceTax, baseRatePerSqm, zoneMult, blightFactor = Nyx.Taxation.CalculateLandMaintenanceTax(landAreaSqm, propertyType, zoneId, condition)

    local tier, statusLabel = Nyx.Taxation.EvaluateDelinquencyTier(missedCycles)
    local penalty, penaltyRate = Nyx.Taxation.CalculateDelinquencyPenalty(tier, overdueArrears)

    local totalTaxDue = roundToCent(millageTax + maintenanceTax + penalty)

    return {
        price = price,
        propertiesOwned = propertiesOwned,
        holdingMultiplier = holdingMultiplier,
        baseMillageRate = baseMillageRate,
        effectiveMillageRate = effectiveMillageRate,
        millageTax = millageTax,
        landAreaSqm = landAreaSqm,
        propertyType = propertyType,
        zoneId = zoneId,
        condition = condition,
        baseRatePerSqm = baseRatePerSqm,
        zoneMultiplier = zoneMult,
        blightFactor = blightFactor,
        maintenanceTax = maintenanceTax,
        delinquencyTier = tier,
        delinquencyStatus = statusLabel,
        overdueArrears = overdueArrears,
        penalty = penalty,
        penaltyRate = penaltyRate,
        totalTaxDue = totalTaxDue
    }
end

-- 9. Closed-Loop Municipal Revenue Redistribution Split
-- Adheres to double-entry conservation: emergency + works + master == total
function Nyx.Taxation.CalculateRevenueDistribution(totalTaxAmount, customSplits)
    local totalCents = math.floor((tonumber(totalTaxAmount) or 0.0) * 100.0 + 0.5)
    if totalCents <= 0 then
        return { emergency = 0.00, works = 0.00, master = 0.00, total = 0.00 }
    end

    local emergencyRatio = 0.40
    local worksRatio = 0.45
    if customSplits then
        emergencyRatio = tonumber(customSplits.EmergencyServices) or emergencyRatio
        worksRatio = tonumber(customSplits.PublicWorks) or worksRatio
    elseif Config.Taxation and Config.Taxation.RevenueSplits then
        emergencyRatio = tonumber(Config.Taxation.RevenueSplits.EmergencyServices) or emergencyRatio
        worksRatio = tonumber(Config.Taxation.RevenueSplits.PublicWorks) or worksRatio
    end

    local emergencyCents = math.floor(totalCents * emergencyRatio)
    local worksCents = math.floor(totalCents * worksRatio)
    local masterCents = totalCents - emergencyCents - worksCents

    return {
        emergency = emergencyCents / 100.0,
        works = worksCents / 100.0,
        master = masterCents / 100.0,
        total = totalCents / 100.0
    }
end

-- 10. Land Maintenance Condition Decay Over Time
function Nyx.Taxation.CalculateConditionDecay(lastMaintenanceTimestamp, currentTimestamp, hoursPerPercent)
    local lastTime = tonumber(lastMaintenanceTimestamp) or os.time()
    local nowTime = tonumber(currentTimestamp) or os.time()
    local hoursPerPct = tonumber(hoursPerPercent) or (Config.Taxation and Config.Taxation.ConditionDecayHoursPerPercent) or 24.0

    if nowTime <= lastTime then
        return 0.00
    end

    local elapsedHours = (nowTime - lastTime) / 3600.0
    local decayPct = elapsedHours / hoursPerPct
    return roundToCent(decayPct)
end

-- 11. Property Structural Repair Cost
function Nyx.Taxation.CalculateRepairCost(landAreaSqm, currentCondition, costPerSqmPoint)
    landAreaSqm = math.max(0.0, tonumber(landAreaSqm) or 100.00)
    currentCondition = math.max(0.0, math.min(100.0, tonumber(currentCondition) or 100.00))
    costPerSqmPoint = tonumber(costPerSqmPoint) or (Config.Taxation and Config.Taxation.RepairCostPerSqmPoint) or 0.05

    local pointsNeeded = 100.00 - currentCondition
    if pointsNeeded <= 0.0 then
        return 0.00, 0.00
    end

    local totalCost = landAreaSqm * pointsNeeded * costPerSqmPoint
    local rounded = roundToCent(totalCost)
    return rounded, pointsNeeded
end
