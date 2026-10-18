--[[
    Nyxframework: nyx_factions
    File: shared/unions.lua
    Description: Pure Lua 5.4 deterministic algorithms for trade union dues checkoffs,
                 strike fund runway projections, CBA wage floor compliance,
                 democratic strike authorization votes, and binding arbitration awards.
]]

Nyx = Nyx or {}
Nyx.Unions = Nyx.Unions or {}

-- 1. Dues Checkoff Arithmetic
-- Computes integer-cent exact deduction for flat or percentage dues modes.
-- Invariants: 0 <= dues <= grossWage, netWage = grossWage - dues.
function Nyx.Unions.CalculateDuesCheckoff(grossWage, duesMode, duesAmount, duesRate)
    grossWage = math.max(0.0, math.floor((tonumber(grossWage) or 0.0) * 100) / 100)
    local dues = 0.0

    if duesMode == "percentage" then
        local rate = tonumber(duesRate) or 0.025
        rate = math.max(0.0, math.min(0.20, rate))
        dues = math.floor((grossWage * rate) * 100) / 100
    else
        local amount = tonumber(duesAmount) or 50.00
        amount = math.max(0.0, math.floor(amount * 100) / 100)
        dues = math.min(grossWage, amount)
    end

    local netWage = math.floor((grossWage - dues) * 100) / 100
    return dues, netWage
end

-- 2. Strike Fund Runway Modeling
-- Projects days of strike relief runway given strike fund liquidity and member count.
function Nyx.Unions.CalculateStrikeFundRunway(strikeFundBalance, memberCount, strikePayRate)
    local balance = math.max(0.0, math.floor((tonumber(strikeFundBalance) or 0.0) * 100) / 100)
    local members = math.max(0, math.floor(tonumber(memberCount) or 0))
    local payRate = math.max(0.0, math.floor((tonumber(strikePayRate) or 150.00) * 100) / 100)

    if members == 0 or payRate == 0.0 then
        return {
            balance = balance,
            daily_burn = 0.00,
            runway_days = 9999,
            solvency_status = "SOLVENT"
        }
    end

    local dailyBurn = math.floor((members * payRate) * 100) / 100
    local runwayDays = 9999
    if dailyBurn > 0.0 then
        runwayDays = math.floor(balance / dailyBurn)
    end

    local status = "SOLVENT"
    if balance <= 0.0 then
        status = "DEPLETED"
    elseif runwayDays <= 5 then
        status = "WARNING"
    end

    return {
        balance = balance,
        daily_burn = dailyBurn,
        runway_days = runwayDays,
        solvency_status = status
    }
end

-- 3. CBA Wage Floor Compliance Evaluator
-- Checks if an offered/paid wage meets or exceeds the guaranteed CBA floor.
function Nyx.Unions.EvaluateWageCompliance(actualWage, wageFloor)
    actualWage = math.max(0.0, math.floor((tonumber(actualWage) or 0.0) * 100) / 100)
    wageFloor = math.max(0.0, math.floor((tonumber(wageFloor) or 0.0) * 100) / 100)

    local isCompliant = (actualWage >= wageFloor)
    local deficit = 0.00
    local deficitPct = 0.00

    if not isCompliant and wageFloor > 0.0 then
        deficit = math.floor((wageFloor - actualWage) * 100) / 100
        deficitPct = math.floor(((deficit / wageFloor) * 100) * 100) / 100
    end

    return {
        is_compliant = isCompliant,
        actual_wage = actualWage,
        wage_floor = wageFloor,
        hourly_deficit = deficit,
        deficit_percentage = deficitPct
    }
end

-- 4. Democratic Strike Authorization Vote Evaluator
-- Validates eligible quorum (default >= 50%) and majority threshold (>= 50% + 1 of cast active votes).
function Nyx.Unions.EvaluateStrikeVote(totalEligibleMembers, votes, quorumPct, majorityPct)
    local eligible = math.max(1, math.floor(tonumber(totalEligibleMembers) or 1))
    quorumPct = tonumber(quorumPct) or 0.50
    majorityPct = tonumber(majorityPct) or 0.50

    local yesCount = 0
    local noCount = 0
    local abstainCount = 0

    if type(votes) == "table" then
        for _, v in ipairs(votes) do
            local choice = string.lower(tostring(type(v) == "table" and v.vote or v))
            if choice == "yes" then
                yesCount = yesCount + 1
            elseif choice == "no" then
                noCount = noCount + 1
            else
                abstainCount = abstainCount + 1
            end
        end
    end

    local totalCast = yesCount + noCount + abstainCount
    local quorumRequired = math.ceil(eligible * quorumPct)
    local quorumReached = (totalCast >= quorumRequired)

    local activeVotes = yesCount + noCount
    local majorityRequired = (activeVotes > 0) and (math.floor(activeVotes * majorityPct) + 1) or 1
    local majorityReached = (activeVotes > 0) and (yesCount >= majorityRequired)

    local passed = (quorumReached and majorityReached)

    return {
        passed = passed,
        eligible = eligible,
        total_cast = totalCast,
        quorum_required = quorumRequired,
        quorum_reached = quorumReached,
        yes_count = yesCount,
        no_count = noCount,
        abstain_count = abstainCount,
        majority_required = majorityRequired,
        majority_reached = majorityReached
    }
end

-- 5. Strike Pay Disbursement Cooldown Guard
function Nyx.Unions.CanClaimStrikePay(lastClaimTimestamp, currentTimestamp, cooldownSeconds)
    local last = tonumber(lastClaimTimestamp) or 0
    local now = tonumber(currentTimestamp) or os.time()
    local cooldown = tonumber(cooldownSeconds) or 86400

    if last <= 0 then
        return true, 0
    end

    local elapsed = now - last
    if elapsed >= cooldown then
        return true, 0
    end

    return false, (cooldown - elapsed)
end

-- 6. Binding Labor Arbitration Damages & Penalty Calculator
function Nyx.Unions.CalculateArbitrationAward(underpaidHours, hourlyDeficit, affectedMemberCount, penaltyRate)
    local hours = math.max(0.0, tonumber(underpaidHours) or 0.0)
    local deficit = math.max(0.0, math.floor((tonumber(hourlyDeficit) or 0.0) * 100) / 100)
    local members = math.max(1, math.floor(tonumber(affectedMemberCount) or 1))
    local rate = math.max(0.0, tonumber(penaltyRate) or 0.10)

    local perMemberRestitution = math.floor((hours * deficit) * 100) / 100
    local totalRestitution = math.floor((perMemberRestitution * members) * 100) / 100
    local statutoryPenalty = math.floor((totalRestitution * rate) * 100) / 100
    local totalAward = math.floor((totalRestitution + statutoryPenalty) * 100) / 100

    return {
        per_member_restitution = perMemberRestitution,
        total_restitution = totalRestitution,
        statutory_penalty = statutoryPenalty,
        total_award = totalAward,
        affected_member_count = members
    }
end
