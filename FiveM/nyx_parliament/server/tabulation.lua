--[[
    Nyxframework: nyx_parliament
    File: server/tabulation.lua
    Description: Authoritative Instant-Runoff Voting (IRV) ranked-choice tabulation engine.
                 Integrates shared pure IRV mathematics, candidate registry qualification,
                 and persistent multi-round audit logs.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- Tabulate ranked-choice ballots for a given legislative, election, or referendum session
function Nyx.Parliament.TabulateRankedChoice(sessionId)
    local session = MySQL.single.await([[
        SELECT * FROM `nyx_parliament_sessions` WHERE `session_id` = ?
    ]], { sessionId })

    if not session then
        return nil, "SESSION_NOT_FOUND"
    end

    -- 1. Resolve Candidate/Option Pool
    local candidates = {}
    local candidateLookup = {}

    -- Check candidate table first (for popular elections)
    local candidateRows = MySQL.query.await([[
        SELECT `candidate_id`, `citizen_id`, `display_name`, `status`
        FROM `nyx_parliament_candidates`
        WHERE `session_id` = ? AND `status` = 'qualified'
    ]], { sessionId })

    -- If no candidates are qualified yet, check all nominated candidates for this session
    if not candidateRows or #candidateRows == 0 then
        candidateRows = MySQL.query.await([[
            SELECT `candidate_id`, `citizen_id`, `display_name`, `status`
            FROM `nyx_parliament_candidates`
            WHERE `session_id` = ?
        ]], { sessionId })
    end

    if candidateRows and #candidateRows > 0 then
        for _, c in ipairs(candidateRows) do
            candidates[#candidates + 1] = c.candidate_id
            candidateLookup[c.candidate_id] = c
        end
    end

    -- Fallback: If no candidate rows, inspect session metadata
    if #candidates == 0 and session.metadata then
        local meta = session.metadata
        if type(meta) == "string" then
            local ok, parsed = pcall(json.decode, meta)
            if ok and type(parsed) == "table" then meta = parsed end
        end

        if type(meta) == "table" then
            if meta.candidates and type(meta.candidates) == "table" then
                for _, c in ipairs(meta.candidates) do
                    local cid = type(c) == "table" and (c.id or c.candidate_id) or tostring(c)
                    candidates[#candidates + 1] = cid
                    candidateLookup[cid] = type(c) == "table" and c or { id = cid, name = cid }
                end
            elseif meta.options and type(meta.options) == "table" then
                for _, opt in ipairs(meta.options) do
                    local oid = type(opt) == "table" and (opt.id or opt.option_id) or tostring(opt)
                    candidates[#candidates + 1] = oid
                    candidateLookup[oid] = type(opt) == "table" and opt or { id = oid, name = oid }
                end
            end
        end
    end

    -- 2. Query Raw Ballots
    local ballotsRaw = MySQL.query.await([[
        SELECT `ballot_id`, `preferences` FROM `nyx_parliament_ballots` WHERE `session_id` = ?
    ]], { sessionId })

    if not ballotsRaw or #ballotsRaw == 0 then
        return nil, "NO_BALLOTS_SUBMITTED"
    end

    local rawBallots = {}
    for _, b in ipairs(ballotsRaw) do
        local prefs = {}
        if type(b.preferences) == "table" then
            prefs = b.preferences
        elseif type(b.preferences) == "string" and #b.preferences > 0 then
            local ok, parsed = pcall(json.decode, b.preferences)
            if ok and type(parsed) == "table" then prefs = parsed end
        end

        if #prefs > 0 then
            rawBallots[#rawBallots + 1] = prefs
        end
    end

    -- If candidate list was completely empty, infer candidates directly from valid ballots
    if #candidates == 0 then
        local seen = {}
        for _, prefs in ipairs(rawBallots) do
            for _, c in ipairs(prefs) do
                if not seen[c] then
                    seen[c] = true
                    candidates[#candidates + 1] = c
                end
            end
        end
    end

    local requiredQuorum = tonumber(session.required_quorum) or Config.DefaultQuorum or 5
    local options = {
        quorum = requiredQuorum,
        majorityThresholdPercent = Config.MajorityThresholdPercent or 50.0
    }

    -- 3. Execute Pure Instant-Runoff Voting Tabulation
    local winner, status, roundLogs, finalCounts, totalExhausted = Nyx.IRV.Tabulate(rawBallots, candidates, options)

    if not winner then
        if status == "QUORUM_NOT_MET" then
            MySQL.prepare([[
                UPDATE `nyx_parliament_sessions` SET `status` = 'invalidated' WHERE `session_id` = ?
            ]], { sessionId })
            print(string.format("^3[Nyx:Parliament] Session '%s' invalidated: Quorum failed (%d / %d required).^7",
                sessionId, #rawBallots, requiredQuorum))
        end
        return nil, status, roundLogs
    end

    -- 4. Persist Round-by-Round Tabulation Logs into Audit Ledger
    -- Clean out previous logs if re-tabulating
    MySQL.prepare.await("DELETE FROM `nyx_parliament_tabulation_logs` WHERE `session_id` = ?", { sessionId })

    for _, roundData in ipairs(roundLogs) do
        MySQL.prepare.await([[
            INSERT INTO `nyx_parliament_tabulation_logs`
                (`session_id`, `round_number`, `continuing_ballots`, `exhausted_ballots`, `tally_breakdown`, `eliminated_candidate`, `winner_declared`)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], {
            sessionId,
            roundData.round,
            roundData.continuingBallots,
            roundData.exhaustedBallots,
            json.encode(roundData.tally),
            roundData.eliminated,
            roundData.winner
        })
    end

    print(string.format("^2[Nyx:Parliament] Session '%s' IRV tabulation certified! Winner: ^3%s^7 (%s across %d rounds, %d exhausted ballots)^7",
        sessionId, winner, status, #roundLogs, totalExhausted))

    return winner, finalCounts, roundLogs, status, candidateLookup[winner]
end
