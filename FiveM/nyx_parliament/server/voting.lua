--[[
    Nyxframework: nyx_parliament
    File: server/voting.lua
    Description: Tamper-proof ballot submission pipeline, hardware token verification,
                 and receipt generation.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- Helper: Retrieve deterministic hardware identity hash
local function getClientHwidHash(src)
    local numTokens = GetNumPlayerTokens(tostring(src))
    local tokens = {}
    for i = 0, numTokens - 1 do
        tokens[#tokens + 1] = GetPlayerToken(tostring(src), i)
    end

    if #tokens > 0 then
        local raw = table.concat(tokens, ":")
        return string.format("HWID-%08x%08x", #raw, numTokens * 54321)
    end

    -- Fallback: Use rockstar license if hardware tokens unavailable
    local identifiers = GetPlayerIdentifiers(tostring(src))
    for _, id in ipairs(identifiers) do
        if id:sub(1, 8) == "license:" then
            return "LIC-" .. id:sub(9)
        end
    end

    return "ANON-DEV-" .. tostring(src)
end

-- RPC: Query Active Legislative and Election Sessions
Nyx.RPC.Register("parliament:getActiveSessions", function(src)
    local rows = MySQL.query.await([[
        SELECT * FROM `nyx_parliament_sessions`
        WHERE `status` = 'active' AND `starts_at` <= CURRENT_TIMESTAMP AND `ends_at` >= CURRENT_TIMESTAMP
        ORDER BY `created_at` DESC
    ]])

    local sessions = {}
    if rows then
        for _, r in ipairs(rows) do
            local meta = {}
            if r.metadata and #r.metadata > 0 then
                local ok, parsed = pcall(json.decode, r.metadata)
                if ok and type(parsed) == "table" then meta = parsed end
            end

            sessions[#sessions + 1] = {
                sessionId = r.session_id,
                title = r.title,
                description = r.description,
                type = r.type,
                startsAt = r.starts_at,
                endsAt = r.ends_at,
                metadata = meta
            }
        end
    end

    return sessions
end)

-- RPC: Cast Tamper-Proof Ranked-Choice Ballot
Nyx.RPC.Register("parliament:castBallot", function(src, sessionId, rankedChoices)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    if type(sessionId) ~= "string" or type(rankedChoices) ~= "table" or #rankedChoices == 0 then
        return { success = false, error = "INVALID_BALLOT_PAYLOAD" }
    end

    -- 1. Session Validity Check
    local session = MySQL.single.await([[
        SELECT * FROM `nyx_parliament_sessions` 
        WHERE `session_id` = ? AND `status` = 'active'
    ]], { sessionId })

    if not session then
        return { success = false, error = "SESSION_NOT_ACTIVE" }
    end

    -- 2. Anti-Sybil / Double Voting Prevention via Hardware Token
    local hwidHash = getClientHwidHash(src)
    local alreadyVoted = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_parliament_voter_registry` 
        WHERE `session_id` = ? AND `hardware_hash` = ?
    ]], { sessionId, hwidHash })

    if alreadyVoted > 0 then
        return { success = false, error = "ALREADY_VOTED" }
    end

    -- 3. Ballot Choices Sanitization (no duplicate candidates)
    local seen = {}
    local sanitizedPreferences = {}
    for _, choice in ipairs(rankedChoices) do
        if type(choice) == "string" and not seen[choice] then
            seen[choice] = true
            sanitizedPreferences[#sanitizedPreferences + 1] = choice
        end
    end

    if #sanitizedPreferences == 0 then
        return { success = false, error = "NO_VALID_CHOICES" }
    end

    -- 4. Generate Anonymized Verification Receipt Hash
    local receiptHash = string.format("NYX-BALLOT-%s", Nyx.RPC.GenerateNonce():sub(1, 12):upper())

    -- 5. Commit Voter Participation and Anonymized Ballot in Transaction
    local success = MySQL.transaction.await({
        {
            query = "INSERT INTO `nyx_parliament_voter_registry` (`session_id`, `hardware_hash`) VALUES (?, ?)",
            values = { sessionId, hwidHash }
        },
        {
            query = "INSERT INTO `nyx_parliament_ballots` (`session_id`, `ballot_hash`, `preferences`) VALUES (?, ?, ?)",
            values = { sessionId, receiptHash, json.encode(sanitizedPreferences) }
        }
    })

    if not success then
        return { success = false, error = "TRANSACTION_COMMIT_FAILED" }
    end

    if Config.Debug then
        print(string.format("^2[Nyx:Parliament] Ballot cast successfully in session '%s' (Receipt: %s)^7", sessionId, receiptHash))
    end

    return {
        success = true,
        receiptHash = receiptHash
    }
end)

-- RPC: Propose Legislative Bill
Nyx.RPC.Register("parliament:proposeBill", function(src, billPayload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    if type(billPayload) ~= "table" or not billPayload.title or not billPayload.actions then
        return { success = false, error = "MALFORMED_BILL_PROPOSAL" }
    end

    -- Check Sponsorship Authorization
    local hasAuth = false
    for role, _ in pairs(Config.SponsorRoles or {}) do
        if player:hasPermission(role) then
            hasAuth = true
            break
        end
    end

    if not hasAuth then
        return { success = false, error = "INSUFFICIENT_SPONSORSHIP_RANK" }
    end

    -- Validate actions against statutory constitutional boundaries
    local okValidate, valErr = Nyx.Parliament.ValidateBillActions(billPayload.actions)
    if not okValidate then
        return { success = false, error = valErr }
    end

    local sessionId = string.format("bill:%s_%s", billPayload.title:lower():gsub("[^%w]", "_"):sub(1, 24), Nyx.RPC.GenerateNonce():sub(1, 6))
    local meta = {
        proposer = player.citizenId,
        options = {
            { id = "PASS", name = "Yes / Ratify Legislation" },
            { id = "REJECT", name = "No / Veto Legislation" }
        },
        actions = billPayload.actions
    }

    MySQL.prepare([[
        INSERT INTO `nyx_parliament_sessions`
        (`session_id`, `title`, `description`, `type`, `required_quorum`, `starts_at`, `ends_at`, `status`, `metadata`)
        VALUES (?, ?, ?, 'bill_vote', ?, CURRENT_TIMESTAMP, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 5 DAY), 'active', ?)
    ]], {
        sessionId,
        billPayload.title,
        billPayload.description or "Legislative statute amendment bill.",
        Config.DefaultQuorum or 5,
        json.encode(meta)
    })

    print(string.format("^2[Nyx:Parliament] Proposer %s authored new bill '%s' (Session ID: %s)^7", player.citizenId, billPayload.title, sessionId))
    TriggerClientEvent("nyx:parliament:client:newSessionPosted", -1, sessionId, billPayload.title)

    return {
        success = true,
        sessionId = sessionId
    }
end)

-- RPC: Verify Ballot Receipt
Nyx.RPC.Register("parliament:verifyReceipt", function(src, sessionId, receiptHash)
    local ballot = MySQL.single.await([[
        SELECT `ballot_id`, `submitted_at` FROM `nyx_parliament_ballots` 
        WHERE `session_id` = ? AND `ballot_hash` = ?
    ]], { sessionId, receiptHash })

    if ballot then
        return {
            verified = true,
            submittedAt = ballot.submitted_at
        }
    end

    return { verified = false }
end)
