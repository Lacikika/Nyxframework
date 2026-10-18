--[[
    Nyxframework: nyx_press
    File: shared/subscriptions.lua
    Description: Pure Lua 5.4 domain logic for media subscriptions, recurring revenue splits,
                 delivery route validation, and whistleblower bounty escrow mechanics.
]]

Nyx = Nyx or {}
Nyx.Press = Nyx.Press or {}
Nyx.Press.Subscriptions = {}

local Sub = Nyx.Press.Subscriptions

-- ----------------------------------------------------------------------------
-- 1. Double-Entry Revenue Split Conservation
-- ----------------------------------------------------------------------------
-- Computes publisher share, whistleblower investigative pool, and municipal tax.
-- Enforces closed-loop economic conservation: Pub + Pool + Tax == TotalPrice (Zero Cent Leakage)
function Sub.CalculateSubscriptionSplit(price, pubRatio, poolRatio, taxRatio)
    local gross = math.max(0.00, math.floor((tonumber(price) or 0.00) * 100) / 100)
    if gross <= 0.00 then
        return 0.00, 0.00, 0.00, 0.00
    end

    local rPub = math.max(0.00, tonumber(pubRatio) or 0.7500)
    local rPool = math.max(0.00, tonumber(poolRatio) or 0.1500)
    local rTax = math.max(0.00, tonumber(taxRatio) or 0.1000)

    local sumRatios = rPub + rPool + rTax
    if sumRatios <= 0.0 then
        rPub, rPool, rTax = 0.75, 0.15, 0.10
        sumRatios = 1.0
    end

    -- Normalize ratios if sum != 1.0
    if math.abs(sumRatios - 1.0) > 0.0001 then
        rPub = rPub / sumRatios
        rPool = rPool / sumRatios
        rTax = rTax / sumRatios
    end

    local pubShare = math.floor((gross * rPub) * 100) / 100
    local poolShare = math.floor((gross * rPool) * 100) / 100
    local taxShare = math.floor((gross - pubShare - poolShare) * 100) / 100

    -- Strict zero-cent leakage invariant correction
    local delta = math.floor((gross - (pubShare + poolShare + taxShare)) * 100) / 100
    if delta ~= 0.00 then
        pubShare = math.floor((pubShare + delta) * 100) / 100
    end

    return pubShare, poolShare, taxShare, gross
end

-- ----------------------------------------------------------------------------
-- 2. Plan Specification Validator
-- ----------------------------------------------------------------------------
local VALID_PLAN_TYPES = {
    ['digital'] = true,
    ['print_delivery'] = true,
    ['syndication'] = true
}

function Sub.ValidateSubscriptionPlan(plan)
    if not plan or type(plan) ~= "table" then
        return false, "MISSING_PLAN_DATA"
    end

    local planId = tostring(plan.planId or plan.plan_id or "")
    if #planId < 3 or #planId > 64 then
        return false, "INVALID_PLAN_ID"
    end

    local outletId = tostring(plan.outletId or plan.outlet_id or "")
    if #outletId < 3 or #outletId > 64 then
        return false, "INVALID_OUTLET_ID"
    end

    local name = tostring(plan.name or "")
    if #name < 3 or #name > 128 then
        return false, "INVALID_PLAN_NAME"
    end

    local pType = tostring(plan.planType or plan.plan_type or "digital")
    if not VALID_PLAN_TYPES[pType] then
        return false, "INVALID_PLAN_TYPE"
    end

    local price = tonumber(plan.price) or 0.0
    if price <= 0.0 or price > 10000.0 then
        return false, "INVALID_PLAN_PRICE"
    end

    local period = tonumber(plan.billingPeriodSec or plan.billing_period_sec) or 604800
    if period < 60 or period > 31536000 then -- Between 1 minute and 1 year
        return false, "INVALID_BILLING_PERIOD"
    end

    return true, "VALID"
end

-- ----------------------------------------------------------------------------
-- 3. Subscription Lifecycle State Machine Evaluator
-- ----------------------------------------------------------------------------
function Sub.EvaluateSubscriptionStatus(currentStatus, periodEndSec, nowSec, consecutiveFailures, maxFailures)
    local status = tostring(currentStatus or "active")
    local pEnd = tonumber(periodEndSec) or 0
    local now = tonumber(nowSec) or os.time()
    local fails = math.max(0, tonumber(consecutiveFailures) or 0)
    local maxF = math.max(1, tonumber(maxFailures) or 3)

    if status == "cancelled" then
        if now > pEnd then
            return "expired", false
        else
            return "cancelled", true -- Still within paid period
        end
    end

    if now <= pEnd then
        return "active", true
    end

    -- Past period end
    if fails >= maxF then
        return "expired", false
    else
        return "past_due", false
    end
end

-- ----------------------------------------------------------------------------
-- 4. Whistleblower Bounty Award Evaluator
-- ----------------------------------------------------------------------------
function Sub.ValidateBountyAward(bountyAmount, escrowBalance, leakStatus)
    local amt = tonumber(bountyAmount) or 0.0
    if amt <= 0.0 then
        return false, "INVALID_BOUNTY_AMOUNT"
    end

    local bal = tonumber(escrowBalance) or 0.0
    if amt > bal then
        return false, "INSUFFICIENT_ESCROW_BALANCE"
    end

    local st = tostring(leakStatus or "")
    if st ~= "under_investigation" and st ~= "published" then
        return false, "INVALID_LEAK_STATUS"
    end

    return true, "VALID"
end

-- ----------------------------------------------------------------------------
-- 5. Whistleblower Bounty Claim Verification
-- ----------------------------------------------------------------------------
function Sub.VerifyBountyClaim(sourceHash, citizenId, salt, nonce)
    if not sourceHash or not citizenId or not salt or not nonce then
        return false
    end
    if Nyx.Press and Nyx.Press.VerifySourceIdentity then
        return Nyx.Press.VerifySourceIdentity(sourceHash, citizenId, salt, nonce)
    end
    return false
end

-- ----------------------------------------------------------------------------
-- 6. Billing Period Calculation
-- ----------------------------------------------------------------------------
function Sub.CalculateNextBillingPeriod(currentPeriodEndSec, billingPeriodSec, nowSec)
    local pEnd = tonumber(currentPeriodEndSec) or 0
    local period = math.max(60, tonumber(billingPeriodSec) or 604800)
    local now = tonumber(nowSec) or os.time()

    local newStart = math.max(now, pEnd)
    local newEnd = newStart + period

    return newStart, newEnd
end

-- ----------------------------------------------------------------------------
-- 7. UI Telemetry & Status Badges
-- ----------------------------------------------------------------------------
function Sub.FormatSubscriptionBadge(status)
    local map = {
        ['active'] = { text = "AKTÍV", color = "#10B981" },
        ['past_due'] = { text = "DÍJHÁTRALÉK", color = "#F59E0B" },
        ['cancelled'] = { text = "LEMONDVA", color = "#6B7280" },
        ['expired'] = { text = "LEJÁRT", color = "#EF4444" }
    }
    return map[status] or { text = "ISMERETLEN", color = "#9CA3AF" }
end

return Sub
