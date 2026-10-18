--[[
    Nyxframework: nyx_parliament
    File: shared/irv.lua
    Description: Pure Lua 5.4 Instant-Runoff Voting (IRV) ranked-choice tabulation engine.
                 Deterministic, multi-round elimination, dynamic ballot exhaustion tracking,
                 and hierarchical tie-breaking.
]]

Nyx = Nyx or {}
Nyx.IRV = Nyx.IRV or {}

-- Helper: Deep clone table
local function cloneTable(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = type(v) == "table" and cloneTable(v) or v
    end
    return copy
end

-- Helper: Round numbers to precision
local function roundPercent(val, decimals)
    local mult = 10 ^ (decimals or 2)
    return math.floor(val * mult + 0.5) / mult
end

--- Sanitize a voter's ballot preference array
--- Removes candidates not in the allowed pool and eliminates internal duplicate choices
--- @param rawPreferences table Array of candidate IDs in ranked order
--- @param allowedCandidates table Set or array of allowed candidate IDs
--- @return table Clean array of unique candidate IDs in voter's ranked order
function Nyx.IRV.SanitizeBallot(rawPreferences, allowedCandidates)
    if type(rawPreferences) ~= "table" then return {} end

    local allowedSet = {}
    if type(allowedCandidates) == "table" then
        for k, v in pairs(allowedCandidates) do
            if type(k) == "string" and v == true then
                allowedSet[k] = true
            elseif type(v) == "string" then
                allowedSet[v] = true
            end
        end
    end

    local seen = {}
    local sanitized = {}

    for _, choice in ipairs(rawPreferences) do
        if type(choice) == "string" and #choice > 0 then
            if (not allowedCandidates or allowedSet[choice]) and not seen[choice] then
                seen[choice] = true
                sanitized[#sanitized + 1] = choice
            end
        end
    end

    return sanitized
end

--- Calculate total preference occurrences across all raw ballots for tie-breaking
--- @param ballots table Array of sanitized ballots
--- @param candidates table Array or set of candidates
--- @return table Map of candidateId -> { [rank] = count, totalAppearances = count }
function Nyx.IRV.BuildPreferenceMatrix(ballots, candidates)
    local matrix = {}
    for _, c in ipairs(candidates) do
        matrix[c] = { totalAppearances = 0, ranks = {} }
    end

    for _, prefs in ipairs(ballots) do
        for rank, candidate in ipairs(prefs) do
            if matrix[candidate] then
                matrix[candidate].ranks[rank] = (matrix[candidate].ranks[rank] or 0) + 1
                matrix[candidate].totalAppearances = matrix[candidate].totalAppearances + 1
            end
        end
    end

    return matrix
end

--- Execute pure Instant-Runoff Voting (Ranked Choice) Tabulation
--- @param rawBallots table Array of preference arrays: { {"c1", "c2"}, {"c2", "c3"}, ... }
--- @param candidateList table Array of candidate IDs: { "c1", "c2", "c3" }
--- @param options table Optional config: quorum, majorityThresholdPercent, tieBreaker
--- @return string|nil winner Winning candidate ID or nil if failed/quorum unmet
--- @return string status Tabulation outcome code
--- @return table roundLogs Chronological array of audit round data
--- @return table finalCounts Final round candidate vote counts
--- @return number totalExhausted Total ballots exhausted throughout tabulation
function Nyx.IRV.Tabulate(rawBallots, candidateList, options)
    options = options or {}
    local quorum = tonumber(options.quorum) or 1
    local majorityPercent = tonumber(options.majorityThresholdPercent) or 50.0

    if type(rawBallots) ~= "table" or #rawBallots == 0 then
        return nil, "NO_BALLOTS_SUBMITTED", {}, {}, 0
    end

    if type(candidateList) ~= "table" or #candidateList == 0 then
        return nil, "NO_CANDIDATES_REGISTERED", {}, {}, 0
    end

    -- Build allowed set and deduplicate candidate list
    local activeCandidates = {}
    local candidateArray = {}
    for _, c in ipairs(candidateList) do
        if type(c) == "string" and not activeCandidates[c] then
            activeCandidates[c] = true
            candidateArray[#candidateArray + 1] = c
        end
    end

    if #candidateArray == 0 then
        return nil, "INVALID_CANDIDATE_LIST", {}, {}, 0
    end

    -- Sanitize each ballot against the registered candidates
    local ballots = {}
    for _, raw in ipairs(rawBallots) do
        local clean = Nyx.IRV.SanitizeBallot(raw, activeCandidates)
        if #clean > 0 then
            ballots[#ballots + 1] = clean
        end
    end

    local totalValidBallots = #ballots
    if totalValidBallots < quorum then
        return nil, "QUORUM_NOT_MET", {}, {}, 0
    end

    -- Special case: Only 1 candidate registered and valid ballots exist
    if #candidateArray == 1 then
        local soleCandidate = candidateArray[1]
        local count = 0
        for _, b in ipairs(ballots) do
            if b[1] == soleCandidate then count = count + 1 end
        end
        local log = {
            round = 1,
            continuingBallots = totalValidBallots,
            exhaustedBallots = 0,
            majorityNeeded = 1,
            tally = { [soleCandidate] = count },
            percentages = { [soleCandidate] = 100.0 },
            highestCandidate = soleCandidate,
            highestVotes = count,
            lowestCandidate = soleCandidate,
            lowestVotes = count,
            eliminated = nil,
            winner = soleCandidate
        }
        return soleCandidate, "SINGLE_CANDIDATE", { log }, { [soleCandidate] = count }, 0
    end

    local prefMatrix = Nyx.IRV.BuildPreferenceMatrix(ballots, candidateArray)
    local roundLogs = {}
    local roundIndex = 1
    local totalExhausted = 0
    local finalCounts = {}

    -- Instant Runoff Elimination Loop
    while true do
        local tally = {}
        local activeCandidateCount = 0
        for c, _ in pairs(activeCandidates) do
            tally[c] = 0
            activeCandidateCount = activeCandidateCount + 1
        end

        local continuingBallots = 0
        local roundExhausted = 0

        -- Tally highest available preference per ballot
        for _, prefs in ipairs(ballots) do
            local voted = false
            for _, candidate in ipairs(prefs) do
                if activeCandidates[candidate] then
                    tally[candidate] = tally[candidate] + 1
                    continuingBallots = continuingBallots + 1
                    voted = true
                    break
                end
            end
            if not voted then
                roundExhausted = roundExhausted + 1
            end
        end

        totalExhausted = roundExhausted
        finalCounts = tally

        -- If all ballots exhausted or no continuing candidates have votes
        if continuingBallots == 0 then
            return nil, "DEADLOCK_NO_CONTINUING_BALLOTS", roundLogs, finalCounts, totalExhausted
        end

        -- Strict majority threshold based on continuing (non-exhausted) ballots
        local majorityNeeded = math.floor(continuingBallots * (majorityPercent / 100.0)) + 1

        -- Calculate percentages
        local percentages = {}
        for c, votes in pairs(tally) do
            percentages[c] = roundPercent((votes / continuingBallots) * 100.0, 2)
        end

        local highestCandidate = nil
        local highestVotes = -1
        local lowestCandidate = nil
        local lowestVotes = math.huge
        local lowestCandidatesList = {}

        for candidate, votes in pairs(tally) do
            if votes > highestVotes then
                highestVotes = votes
                highestCandidate = candidate
            end

            if votes < lowestVotes then
                lowestVotes = votes
                lowestCandidate = candidate
                lowestCandidatesList = { candidate }
            elseif votes == lowestVotes then
                lowestCandidatesList[#lowestCandidatesList + 1] = candidate
            end
        end

        -- Check for clear majority winner (>50% of continuing ballots)
        if highestVotes >= majorityNeeded then
            local roundLog = {
                round = roundIndex,
                continuingBallots = continuingBallots,
                exhaustedBallots = roundExhausted,
                majorityNeeded = majorityNeeded,
                tally = cloneTable(tally),
                percentages = percentages,
                highestCandidate = highestCandidate,
                highestVotes = highestVotes,
                lowestCandidate = lowestCandidate,
                lowestVotes = lowestVotes,
                eliminated = nil,
                winner = highestCandidate
            }
            roundLogs[roundIndex] = roundLog
            return highestCandidate, "WINNER_MAJORITY", roundLogs, finalCounts, totalExhausted
        end

        -- Check if only 2 candidates remain
        if activeCandidateCount <= 2 then
            local winnerCandidate = highestCandidate
            local winStatus = "FINAL_ROUND_WINNER"

            -- If tied in the final round of 2 candidates
            if #lowestCandidatesList == 2 and lowestVotes == highestVotes then
                -- Hierarchical tie-breaker:
                -- 1. Check Round 1 first preferences
                local r1Log = roundLogs[1]
                local r1VotesA = r1Log and r1Log.tally[lowestCandidatesList[1]] or 0
                local r1VotesB = r1Log and r1Log.tally[lowestCandidatesList[2]] or 0

                if r1VotesA ~= r1VotesB then
                    winnerCandidate = (r1VotesA > r1VotesB) and lowestCandidatesList[1] or lowestCandidatesList[2]
                    winStatus = "TIE_RESOLVED_ROUND1"
                else
                    -- 2. Deterministic lexicographical tie-break
                    table.sort(lowestCandidatesList)
                    winnerCandidate = lowestCandidatesList[1]
                    winStatus = "TIE_RESOLVED_LEXICOGRAPHICAL"
                end
            end

            local roundLog = {
                round = roundIndex,
                continuingBallots = continuingBallots,
                exhaustedBallots = roundExhausted,
                majorityNeeded = majorityNeeded,
                tally = cloneTable(tally),
                percentages = percentages,
                highestCandidate = highestCandidate,
                highestVotes = highestVotes,
                lowestCandidate = lowestCandidate,
                lowestVotes = lowestVotes,
                eliminated = nil,
                winner = winnerCandidate
            }
            roundLogs[roundIndex] = roundLog
            return winnerCandidate, winStatus, roundLogs, finalCounts, totalExhausted
        end

        -- Resolve lowest candidate elimination (3+ candidates remain)
        local toEliminate = lowestCandidate
        if #lowestCandidatesList > 1 then
            -- Tie for lowest candidate:
            -- 1. Check previous round votes (if round > 1)
            local resolved = false
            if roundIndex > 1 then
                local prevLog = roundLogs[roundIndex - 1]
                local minPrevVotes = math.huge
                local prevLowest = nil
                local prevTied = false

                for _, tiedCand in ipairs(lowestCandidatesList) do
                    local prevV = prevLog.tally[tiedCand] or 0
                    if prevV < minPrevVotes then
                        minPrevVotes = prevV
                        prevLowest = tiedCand
                        prevTied = false
                    elseif prevV == minPrevVotes then
                        prevTied = true
                    end
                end

                if prevLowest and not prevTied then
                    toEliminate = prevLowest
                    resolved = true
                end
            end

            -- 2. Check total secondary preferences across original ballots
            if not resolved then
                local minSecondary = math.huge
                local secondaryLowest = nil
                local secondaryTied = false

                for _, tiedCand in ipairs(lowestCandidatesList) do
                    local appearances = prefMatrix[tiedCand] and prefMatrix[tiedCand].totalAppearances or 0
                    if appearances < minSecondary then
                        minSecondary = appearances
                        secondaryLowest = tiedCand
                        secondaryTied = false
                    elseif appearances == minSecondary then
                        secondaryTied = true
                    end
                end

                if secondaryLowest and not secondaryTied then
                    toEliminate = secondaryLowest
                    resolved = true
                end
            end

            -- 3. Fallback: Deterministic lexicographical tie-break
            if not resolved then
                table.sort(lowestCandidatesList)
                toEliminate = lowestCandidatesList[#lowestCandidatesList] -- eliminate last alphabetically
            end
        end

        -- Record round log
        local roundLog = {
            round = roundIndex,
            continuingBallots = continuingBallots,
            exhaustedBallots = roundExhausted,
            majorityNeeded = majorityNeeded,
            tally = cloneTable(tally),
            percentages = percentages,
            highestCandidate = highestCandidate,
            highestVotes = highestVotes,
            lowestCandidate = lowestCandidate,
            lowestVotes = lowestVotes,
            eliminated = toEliminate,
            winner = nil
        }
        roundLogs[roundIndex] = roundLog

        -- Eliminate lowest candidate and trigger next round
        activeCandidates[toEliminate] = nil
        roundIndex = roundIndex + 1

        -- Safety guard against infinite loops
        if roundIndex > 50 then
            return highestCandidate, "SAFETY_MAX_ROUNDS_REACHED", roundLogs, finalCounts, totalExhausted
        end
    end
end
