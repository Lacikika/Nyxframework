--[[
    Nyxframework: nyx_treasury
    File: shared/degradation.lua
    Description: Pure Lua 5.4 municipal fiscal solvency evaluation, infrastructure degradation state machine,
                 impound emergency surcharges, and public repair station cost modeling.
]]

Nyx = Nyx or {}
Nyx.Degradation = Nyx.Degradation or {}

Nyx.Degradation.THRESHOLDS = {
    OPTIMAL  = 100000.0,
    STRESS   = 50000.0,
    DEGRADED = 20000.0,
    BANKRUPT = 0.0
}

Nyx.Degradation.TIERS = {
    SOLVENT       = "solvent",
    FISCAL_STRESS = "fiscal_stress",
    DEGRADED      = "degraded",
    BANKRUPT      = "bankrupt"
}

Nyx.Degradation.SURCHARGES = {
    ["solvent"] = {
        label = "Solvent (Optimal Operations)",
        repairPct = 0.0,
        impoundSurcharge = 0.0,
        dispatchLatencySec = 0,
        autoRepairStatus = "subsidized",
        impoundLotStatus = "standard",
        canRepairWithoutKit = true
    },
    ["fiscal_stress"] = {
        label = "Fiscal Stress (Subsidies Constrained)",
        repairPct = 0.10,
        impoundSurcharge = 0.0,
        dispatchLatencySec = 5,
        autoRepairStatus = "at_cost",
        impoundLotStatus = "standard",
        canRepairWithoutKit = true
    },
    ["degraded"] = {
        label = "Infrastructure Degradation (Austerity Mode)",
        repairPct = 0.25,
        impoundSurcharge = 100.0,
        dispatchLatencySec = 20,
        autoRepairStatus = "emergency_only",
        impoundLotStatus = "surcharged",
        canRepairWithoutKit = true
    },
    ["bankrupt"] = {
        label = "Municipal Bankruptcy (Public Services Insolvent)",
        repairPct = 0.50,
        impoundSurcharge = 250.0,
        dispatchLatencySec = 60,
        autoRepairStatus = "offline",
        impoundLotStatus = "emergency_only",
        canRepairWithoutKit = false
    }
}

--- Evaluates the municipal fiscal solvency tier from liquid master treasury balance.
--- @param liquidBalance number
--- @return string tier ("solvent", "fiscal_stress", "degraded", "bankrupt")
--- @return table details
function Nyx.Degradation.EvaluateFiscalTier(liquidBalance)
    local b = tonumber(liquidBalance) or 0.0
    local tier = Nyx.Degradation.TIERS.BANKRUPT

    if b > Nyx.Degradation.THRESHOLDS.STRESS then
        tier = Nyx.Degradation.TIERS.SOLVENT
    elseif b > Nyx.Degradation.THRESHOLDS.DEGRADED then
        tier = Nyx.Degradation.TIERS.FISCAL_STRESS
    elseif b > Nyx.Degradation.THRESHOLDS.BANKRUPT then
        tier = Nyx.Degradation.TIERS.DEGRADED
    else
        tier = Nyx.Degradation.TIERS.BANKRUPT
    end

    local details = Nyx.Degradation.SURCHARGES[tier] or Nyx.Degradation.SURCHARGES["solvent"]
    return tier, details
end

--- Returns static configuration details for a specific fiscal tier.
--- @param tier string
--- @return table details
function Nyx.Degradation.GetTierDetails(tier)
    return Nyx.Degradation.SURCHARGES[tier] or Nyx.Degradation.SURCHARGES["solvent"]
end

--- Computes total impound release fee with daily storage and emergency fiscal surcharges.
--- @param baseFee number
--- @param daysImpounded number
--- @param dailyRate number
--- @param fiscalTier string
--- @return table calculation
function Nyx.Degradation.CalculateImpoundReleaseCost(baseFee, daysImpounded, dailyRate, fiscalTier)
    local base = math.max(0.0, math.floor(((tonumber(baseFee) or 0.0) * 100) + 0.5) / 100)
    local days = math.max(0, math.floor(tonumber(daysImpounded) or 0))
    local daily = math.max(0.0, math.floor(((tonumber(dailyRate) or 0.0) * 100) + 0.5) / 100)

    local storageFee = math.floor(((days * daily) * 100) + 0.5) / 100
    local tierDetails = Nyx.Degradation.GetTierDetails(fiscalTier)
    local emergencySurcharge = tierDetails.impoundSurcharge or 0.0

    local total = math.floor(((base + storageFee + emergencySurcharge) * 100) + 0.5) / 100

    return {
        baseFee = base,
        storageFee = storageFee,
        emergencySurcharge = emergencySurcharge,
        totalFee = total,
        daysImpounded = days,
        dailyRate = daily,
        fiscalTier = fiscalTier or "solvent"
    }
end

--- Computes public auto-repair station cost based on vehicle damage, parts multiplier, and fiscal tier.
--- @param baseLabor number
--- @param damageRatio number (0.0 to 1.0)
--- @param partsMultiplier number
--- @param fiscalTier string
--- @param hasRepairKit boolean
--- @return boolean success
--- @return table|string resultOrError
function Nyx.Degradation.CalculatePublicRepairCost(baseLabor, damageRatio, partsMultiplier, fiscalTier, hasRepairKit)
    local tier = fiscalTier or "solvent"
    local details = Nyx.Degradation.GetTierDetails(tier)

    if tier == "bankrupt" and not hasRepairKit then
        return false, "STATION_INSOLVENT_REQUIRES_REPAIR_KIT"
    end

    local base = math.max(0.0, math.floor(((tonumber(baseLabor) or 0.0) * 100) + 0.5) / 100)
    local dmg = math.max(0.0, math.min(1.0, tonumber(damageRatio) or 0.0))
    local partsMult = math.max(0.5, tonumber(partsMultiplier) or 1.0)

    local rawParts = math.floor(((dmg * 500.0 * partsMult) * 100) + 0.5) / 100
    local surcharge = math.floor(((rawParts * (details.repairPct or 0.0)) * 100) + 0.5) / 100
    local partsTotal = math.floor(((rawParts + surcharge) * 100) + 0.5) / 100

    -- If bankrupt and player brings own kit, labor is discounted by 50%
    local laborTotal = base
    if tier == "bankrupt" and hasRepairKit then
        laborTotal = math.floor(((base * 0.5) * 100) + 0.5) / 100
    end

    local total = math.floor(((laborTotal + partsTotal) * 100) + 0.5) / 100

    return true, {
        laborFee = laborTotal,
        partsFee = rawParts,
        surcharge = surcharge,
        totalCost = total,
        fiscalTier = tier,
        requiresKit = not details.canRepairWithoutKit
    }
end
