--[[
    Nyxframework: nyx_parliament
    File: shared/campaign_finance.lua
    Description: Pure deterministic Lua formulas for campaign finance donation caps,
                 PAC statutory compliance auditing, and Citizen OS mobile opinion poll sentiment calculation.
]]

Nyx = Nyx or {}
Nyx.CampaignFinance = Nyx.CampaignFinance or {}

-- 1. Evaluate Campaign Finance Donation Cap & Compliance Status
function Nyx.CampaignFinance.EvaluateDonationEligibility(donorCitizenId, donorPriorTotal, donationAmount, statutoryCap, isFactionDonation)
    local cap = tonumber(statutoryCap) or 5000.00
    local prior = tonumber(donorPriorTotal) or 0.0
    local amt = tonumber(donationAmount) or 0.0

    if amt <= 0.0 then
        return false, "INVALID_DONATION_AMOUNT", {
            allowedAmount = 0.0,
            excessAmount = 0.0,
            remainingCap = math.max(0.0, cap - prior),
            complianceStatus = "invalid"
        }
    end

    local remainingCap = math.max(0.0, cap - prior)

    if prior >= cap then
        return false, "STATUTORY_CAP_EXCEEDED", {
            allowedAmount = 0.0,
            excessAmount = amt,
            remainingCap = 0.0,
            complianceStatus = "flagged_over_cap"
        }
    end

    if (prior + amt) > cap then
        local allowed = remainingCap
        local excess = amt - remainingCap
        return true, "CAP_EXCEEDED_PARTIAL", {
            allowedAmount = allowed,
            excessAmount = excess,
            remainingCap = 0.0,
            complianceStatus = "flagged_over_cap"
        }
    end

    return true, "COMPLIANT", {
        allowedAmount = amt,
        excessAmount = 0.0,
        remainingCap = math.max(0.0, cap - (prior + amt)),
        complianceStatus = "compliant"
    }
end

-- 2. Calculate PAC Audit Summary & Statutory Fine Assessment
function Nyx.CampaignFinance.CalculatePACAuditSummary(donationsList, statutoryCap, fineMultiplier)
    local mult = tonumber(fineMultiplier) or 1.5
    local cap = tonumber(statutoryCap) or 5000.00

    local totalContributions = 0.0
    local compliantContributions = 0.0
    local flaggedExcessAmount = 0.0
    local flaggedCount = 0
    local totalCount = 0

    if type(donationsList) == "table" then
        for _, don in ipairs(donationsList) do
            totalCount = totalCount + 1
            local amt = tonumber(don.amount) or 0.0
            totalContributions = totalContributions + amt

            if don.compliance_status == "flagged_over_cap" or (don.amount and tonumber(don.amount) > cap) then
                flaggedCount = flaggedCount + 1
                local excess = math.max(0.0, amt - cap)
                flaggedExcessAmount = flaggedExcessAmount + excess
            else
                compliantContributions = compliantContributions + amt
            end
        end
    end

    local fineAssessed = flaggedExcessAmount * mult
    local auditStatus = "passed"
    if flaggedExcessAmount > 0.0 then
        auditStatus = "fines_assessed"
    end

    local riskScore = 0.0
    if totalContributions > 0.0 then
        riskScore = math.min(100.0, (flaggedExcessAmount / totalContributions) * 100.0)
    end

    return {
        totalContributions = totalContributions,
        compliantContributions = compliantContributions,
        flaggedExcessAmount = flaggedExcessAmount,
        fineAssessed = fineAssessed,
        flaggedCount = flaggedCount,
        totalCount = totalCount,
        auditStatus = auditStatus,
        riskScore = riskScore
    }
end

-- 3. Calculate Citizen OS Mobile Poll Voter Sentiment & Margin of Error
function Nyx.CampaignFinance.CalculatePollSentiment(pollOptions, responseCounts, totalTurnout)
    local total = tonumber(totalTurnout) or 0
    local optionsMap = {}
    local breakdown = {}
    local leadingOption = nil
    local maxVotes = -1

    if type(pollOptions) == "string" then
        local ok, parsed = pcall(json.decode, pollOptions)
        if ok and type(parsed) == "table" then
            pollOptions = parsed
        else
            pollOptions = {}
        end
    end

    responseCounts = responseCounts or {}

    for _, opt in ipairs(pollOptions or {}) do
        local optId = type(opt) == "table" and (opt.id or opt.value) or tostring(opt)
        local optLabel = type(opt) == "table" and (opt.label or opt.name or optId) or tostring(opt)
        local count = tonumber(responseCounts[optId]) or 0

        local pct = total > 0 and ((count / total) * 100.0) or 0.0

        if count > maxVotes then
            maxVotes = count
            leadingOption = optId
        end

        breakdown[optId] = {
            id = optId,
            label = optLabel,
            count = count,
            percentage = math.floor(pct * 100 + 0.5) / 100
        }
    end

    -- Margin of Error formula: 1.96 * sqrt(0.25 / N) * 100
    local marginOfError = 0.0
    if total > 0 then
        marginOfError = math.floor((1.96 * math.sqrt(0.25 / total) * 100.0) * 100 + 0.5) / 100
    end

    return {
        totalTurnout = total,
        leadingOption = leadingOption,
        breakdown = breakdown,
        marginOfErrorPercent = marginOfError
    }
end
