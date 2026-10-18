--[[
    Nyxframework: nyx_parliament
    File: server/elections.lua
    Description: Candidate registration, endorsement ledger, collateral escrow,
                 official instatement, and recall referendum petitions.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- 1. Register Candidate for an Election Session
function Nyx.Parliament.RegisterCandidate(src, sessionId, displayName, party, platform, slogan)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    if type(sessionId) ~= "string" then
        return { success = false, error = "INVALID_SESSION_ID" }
    end

    local okVal, sanitized, valErr = Nyx.ParliamentUI.ValidateCandidatePayload({
        displayName = displayName,
        party = party,
        platform = platform,
        slogan = slogan
    })

    if not okVal then
        return { success = false, error = valErr or "INVALID_CANDIDATE_DATA" }
    end

    displayName = sanitized.displayName
    party = sanitized.party
    platform = sanitized.platform
    slogan = sanitized.slogan

    -- Verify session exists and is accepting candidates
    local session = MySQL.single.await([[
        SELECT `session_id`, `title`, `type`, `status`, `metadata`
        FROM `nyx_parliament_sessions`
        WHERE `session_id` = ?
    ]], { sessionId })

    if not session then
        return { success = false, error = "SESSION_NOT_FOUND" }
    end

    if session.type ~= "election" then
        return { success = false, error = "SESSION_NOT_AN_ELECTION" }
    end

    if session.status ~= "active" and session.status ~= "scheduled" then
        return { success = false, error = "SESSION_NOT_OPEN" }
    end

    -- Check candidate ceiling
    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_parliament_candidates` WHERE `session_id` = ?
    ]], { sessionId }) or 0

    if count >= (Config.MaxCandidatesPerSession or 10) then
        return { success = false, error = "MAX_CANDIDATES_REACHED" }
    end

    -- Check if already registered
    local citId = player.citizenId
    local existing = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_parliament_candidates` 
        WHERE `session_id` = ? AND `citizen_id` = ?
    ]], { sessionId, citId }) or 0

    if existing > 0 then
        return { success = false, error = "ALREADY_REGISTERED_AS_CANDIDATE" }
    end

    -- Process collateral deposit via nyx_treasury
    local collateral = Config.CandidateCollateral or 2500.00
    if collateral > 0 then
        local debitAccount = "char:" .. citId .. ":bank"
        local treasuryAccount = "gov:city:master"
        local balance = exports['nyx_treasury']:GetAccountBalance(debitAccount) or 0.0

        if balance < collateral then
            return { success = false, error = "INSUFFICIENT_COLLATERAL_FUNDS", required = collateral }
        end

        local okTransfer, transferErr = exports['nyx_treasury']:ExecuteTransfer(
            debitAccount,
            treasuryAccount,
            collateral,
            "election_collateral",
            "parliament:" .. sessionId,
            string.format("Electoral Candidacy Collateral: %s for %s", citId, session.title),
            0.0
        )

        if not okTransfer then
            return { success = false, error = "COLLATERAL_ESCROW_FAILED", detail = transferErr }
        end
    end

    local candidateId = string.format("cand_%s_%s", citId, sessionId:gsub("[^%w]", ""):sub(1, 16))
    local partyAffiliation = party or "Independent"
    local platformSummary = platform or "Civil platform for municipal progress."
    local initialStatus = (Config.RequiredEndorsements or 3) == 0 and "qualified" or "nominated"

    local inserted = MySQL.insert.await([[
        INSERT INTO `nyx_parliament_candidates`
            (`candidate_id`, `session_id`, `citizen_id`, `display_name`, `party_affiliation`, `campaign_slogan`, `platform_summary`, `collateral_deposited`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        candidateId,
        sessionId,
        citId,
        displayName,
        partyAffiliation,
        slogan or "",
        platformSummary,
        collateral,
        initialStatus
    })

    if not inserted then
        return { success = false, error = "DATABASE_INSERTION_FAILED" }
    end

    print(string.format("^2[Nyx:Parliament] Citizen %s registered as candidate '%s' for session '%s' (Status: %s)^7",
        citId, displayName, sessionId, initialStatus))

    TriggerClientEvent("nyx:core:client:notify", src,
        string.format("ELECTION: Candidacy filed for '%s'. Gather %d citizen endorsements to qualify for the ballot.",
            session.title, Config.RequiredEndorsements or 3),
        "success"
    )

    return {
        success = true,
        candidateId = candidateId,
        status = initialStatus,
        collateral = collateral
    }
end

-- 2. Endorse Candidate
function Nyx.Parliament.EndorseCandidate(src, candidateId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    if not candidateId or type(candidateId) ~= "string" then
        return { success = false, error = "INVALID_CANDIDATE_ID" }
    end

    local candidate = MySQL.single.await([[
        SELECT * FROM `nyx_parliament_candidates` WHERE `candidate_id` = ?
    ]], { candidateId })

    if not candidate then
        return { success = false, error = "CANDIDATE_NOT_FOUND" }
    end

    local endorserCitId = player.citizenId

    -- Self-endorsement prevention
    if candidate.citizen_id == endorserCitId then
        return { success = false, error = "CANNOT_ENDORSE_SELF" }
    end

    -- Duplicate endorsement check
    local alreadyEndorsed = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_parliament_candidate_endorsements`
        WHERE `candidate_id` = ? AND `citizen_id` = ?
    ]], { candidateId, endorserCitId }) or 0

    if alreadyEndorsed > 0 then
        return { success = false, error = "ALREADY_ENDORSED" }
    end

    -- Insert endorsement
    local ok = MySQL.insert.await([[
        INSERT INTO `nyx_parliament_candidate_endorsements` (`candidate_id`, `citizen_id`)
        VALUES (?, ?)
    ]], { candidateId, endorserCitId })

    if not ok then
        return { success = false, error = "ENDORSEMENT_FAILED" }
    end

    local newCount = (candidate.endorsements_count or 0) + 1
    local reqEndorsements = Config.RequiredEndorsements or 3
    local qualified = newCount >= reqEndorsements
    local newStatus = qualified and "qualified" or candidate.status

    MySQL.prepare([[
        UPDATE `nyx_parliament_candidates`
        SET `endorsements_count` = ?, `status` = ?
        WHERE `candidate_id` = ?
    ]], { newCount, newStatus, candidateId })

    if qualified and candidate.status ~= "qualified" then
        print(string.format("^2[Nyx:Parliament] Candidate '%s' reached endorsement threshold (%d/%d) and is now QUALIFIED!^7",
            candidate.display_name, newCount, reqEndorsements))
    end

    return {
        success = true,
        endorsementsCount = newCount,
        qualified = qualified,
        status = newStatus
    }
end

-- 3. Instate Official following Election Concluded with Winner
function Nyx.Parliament.InstateOfficial(officeId, citizenId, displayName, sessionId)
    if not officeId or not citizenId then return false, "INVALID_OFFICIAL_PARAMETERS" end

    local officeInfo = Config.Offices and Config.Offices[officeId] or {
        title = "Municipal Official",
        termDays = 30
    }

    local termDays = officeInfo.termDays or Config.OfficialTermDays or 30

    MySQL.prepare.await([[
        INSERT INTO `nyx_parliament_officials`
            (`office_id`, `title`, `citizen_id`, `display_name`, `elected_session_id`, `term_start`, `term_end`, `status`)
        VALUES
            (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? DAY), 'active')
        ON DUPLICATE KEY UPDATE
            `citizen_id` = VALUES(`citizen_id`),
            `display_name` = VALUES(`display_name`),
            `elected_session_id` = VALUES(`elected_session_id`),
            `term_start` = CURRENT_TIMESTAMP,
            `term_end` = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? DAY),
            `status` = 'active'
    ]], {
        officeId,
        officeInfo.title,
        citizenId,
        displayName or "Elected Citizen",
        sessionId,
        termDays,
        termDays
    })

    print(string.format("^2[Nyx:Parliament] Instated citizen %s as %s (%s) for %d-day term.^7",
        citizenId, officeInfo.title, officeId, termDays))

    -- Synchronize player metadata / state bag if online
    local targetPlayer = exports['nyx_core']:GetPlayerByCitizenId(citizenId)
    if targetPlayer then
        targetPlayer:setMetadata("parliamentOffice", officeId)
        Player(targetPlayer.source).state.parliamentOffice = officeId
        TriggerClientEvent("nyx:core:client:notify", targetPlayer.source,
            string.format("CONGRATULATIONS: You have been certified and instated as %s!", officeInfo.title),
            "success"
        )
    end

    TriggerClientEvent("nyx:parliament:client:officialInstated", -1, {
        officeId = officeId,
        title = officeInfo.title,
        displayName = displayName,
        citizenId = citizenId,
        termDays = termDays
    })

    return true
end

-- 4. Initiate Recall Petition
function Nyx.Parliament.InitiateRecallPetition(src, officeId, reason)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    if not officeId or not reason or #reason < 10 then
        return { success = false, error = "INVALID_PETITION_REASON" }
    end

    local official = MySQL.single.await([[
        SELECT * FROM `nyx_parliament_officials` WHERE `office_id` = ? AND `status` = 'active'
    ]], { officeId })

    if not official then
        return { success = false, error = "NO_ACTIVE_OFFICIAL_IN_OFFICE" }
    end

    local citId = player.citizenId
    local petitionId = string.format("recall:%s_%d", officeId, os.time())
    local reqSigs = Config.RecallSignatureThreshold or 5

    local ok = MySQL.insert.await([[
        INSERT INTO `nyx_parliament_recall_petitions`
            (`petition_id`, `office_id`, `initiator_citizen_id`, `reason`, `signatures_count`, `required_signatures`, `expires_at`)
        VALUES (?, ?, ?, ?, 1, ?, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 7 DAY))
    ]], {
        petitionId,
        officeId,
        citId,
        reason,
        reqSigs
    })

    if not ok then
        return { success = false, error = "PETITION_CREATION_FAILED" }
    end

    -- Insert initiator's own signature
    MySQL.insert.await([[
        INSERT INTO `nyx_parliament_recall_signatures` (`petition_id`, `citizen_id`)
        VALUES (?, ?)
    ]], { petitionId, citId })

    print(string.format("^3[Nyx:Parliament] Recall petition filed against '%s' by citizen %s (Petition: %s)^7",
        officeId, citId, petitionId))

    return {
        success = true,
        petitionId = petitionId,
        signaturesCount = 1,
        requiredSignatures = reqSigs
    }
end

-- 5. Sign Recall Petition
function Nyx.Parliament.SignRecallPetition(src, petitionId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local petition = MySQL.single.await([[
        SELECT * FROM `nyx_parliament_recall_petitions`
        WHERE `petition_id` = ? AND `status` = 'active' AND `expires_at` >= CURRENT_TIMESTAMP
    ]], { petitionId })

    if not petition then
        return { success = false, error = "PETITION_NOT_ACTIVE" }
    end

    local citId = player.citizenId
    local alreadySigned = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_parliament_recall_signatures`
        WHERE `petition_id` = ? AND `citizen_id` = ?
    ]], { petitionId, citId }) or 0

    if alreadySigned > 0 then
        return { success = false, error = "ALREADY_SIGNED" }
    end

    MySQL.insert.await([[
        INSERT INTO `nyx_parliament_recall_signatures` (`petition_id`, `citizen_id`)
        VALUES (?, ?)
    ]], { petitionId, citId })

    local newCount = (petition.signatures_count or 1) + 1
    local req = petition.required_signatures or 5

    if newCount >= req then
        -- Threshold reached: certify petition and create recall referendum session
        MySQL.prepare.await([[
            UPDATE `nyx_parliament_recall_petitions` SET `signatures_count` = ?, `status` = 'certified' WHERE `petition_id` = ?
        ]], { newCount, petitionId })

        local referendumId = string.format("referendum:recall_%s_%s", petition.office_id, Nyx.RPC.GenerateNonce():sub(1, 6))
        local meta = {
            officeId = petition.office_id,
            recallPetitionId = petitionId,
            options = {
                { id = "RECALL_YES", name = "Yes / Remove Official from Office" },
                { id = "RECALL_NO", name = "No / Retain Official in Office" }
            }
        }

        MySQL.prepare.await([[
            INSERT INTO `nyx_parliament_sessions`
                (`session_id`, `title`, `description`, `type`, `required_quorum`, `starts_at`, `ends_at`, `status`, `metadata`)
            VALUES (?, ?, ?, 'referendum', ?, CURRENT_TIMESTAMP, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 5 DAY), 'active', ?)
        ]], {
            referendumId,
            string.format("Recall Referendum: %s", petition.office_id:upper()),
            string.format("Popular recall election pursuant to certified petition %s. Reason: %s", petitionId, petition.reason),
            Config.DefaultQuorum or 5,
            json.encode(meta)
        })

        TriggerClientEvent("nyx:parliament:client:newSessionPosted", -1, referendumId, string.format("Recall Referendum: %s", petition.office_id))
    else
        MySQL.prepare.await([[
            UPDATE `nyx_parliament_recall_petitions` SET `signatures_count` = ? WHERE `petition_id` = ?
        ]], { newCount, petitionId })
    end

    return {
        success = true,
        signaturesCount = newCount,
        requiredSignatures = req,
        certified = (newCount >= req)
    }
end

-- ============================================================================
-- RPC Registrations for Elections & Candidacies
-- ============================================================================

Nyx.RPC.Register("parliament:registerCandidate", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end
    return Nyx.Parliament.RegisterCandidate(src, payload.sessionId, payload.displayName, payload.party, payload.platform, payload.slogan)
end)

Nyx.RPC.Register("parliament:endorseCandidate", function(src, candidateId)
    return Nyx.Parliament.EndorseCandidate(src, candidateId)
end)

Nyx.RPC.Register("parliament:getCandidates", function(src, sessionId)
    if not sessionId then return {} end
    local rows = MySQL.query.await([[
        SELECT `candidate_id`, `session_id`, `citizen_id`, `display_name`, `party_affiliation`,
               `campaign_slogan`, `platform_summary`, `collateral_deposited`, `endorsements_count`, `status`, `created_at`
        FROM `nyx_parliament_candidates`
        WHERE `session_id` = ?
        ORDER BY `endorsements_count` DESC, `created_at` ASC
    ]], { sessionId })
    return rows or {}
end)

Nyx.RPC.Register("parliament:getOfficials", function(src)
    local rows = MySQL.query.await([[
        SELECT `office_id`, `title`, `citizen_id`, `display_name`, `elected_session_id`,
               `term_start`, `term_end`, `status`, `updated_at`
        FROM `nyx_parliament_officials`
        WHERE `status` = 'active'
    ]])
    return rows or {}
end)

Nyx.RPC.Register("parliament:getTabulationAudit", function(src, sessionId)
    if not sessionId then return {} end
    local rows = MySQL.query.await([[
        SELECT `round_number`, `continuing_ballots`, `exhausted_ballots`,
               `tally_breakdown`, `eliminated_candidate`, `winner_declared`, `created_at`
        FROM `nyx_parliament_tabulation_logs`
        WHERE `session_id` = ?
        ORDER BY `round_number` ASC
    ]], { sessionId })

    local logs = {}
    if rows then
        for _, r in ipairs(rows) do
            local breakdown = {}
            if type(r.tally_breakdown) == "string" then
                local ok, parsed = pcall(json.decode, r.tally_breakdown)
                if ok and type(parsed) == "table" then breakdown = parsed end
            elseif type(r.tally_breakdown) == "table" then
                breakdown = r.tally_breakdown
            end

            logs[#logs + 1] = {
                roundNumber = r.round_number,
                continuingBallots = r.continuing_ballots,
                exhaustedBallots = r.exhausted_ballots,
                tally = breakdown,
                eliminated = r.eliminated_candidate,
                winner = r.winner_declared,
                createdAt = r.created_at
            }
        end
    end

    return logs
end)

Nyx.RPC.Register("parliament:fileRecallPetition", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end
    return Nyx.Parliament.InitiateRecallPetition(src, payload.officeId, payload.reason)
end)

Nyx.RPC.Register("parliament:signRecallPetition", function(src, petitionId)
    return Nyx.Parliament.SignRecallPetition(src, petitionId)
end)
