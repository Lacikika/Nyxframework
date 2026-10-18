--[[
    Nyxframework: nyx_parliament
    File: server/voting.lua
    Description: Tamper-proof ballot submission pipeline, hardware token verification,
                 physical voting booth terminal provenance, and cryptographic receipt generation.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- Helper: Retrieve deterministic hardware identity hash
local function getClientHwidHash(src)
    local tokens = {}
    local numTokens = GetNumPlayerTokens and GetNumPlayerTokens(tostring(src)) or 0
    if numTokens > 0 then
        for i = 0, numTokens - 1 do
            tokens[#tokens + 1] = GetPlayerToken(tostring(src), i)
        end
    end

    local identifiers = GetPlayerIdentifiers and GetPlayerIdentifiers(tostring(src)) or {}
    return Nyx.DemocraticElections.GenerateHardwareFootprintHash(identifiers, tokens, src)
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
                officeId = r.office_id,
                electionPhase = r.election_phase or "voting",
                startsAt = r.starts_at,
                nominationEndsAt = r.nomination_ends_at,
                endsAt = r.ends_at,
                totalTurnout = r.total_turnout or 0,
                metadata = meta
            }
        end
    end

    return sessions
end)

-- RPC: Cast Tamper-Proof Ranked-Choice Ballot
Nyx.RPC.Register("parliament:castBallot", function(src, sessionId, rankedChoices, boothId, boothLabel)
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

    -- Check Election Phase (cannot vote during candidate nomination phase)
    if session.election_phase and session.election_phase == "nomination" then
        return { success = false, error = "VOTING_PERIOD_NOT_OPEN" }
    end

    -- 2. Physical Booth Proximity & Attribution
    local bId = boothId or "remote"
    local bLabel = boothLabel or "Remote Terminal"

    if Config.EnforceBoothProximity then
        local ped = GetPlayerPed(tostring(src))
        if ped and DoesEntityExist(ped) then
            local coords = GetEntityCoords(ped)
            local prox = Nyx.DemocraticElections.ValidateBoothProximity(coords, Config.Booths, Config.BoothInteractDistance or 2.5)
            if not prox.isNear then
                return { success = false, error = "NOT_AT_VOTING_BOOTH", distance = prox.distance }
            end
            bId = prox.boothId or bId
            bLabel = prox.boothLabel or bLabel
        end
    end

    -- 3. Anti-Sybil / Double Voting Prevention via Hardware Token
    local hwidHash = getClientHwidHash(src)
    local alreadyVoted = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_parliament_voter_registry` 
        WHERE `session_id` = ? AND `hardware_hash` = ?
    ]], { sessionId, hwidHash })

    if alreadyVoted > 0 then
        return { success = false, error = "ALREADY_VOTED" }
    end

    -- 4. Ballot Choices Sanitization (no duplicate candidates)
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

    -- 5. Generate Anonymized Verification Receipt Hash
    local receiptHash = string.format("NYX-BALLOT-%s", Nyx.RPC.GenerateNonce():sub(1, 12):upper())

    -- 6. Commit Voter Participation and Anonymized Ballot in Transaction
    local success = MySQL.transaction.await({
        {
            query = "INSERT INTO `nyx_parliament_voter_registry` (`session_id`, `hardware_hash`) VALUES (?, ?)",
            values = { sessionId, hwidHash }
        },
        {
            query = "INSERT INTO `nyx_parliament_ballots` (`session_id`, `ballot_hash`, `preferences`, `booth_id`, `booth_label`) VALUES (?, ?, ?, ?, ?)",
            values = { sessionId, receiptHash, json.encode(sanitizedPreferences), bId, bLabel }
        },
        {
            query = "UPDATE `nyx_parliament_sessions` SET `total_turnout` = `total_turnout` + 1 WHERE `session_id` = ?",
            values = { sessionId }
        }
    })

    if not success then
        return { success = false, error = "TRANSACTION_COMMIT_FAILED" }
    end

    -- Update booth station stats if cast at a certified station
    pcall(function()
        if bId ~= "remote" then
            MySQL.prepare.await([[
                UPDATE `nyx_parliament_booth_terminals`
                SET `total_ballots_cast` = `total_ballots_cast` + 1, `last_ping_at` = CURRENT_TIMESTAMP
                WHERE `booth_id` = ?
            ]], { bId })
        end
    end)

    if Config.Debug then
        print(string.format("^2[Nyx:Parliament] Ballot cast in session '%s' at '%s' (Receipt: %s)^7",
            sessionId, bLabel, receiptHash))
    end

    return {
        success = true,
        receiptHash = receiptHash,
        boothId = bId,
        boothLabel = bLabel
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
        SELECT `ballot_id`, `submitted_at`, `booth_id`, `booth_label` FROM `nyx_parliament_ballots` 
        WHERE `session_id` = ? AND `ballot_hash` = ?
    ]], { sessionId, receiptHash })

    if ballot then
        return {
            verified = true,
            submittedAt = ballot.submitted_at,
            boothId = ballot.booth_id,
            boothLabel = ballot.booth_label
        }
    end

    return { verified = false }
end)
