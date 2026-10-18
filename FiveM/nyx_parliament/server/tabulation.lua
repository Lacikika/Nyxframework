--[[
    Nyxframework: nyx_parliament
    File: server/tabulation.lua
    Description: Recursive Instant-Runoff Voting (IRV) ranked-choice ballot tabulation engine.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- Tabulate ranked-choice ballots for a given legislative or election session
function Nyx.Parliament.TabulateRankedChoice(sessionId)
    local session = MySQL.single.await("SELECT * FROM `nyx_parliament_sessions` WHERE `session_id` = ?", { sessionId })
    if not session then
        return nil, "SESSION_NOT_FOUND"
    end

    local ballotsRaw = MySQL.query.await("SELECT `preferences` FROM `nyx_parliament_ballots` WHERE `session_id` = ?", { sessionId })
    if not ballotsRaw or #ballotsRaw == 0 then
        return nil, "NO_BALLOTS_SUBMITTED"
    end

    local totalBallots = #ballotsRaw
    local requiredQuorum = tonumber(session.required_quorum) or Config.DefaultQuorum or 5

    -- Quorum Check
    if totalBallots < requiredQuorum then
        MySQL.prepare("UPDATE `nyx_parliament_sessions` SET `status` = 'invalidated' WHERE `session_id` = ?", { sessionId })
        print(string.format("^3[Nyx:Parliament] Session '%s' invalidated: Quorum failed (%d / %d required).^7", sessionId, totalBallots, requiredQuorum))
        return nil, "QUORUM_NOT_MET"
    end

    -- Decode Preferences Matrix
    local ballots = {}
    local activeCandidates = {}

    for _, b in ipairs(ballotsRaw) do
        local prefs = {}
        if type(b.preferences) == "table" then
            prefs = b.preferences
        elseif type(b.preferences) == "string" and #b.preferences > 0 then
            local ok, parsed = pcall(json.decode, b.preferences)
            if ok and type(parsed) == "table" then prefs = parsed end
        end

        if #prefs > 0 then
            ballots[#ballots + 1] = prefs
            for _, candidate in ipairs(prefs) do
                activeCandidates[candidate] = true
            end
        end
    end

    if #ballots == 0 then
        return nil, "NO_VALID_BALLOTS"
    end

    local majorityNeeded = math.floor(#ballots / 2) + 1
    local roundIndex = 1
    local roundLogs = {}

    -- Instant-Runoff Elimination Loop
    while true do
        local firstPrefs = {}
        for c, _ in pairs(activeCandidates) do
            firstPrefs[c] = 0
        end

        -- Tally highest available preference per ballot
        for _, prefs in ipairs(ballots) do
            for _, candidate in ipairs(prefs) do
                if activeCandidates[candidate] then
                    firstPrefs[candidate] = firstPrefs[candidate] + 1
                    break
                end
            end
        end

        roundLogs[roundIndex] = {
            round = roundIndex,
            counts = firstPrefs
        }

        local lowestCandidate = nil
        local lowestVotes = math.huge
        local highestCandidate = nil
        local highestVotes = -1

        for candidate, votes in pairs(firstPrefs) do
            if votes >= majorityNeeded then
                -- Clear majority winner crossed 50% + 1 threshold
                return candidate, firstPrefs, roundLogs
            end

            if votes > highestVotes then
                highestVotes = votes
                highestCandidate = candidate
            end

            if votes < lowestVotes then
                lowestVotes = votes
                lowestCandidate = candidate
            end
        end

        -- Check remaining candidate count
        local remainingCount = 0
        for _ in pairs(activeCandidates) do
            remainingCount = remainingCount + 1
        end

        if remainingCount <= 2 then
            -- Final round resolution
            return highestCandidate, firstPrefs, roundLogs
        end

        -- Eliminate lowest candidate and transfer their votes
        activeCandidates[lowestCandidate] = nil
        roundIndex = roundIndex + 1
    end
end
