--[[
    Nyxframework: nyx_factions
    File: shared/succession.lua
    Description: Pure Lua 5.4 Organization Founder Inactivity & Democratic Succession Engine.
                 Evaluates abandoned enterprise charters, selects successors by equity shares & seniority,
                 and computes closed-loop double-entry liquidation splits into the municipal treasury.
]]

Nyx = Nyx or {}
Nyx.Succession = {}

local function roundToCent(val)
    val = tonumber(val) or 0.0
    return math.floor(val * 100.0 + 0.5) / 100.0
end

Nyx.Succession.Defaults = {
    FounderInactivityThresholdSeconds = 14 * 86400,  -- 14 days (1,209,600s)
    StewardMaxExtensionSeconds = 16 * 86400,         -- +16 days extension (total 30 days = 2,592,000s)
    GracePeriodSeconds = 3 * 86400,                  -- 72 hours (259,200s)
    MunicipalMasterSplitRatio = 0.85,                -- 85% to gov:city:master
    PublicWorksSplitRatio = 0.15                     -- 15% to gov:dept:works
}

-- 1. Evaluate Founder Inactivity & Grace Period
function Nyx.Succession.EvaluateFounderStatus(currentTime, founderLastActive, delegateCitizenId, delegateLastActive, warningAt, cfg)
    cfg = cfg or Nyx.Succession.Defaults
    local founderThreshold = cfg.FounderInactivityThresholdSeconds or Nyx.Succession.Defaults.FounderInactivityThresholdSeconds
    local maxExtension = cfg.StewardMaxExtensionSeconds or Nyx.Succession.Defaults.StewardMaxExtensionSeconds
    local gracePeriod = cfg.GracePeriodSeconds or Nyx.Succession.Defaults.GracePeriodSeconds

    currentTime = tonumber(currentTime) or os.time()
    founderLastActive = tonumber(founderLastActive) or currentTime
    local founderInactivitySec = math.max(0, currentTime - founderLastActive)

    -- Case A: Founder is active
    if founderInactivitySec <= founderThreshold then
        return {
            status = "active",
            isProtected = true,
            inactivitySeconds = founderInactivitySec,
            graceRemainingSeconds = 0,
            needsWarning = false,
            reason = "FOUNDER_ACTIVE"
        }
    end

    -- Case B: Shielded by active stewardship delegate
    local hasValidDelegate = (delegateCitizenId and type(delegateCitizenId) == "string" and #delegateCitizenId > 0)
    if hasValidDelegate and delegateLastActive then
        local delegateInactivitySec = math.max(0, currentTime - tonumber(delegateLastActive))
        local totalAllowed = founderThreshold + maxExtension

        if delegateInactivitySec <= founderThreshold and founderInactivitySec <= totalAllowed then
            return {
                status = "delegated",
                isProtected = true,
                inactivitySeconds = founderInactivitySec,
                delegateInactivitySeconds = delegateInactivitySec,
                graceRemainingSeconds = 0,
                needsWarning = false,
                reason = "PROTECTED_BY_ACTIVE_STEWARD"
            }
        end
    end

    -- Case C: Unprotected, evaluate grace period
    warningAt = tonumber(warningAt)
    if not warningAt or warningAt <= 0 then
        return {
            status = "grace_period",
            isProtected = false,
            inactivitySeconds = founderInactivitySec,
            graceRemainingSeconds = gracePeriod,
            needsWarning = true,
            reason = "GRACE_PERIOD_INITIATED"
        }
    end

    local elapsedWarning = math.max(0, currentTime - warningAt)
    if elapsedWarning < gracePeriod then
        return {
            status = "grace_period",
            isProtected = false,
            inactivitySeconds = founderInactivitySec,
            graceRemainingSeconds = gracePeriod - elapsedWarning,
            needsWarning = false,
            reason = "IN_GRACE_PERIOD"
        }
    else
        return {
            status = "actionable",
            isProtected = false,
            inactivitySeconds = founderInactivitySec,
            graceRemainingSeconds = 0,
            needsWarning = false,
            reason = "GRACE_PERIOD_EXPIRED_ACTIONABLE"
        }
    end
end

-- 2. Determine Successor Candidate from Active Members
-- Ranks candidates by equity shares (descending), then wage/role seniority.
function Nyx.Succession.DetermineSuccessor(members, founderCitizenId, currentTime, activeThresholdSec)
    currentTime = tonumber(currentTime) or os.time()
    activeThresholdSec = tonumber(activeThresholdSec) or Nyx.Succession.Defaults.FounderInactivityThresholdSeconds

    if not members or type(members) ~= "table" or #members == 0 then
        return "liquidation", nil, "NO_MEMBERS_REGISTERED"
    end

    local eligible = {}
    for _, m in ipairs(members) do
        local isFounder = (m.citizen_id == founderCitizenId)
        local lastActive = tonumber(m.last_active_at) or 0
        local isActive = ((currentTime - lastActive) <= activeThresholdSec)

        if not isFounder and isActive then
            eligible[#eligible + 1] = {
                citizenId = m.citizen_id,
                roleTitle = m.role_title or "Associate",
                equityShares = tonumber(m.equity_shares) or 0.0,
                wageHourly = tonumber(m.wage_hourly) or 0.0,
                hiredAt = tonumber(m.hired_at_unix) or 0
            }
        end
    end

    if #eligible == 0 then
        return "liquidation", nil, "NO_ACTIVE_MEMBERS_REMAIN"
    end

    -- Sort: highest equity shares first; tie-breaker: highest wage; tie-breaker: oldest hired
    table.sort(eligible, function(a, b)
        if math.abs(a.equityShares - b.equityShares) > 0.001 then
            return a.equityShares > b.equityShares
        end
        if math.abs(a.wageHourly - b.wageHourly) > 0.01 then
            return a.wageHourly > b.wageHourly
        end
        return a.hiredAt < b.hiredAt
    end)

    return "succession", eligible[1], "ACTIVE_SUCCESSOR_SELECTED"
end

-- 3. Calculate Corporate Treasury Liquidation Distribution (Double-Entry Conservation)
-- Exactly splits liquidated balances between municipal master reserve and public works.
function Nyx.Succession.CalculateCharterLiquidationDistribution(treasuryBalance, masterRatio)
    treasuryBalance = math.max(0.0, roundToCent(treasuryBalance))
    if treasuryBalance <= 0.00 then
        return {
            masterAmount = 0.00,
            worksAmount = 0.00,
            totalLiquidated = 0.00
        }
    end

    masterRatio = tonumber(masterRatio) or Nyx.Succession.Defaults.MunicipalMasterSplitRatio
    masterRatio = math.max(0.0, math.min(1.0, masterRatio))

    local masterAmount = roundToCent(treasuryBalance * masterRatio)
    local worksAmount = roundToCent(treasuryBalance - masterAmount)

    return {
        masterAmount = masterAmount,
        worksAmount = worksAmount,
        totalLiquidated = treasuryBalance
    }
end
