--[[
    Nyxframework: nyx_judiciary
    File: shared/jury.lua
    Description: Pure Lua 5.4 shared algorithms for civic jury pool dispatching,
                 Fisher-Yates permutations, candidate qualification filters,
                 seat assignment matrices, and deliberation vote tabulation.
]]

Nyx = Nyx or {}
Nyx.Jury = Nyx.Jury or {}

--- Mathematically unbiased Fisher-Yates (Knuth) shuffle algorithm.
--- Guarantees an exact O(N) uniform random permutation across all N! outcomes.
--- @param list table Array of elements to shuffle (modified in-place or copied)
--- @param customRng function|nil Optional custom RNG generator(min, max) -> integer
--- @return table Shuffled array
function Nyx.Jury.FisherYatesShuffle(list, customRng)
    if not list or type(list) ~= "table" then
        return {}
    end

    local count = #list
    if count <= 1 then
        return list
    end

    for i = count, 2, -1 do
        local j
        if customRng and type(customRng) == "function" then
            j = customRng(1, i)
        else
            j = math.random(1, i)
        end
        list[i], list[j] = list[j], list[i]
    end

    return list
end

--- Evaluate online citizens against civic qualification and disqualification criteria.
--- Filters out exempt emergency/judicial professions, active warrants, case participants,
--- incarcerated citizens, and citizens within recent jury fatigue cooldown windows.
--- @param candidates table List of candidate tables { citizenId, job, source, name }
--- @param criteria table Validation criteria { exemptJobs, participants, activeWarrants, inJail, recentServed }
--- @return table eligible, table disqualified
function Nyx.Jury.FilterCandidates(candidates, criteria)
    candidates = candidates or {}
    criteria = criteria or {}

    local exemptJobs = criteria.exemptJobs or {}
    local participants = criteria.participants or {}
    local activeWarrants = criteria.activeWarrants or {}
    local inJail = criteria.inJail or {}
    local recentServed = criteria.recentServed or {}

    -- Convert array lookups to fast hash sets if necessary
    local function toSet(input)
        local s = {}
        if type(input) == "table" then
            for k, v in pairs(input) do
                if type(k) == "string" and (v == true or v == 1) then
                    s[k] = true
                elseif type(v) == "string" then
                    s[v] = true
                end
            end
        end
        return s
    end

    local exemptSet = toSet(exemptJobs)
    local partSet = toSet(participants)
    local warrantSet = toSet(activeWarrants)
    local jailSet = toSet(inJail)
    local servedSet = toSet(recentServed)

    local eligible = {}
    local disqualified = {}

    for _, cand in ipairs(candidates) do
        local cid = cand.citizenId or cand.citizen_id
        local job = cand.job or "unemployed"

        if exemptSet[job] then
            disqualified[cid] = "EXEMPT_JOB"
        elseif partSet[cid] then
            disqualified[cid] = "CASE_PARTICIPANT"
        elseif warrantSet[cid] then
            disqualified[cid] = "ACTIVE_WARRANT"
        elseif jailSet[cid] then
            disqualified[cid] = "INCARCERATED"
        elseif servedSet[cid] then
            disqualified[cid] = "RECENT_SERVICE_COOLDOWN"
        else
            table.insert(eligible, cand)
        end
    end

    return eligible, disqualified
end

--- Calculate juror dispatch requirements and evaluate democratic quorum thresholds.
--- @param eligiblePool table Filtered list of eligible candidates
--- @param requiredCount number Target total seated jurors (e.g. 5)
--- @param minQuorum number Absolute minimum seated jurors required (e.g. 3)
--- @param existingSeatedCount number Currently seated jurors
--- @return boolean success, string reason, table selected
function Nyx.Jury.CalculateDispatchPlan(eligiblePool, requiredCount, minQuorum, existingSeatedCount)
    eligiblePool = eligiblePool or {}
    requiredCount = tonumber(requiredCount) or 5
    minQuorum = tonumber(minQuorum) or 3
    existingSeatedCount = tonumber(existingSeatedCount) or 0

    local needed = math.max(0, requiredCount - existingSeatedCount)
    local totalPotential = existingSeatedCount + #eligiblePool

    if totalPotential < minQuorum then
        return false, "INSUFFICIENT_QUORUM", {}
    end

    local selected = {}
    for i = 1, math.min(needed, #eligiblePool) do
        table.insert(selected, eligiblePool[i])
    end

    return true, "DISPATCH_OK", selected
end

--- Dynamically allocate unoccupied jury box seats (Seats 1 through totalSeats).
--- Preserves existing juror seat assignments and avoids seat collisions.
--- @param currentJurors table List of juror records { citizenId, seatIndex, ... }
--- @param totalSeats number Maximum seats available in jury box (default 6)
--- @return boolean success, table|string assignedJurorsOrError
function Nyx.Jury.AssignSeats(currentJurors, totalSeats)
    currentJurors = currentJurors or {}
    totalSeats = tonumber(totalSeats) or 6

    local occupied = {}
    for _, juror in ipairs(currentJurors) do
        local sIdx = juror.seatIndex or juror.seat_index
        if sIdx and tonumber(sIdx) then
            occupied[tonumber(sIdx)] = true
        end
    end

    local nextSeat = 1
    local assigned = {}

    for _, juror in ipairs(currentJurors) do
        local jurorCopy = {}
        for k, v in pairs(juror) do jurorCopy[k] = v end

        local sIdx = jurorCopy.seatIndex or jurorCopy.seat_index
        if not sIdx then
            while occupied[nextSeat] and nextSeat <= totalSeats do
                nextSeat = nextSeat + 1
            end

            if nextSeat > totalSeats then
                return false, "NO_SEATS_AVAILABLE"
            end

            jurorCopy.seatIndex = nextSeat
            jurorCopy.seat_index = nextSeat
            occupied[nextSeat] = true
        end
        table.insert(assigned, jurorCopy)
    end

    return true, assigned
end

--- Tabulate secret ballots cast by jurors during deliberation.
--- Supports 'majority' and 'unanimous' verdict criteria.
--- @param ballots table Array of string outcomes ('guilty', 'not_guilty', 'abstain')
--- @param ruleType string 'majority' or 'unanimous'
--- @param minQuorum number Minimum votes required to form a verdict
--- @return string outcome, table tally
function Nyx.Jury.TabulateVotes(ballots, ruleType, minQuorum)
    ballots = ballots or {}
    ruleType = ruleType or "majority"
    minQuorum = tonumber(minQuorum) or 3

    local guilty = 0
    local notGuilty = 0
    local abstain = 0

    for _, b in ipairs(ballots) do
        if b == "guilty" then
            guilty = guilty + 1
        elseif b == "not_guilty" then
            notGuilty = notGuilty + 1
        elseif b == "abstain" then
            abstain = abstain + 1
        end
    end

    local totalCast = guilty + notGuilty + abstain
    local tally = {
        guilty = guilty,
        notGuilty = notGuilty,
        abstain = abstain,
        totalCast = totalCast
    }

    if totalCast < minQuorum then
        return "incomplete", tally
    end

    if ruleType == "unanimous" then
        if guilty > 0 and notGuilty == 0 and (guilty + abstain) >= minQuorum then
            return "guilty", tally
        elseif notGuilty > 0 and guilty == 0 and (notGuilty + abstain) >= minQuorum then
            return "not_guilty", tally
        elseif guilty > 0 and notGuilty > 0 then
            return "hung_jury", tally
        end
        return "incomplete", tally
    end

    -- Default: Majority Rule
    if guilty > notGuilty then
        return "guilty", tally
    elseif notGuilty > guilty then
        return "not_guilty", tally
    else
        return "hung_jury", tally
    end
end
