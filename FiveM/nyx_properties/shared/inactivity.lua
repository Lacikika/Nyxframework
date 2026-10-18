--[[
    Nyxframework: nyx_properties
    File: shared/inactivity.lua
    Description: Pure Lua 5.4 Anti-Monopoly Inactivity Reclamation & Stewardship Engine.
                 Features time-decay inactivity modeling, stewardship delegate verification,
                 grace period countdown calculations, and public blind-auction minimum bids.
]]

Nyx = Nyx or {}
Nyx.Inactivity = {}

local function roundToCent(val)
    val = tonumber(val) or 0.0
    return math.floor(val * 100.0 + 0.5) / 100.0
end

Nyx.Inactivity.Defaults = {
    OwnerInactivityThresholdSeconds = 14 * 86400,  -- 14 days (1,209,600s)
    StewardMaxExtensionSeconds = 16 * 86400,       -- +16 days extension (total 30 days = 2,592,000s)
    GracePeriodSeconds = 3 * 86400,                -- 72-hour grace period (259,200s)
    AuctionMinBidDiscount = 0.50,                  -- 50% of original property valuation
    AbsoluteMinBidFloor = 1000.00                  -- Absolute starting bid floor ($1,000.00)
}

-- 1. Calculate Inactivity Duration in Seconds
function Nyx.Inactivity.CalculateInactivitySeconds(currentTime, lastActiveTime)
    currentTime = tonumber(currentTime) or os.time()
    lastActiveTime = tonumber(lastActiveTime) or currentTime
    return math.max(0, currentTime - lastActiveTime)
end

-- 2. Validate Stewardship Delegate Authorization
function Nyx.Inactivity.ValidateDelegation(ownerCitizenId, delegateCitizenId, scope)
    if not ownerCitizenId or type(ownerCitizenId) ~= "string" or #ownerCitizenId == 0 then
        return false, "INVALID_OWNER_CITIZEN_ID"
    end
    if not delegateCitizenId or type(delegateCitizenId) ~= "string" or #delegateCitizenId == 0 then
        return false, "INVALID_DELEGATE_CITIZEN_ID"
    end
    if ownerCitizenId == delegateCitizenId then
        return false, "CANNOT_DELEGATE_TO_SELF"
    end

    scope = scope or "all"
    local validScopes = { ['all'] = true, ['properties'] = true, ['factions'] = true }
    if not validScopes[scope] then
        return false, "INVALID_STEWARDSHIP_SCOPE"
    end

    return true, scope
end

-- 3. Evaluate Stewardship & Inactivity Status
-- Evaluates whether an asset is actively protected, sheltered by an active delegate,
-- entering a 72-hour grace period, or forfeited for municipal auction.
function Nyx.Inactivity.EvaluateStewardshipStatus(currentTime, ownerLastActive, delegateCitizenId, delegateLastActive, warningAt, cfg)
    cfg = cfg or Nyx.Inactivity.Defaults
    local ownerThreshold = cfg.OwnerInactivityThresholdSeconds or Nyx.Inactivity.Defaults.OwnerInactivityThresholdSeconds
    local maxExtension = cfg.StewardMaxExtensionSeconds or Nyx.Inactivity.Defaults.StewardMaxExtensionSeconds
    local gracePeriod = cfg.GracePeriodSeconds or Nyx.Inactivity.Defaults.GracePeriodSeconds

    currentTime = tonumber(currentTime) or os.time()
    ownerLastActive = tonumber(ownerLastActive) or currentTime
    local ownerInactivitySec = math.max(0, currentTime - ownerLastActive)

    -- Case A: Owner is actively logging in within standard threshold (<= 14 days)
    if ownerInactivitySec <= ownerThreshold then
        return {
            status = "active",
            isProtected = true,
            inactivitySeconds = ownerInactivitySec,
            graceRemainingSeconds = 0,
            needsWarning = false,
            reason = "OWNER_ACTIVE"
        }
    end

    -- Case B: Owner is inactive, check if shielded by an active stewardship delegate
    local hasValidDelegate = (delegateCitizenId and type(delegateCitizenId) == "string" and #delegateCitizenId > 0)
    if hasValidDelegate and delegateLastActive then
        local delegateInactivitySec = math.max(0, currentTime - tonumber(delegateLastActive))
        local totalAllowedWindow = ownerThreshold + maxExtension -- e.g. 14 + 16 = 30 days

        if delegateInactivitySec <= ownerThreshold and ownerInactivitySec <= totalAllowedWindow then
            return {
                status = "delegated",
                isProtected = true,
                inactivitySeconds = ownerInactivitySec,
                delegateInactivitySeconds = delegateInactivitySec,
                graceRemainingSeconds = 0,
                needsWarning = false,
                reason = "PROTECTED_BY_ACTIVE_STEWARD"
            }
        end
    end

    -- Case C: Neither owner nor delegate is protecting the asset -> Evaluate Grace Period
    warningAt = tonumber(warningAt)
    if not warningAt or warningAt <= 0 then
        -- First time inactivity detected: trigger 72h grace period warning
        return {
            status = "grace_period",
            isProtected = false,
            inactivitySeconds = ownerInactivitySec,
            graceRemainingSeconds = gracePeriod,
            needsWarning = true,
            reason = "GRACE_PERIOD_INITIATED"
        }
    end

    local elapsedSinceWarning = math.max(0, currentTime - warningAt)
    if elapsedSinceWarning < gracePeriod then
        -- Currently in grace period
        return {
            status = "grace_period",
            isProtected = false,
            inactivitySeconds = ownerInactivitySec,
            graceRemainingSeconds = gracePeriod - elapsedSinceWarning,
            needsWarning = false,
            reason = "IN_GRACE_PERIOD"
        }
    else
        -- Grace period expired without owner or delegate activity -> Forfeited
        return {
            status = "forfeited",
            isProtected = false,
            inactivitySeconds = ownerInactivitySec,
            graceRemainingSeconds = 0,
            needsWarning = false,
            reason = "GRACE_PERIOD_EXPIRED_FORFEITURE"
        }
    end
end

-- 4. Calculate Blind-Auction Minimum Bid
-- Formulates initial starting bid as a percentage of property valuation with a statutory floor.
function Nyx.Inactivity.CalculateAuctionMinimumBid(propertyPrice, discountRatio, absoluteFloor)
    propertyPrice = math.max(0.0, tonumber(propertyPrice) or 0.0)
    discountRatio = tonumber(discountRatio) or Nyx.Inactivity.Defaults.AuctionMinBidDiscount
    absoluteFloor = tonumber(absoluteFloor) or Nyx.Inactivity.Defaults.AbsoluteMinBidFloor

    local calculated = math.floor((propertyPrice * discountRatio) * 100.0 + 0.5) / 100.0
    return math.max(absoluteFloor, calculated)
end

-- 5. Valid Inactivity State Machine Transitions
function Nyx.Inactivity.CanTransitionStatus(currentStatus, targetStatus)
    local allowed = {
        ['active'] = { ['delegated'] = true, ['grace_period'] = true, ['active'] = true },
        ['delegated'] = { ['active'] = true, ['grace_period'] = true, ['delegated'] = true },
        ['grace_period'] = { ['active'] = true, ['delegated'] = true, ['reclaimed_for_auction'] = true, ['grace_period'] = true },
        ['reclaimed_for_auction'] = { ['active'] = true, ['reclaimed_for_auction'] = true }
    }

    if not allowed[currentStatus] then return false end
    return allowed[currentStatus][targetStatus] == true
end
