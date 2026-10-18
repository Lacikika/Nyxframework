--[[
    Nyxframework: nyx_factions
    File: shared/laundering.lua
    Description: Pure Lua 5.4 domain logic for commercial cash registers,
                 drip laundering splits with strict cent conservation,
                 and register eligibility evaluation.
]]

Nyx = Nyx or {}
Nyx.Laundering = Nyx.Laundering or {}

-- 1. Declarative Business Profiles Taxonomy
Nyx.Laundering.BusinessProfiles = {
    ['nightclub'] = {
        type = 'nightclub',
        label = 'Nightclub / Bar',
        baselineCashRatio = 0.70,   -- Normal business expects 70% cash
        washFeePct = 12.0,          -- 12% operational overhead/burn
        maxDailyCap = 100000.00,    -- $100k daily volume cap
        defaultDrip = 5000.00,      -- $5,000 per wash cycle
        riskTolerance = 'high',
        description = 'High cash-turnover entertainment venue with substantial cash tolerance.'
    },
    ['carwash'] = {
        type = 'carwash',
        label = 'Automated & Hand Carwash',
        baselineCashRatio = 0.60,
        washFeePct = 15.0,
        maxDailyCap = 40000.00,
        defaultDrip = 2000.00,
        riskTolerance = 'high',
        description = 'Classic high-volume coin and cash operation with moderate capacity.'
    },
    ['restaurant'] = {
        type = 'restaurant',
        label = 'Diner / Restaurant',
        baselineCashRatio = 0.45,
        washFeePct = 14.0,
        maxDailyCap = 60000.00,
        defaultDrip = 3000.00,
        riskTolerance = 'medium',
        description = 'Hospitality venue blending credit card receipts and cash register bills.'
    },
    ['pawnshop'] = {
        type = 'pawnshop',
        label = 'Pawnshop & Gold Exchange',
        baselineCashRatio = 0.55,
        washFeePct = 18.0,
        maxDailyCap = 75000.00,
        defaultDrip = 4000.00,
        riskTolerance = 'high',
        description = 'Variable-valuation pawn storefront facilitating irregular cash inflows.'
    },
    ['retail'] = {
        type = 'retail',
        label = 'Convenience Store / Retail',
        baselineCashRatio = 0.30,
        washFeePct = 20.0,
        maxDailyCap = 30000.00,
        defaultDrip = 1500.00,
        riskTolerance = 'low',
        description = 'Small retail store where excessive cash bursts stand out prominently.'
    },
    ['consulting'] = {
        type = 'consulting',
        label = 'Management & Corporate Consulting',
        baselineCashRatio = 0.05,
        washFeePct = 25.0,
        maxDailyCap = 20000.00,
        defaultDrip = 1000.00,
        riskTolerance = 'very_low',
        description = 'Professional corporate office where physical cash is anomalous.'
    },
    ['logistics'] = {
        type = 'logistics',
        label = 'Freight & Warehouse Logistics',
        baselineCashRatio = 0.15,
        washFeePct = 15.0,
        maxDailyCap = 50000.00,
        defaultDrip = 2500.00,
        riskTolerance = 'low',
        description = 'Commercial freight depot where commercial invoices dominate.'
    }
}

-- 2. Pure Mathematical Laundering Split Calculator
-- Conserves 100% of the gross cash input: Gross == Clean + Tax + Overhead (Delta = 0.00)
function Nyx.Laundering.CalculateLaunderingSplit(grossAmount, businessType, customTaxPct)
    grossAmount = math.floor((tonumber(grossAmount) or 0.0) * 100 + 0.5) / 100
    if grossAmount <= 0.00 then
        return {
            gross = 0.00,
            clean = 0.00,
            tax = 0.00,
            overhead = 0.00,
            conservationDelta = 0.00,
            isValid = false
        }
    end

    local profile = Nyx.Laundering.BusinessProfiles[businessType] or Nyx.Laundering.BusinessProfiles.retail
    local taxRate = math.max(0.0, (tonumber(customTaxPct) or 10.0)) / 100.0
    local feeRate = (profile.washFeePct or 15.0) / 100.0

    local taxAmount = math.floor(grossAmount * taxRate * 100 + 0.5) / 100
    local overheadFee = math.floor(grossAmount * feeRate * 100 + 0.5) / 100
    local cleanAmount = math.floor((grossAmount - taxAmount - overheadFee) * 100 + 0.5) / 100

    -- Strict cent conservation adjustment
    local sum = math.floor((cleanAmount + taxAmount + overheadFee) * 100 + 0.5) / 100
    local delta = math.floor((grossAmount - sum) * 100 + 0.5) / 100
    cleanAmount = math.floor((cleanAmount + delta) * 100 + 0.5) / 100

    local finalSum = math.floor((cleanAmount + taxAmount + overheadFee) * 100 + 0.5) / 100
    local finalDelta = math.abs(grossAmount - finalSum)

    return {
        gross = grossAmount,
        clean = cleanAmount,
        tax = taxAmount,
        overhead = overheadFee,
        conservationDelta = finalDelta,
        isValid = (finalDelta < 0.001 and cleanAmount >= 0.00)
    }
end

-- 3. Pure Calculation of Drip Wash Amount per Tick
function Nyx.Laundering.CalculateDripAmount(dirtyPool, configuredDrip, remainingDailyCap)
    dirtyPool = math.max(0.0, math.floor((tonumber(dirtyPool) or 0.0) * 100 + 0.5) / 100)
    configuredDrip = math.max(0.0, math.floor((tonumber(configuredDrip) or 0.0) * 100 + 0.5) / 100)
    remainingDailyCap = math.max(0.0, math.floor((tonumber(remainingDailyCap) or 0.0) * 100 + 0.5) / 100)

    if dirtyPool <= 0.00 or remainingDailyCap <= 0.00 then
        return 0.00
    end

    local targetDrip = (configuredDrip > 0.00) and configuredDrip or 2500.00
    local washAmount = math.min(dirtyPool, targetDrip, remainingDailyCap)
    return math.floor(washAmount * 100 + 0.5) / 100
end

-- 4. Zero-Trust Injection Payload Validator
function Nyx.Laundering.ValidateInjectionPayload(payload)
    if type(payload) ~= "table" then
        return false, "PAYLOAD_MUST_BE_TABLE"
    end

    if not payload.registerId or type(payload.registerId) ~= "string" or #payload.registerId < 3 then
        return false, "INVALID_REGISTER_ID"
    end

    local amount = tonumber(payload.amount)
    if not amount or amount <= 0 or amount > 500000.00 then
        return false, "INVALID_INJECTION_AMOUNT_LIMIT_500K"
    end

    if not payload.citizenId or type(payload.citizenId) ~= "string" or #payload.citizenId < 3 then
        return false, "INVALID_CITIZEN_ID"
    end

    return true, {
        registerId = payload.registerId,
        amount = math.floor(amount * 100 + 0.5) / 100,
        citizenId = payload.citizenId,
        sourceNote = (type(payload.sourceNote) == "string" and #payload.sourceNote <= 128) and payload.sourceNote or "Cash Till Deposit"
    }
end

-- 5. Register Eligibility Evaluator
function Nyx.Laundering.EvaluateRegisterEligibility(registerData, injectAmount)
    if not registerData or type(registerData) ~= "table" then
        return false, "REGISTER_NOT_FOUND"
    end

    if registerData.is_active ~= 1 and registerData.isActive ~= true then
        return false, "REGISTER_DECOMMISSIONED"
    end

    if (registerData.is_frozen == 1 or registerData.isFrozen == true) then
        return false, string.format("REGISTER_FROZEN_BY_COURT_ORDER: %s", registerData.freeze_reason or registerData.freezeReason or "Subpoena Restraint")
    end

    local maxCap = tonumber(registerData.max_daily_laundering_cap or registerData.maxDailyLaunderingCap) or 50000.00
    local launderedToday = tonumber(registerData.daily_laundered_amount or registerData.dailyLaunderedAmount) or 0.00
    local currentDirty = tonumber(registerData.dirty_cash_pool or registerData.dirtyCashPool) or 0.00

    local remainingCap = math.max(0.00, maxCap - launderedToday)
    if remainingCap <= 0.00 and currentDirty <= 0.00 then
        return false, "DAILY_LAUNDERING_CAP_EXHAUSTED"
    end

    -- Maximum buffer capacity for unwashed dirty cash in a single register (e.g., 3x daily cap)
    local maxDirtyPool = maxCap * 3.0
    if (currentDirty + injectAmount) > maxDirtyPool then
        return false, string.format("REGISTER_VAULT_OVERFLOW_MAX_POOL_%.2f", maxDirtyPool)
    end

    return true, {
        remainingDailyCap = remainingCap,
        currentDirtyPool = currentDirty,
        projectedDirtyPool = currentDirty + injectAmount
    }
end

-- 6. Formatting Badges & Status Indicators
function Nyx.Laundering.FormatStatusBadge(registerData)
    if not registerData then return "[UNKNOWN]" end
    if registerData.is_frozen == 1 or registerData.isFrozen then
        return "[JUDICIALLY FROZEN]"
    end
    if registerData.is_active ~= 1 and not registerData.isActive then
        return "[INACTIVE]"
    end

    local dirty = tonumber(registerData.dirty_cash_pool or registerData.dirtyCashPool) or 0.00
    if dirty > 0 then
        return string.format("[WASHING: $%.2f QUEUED]", dirty)
    end

    return "[REGISTER OPERATIONAL]"
end
