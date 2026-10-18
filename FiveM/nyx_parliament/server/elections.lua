--[[
    Nyxframework: nyx_parliament
    File: server/elections.lua
    Description: Candidate registration, endorsement ledger, collateral escrow & refund reconciliation,
                 official instatement, automated term limit expiration, succession election dispatch,
                 and citizen recall referendum petitions.
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
        SELECT `session_id`, `title`, `type`, `status`, `metadata`, `office_id`, `election_phase`, `nomination_ends_at`
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

    -- Query existing candidates
    local existingCandidates = MySQL.query.await([[
        SELECT `candidate_id`, `citizen_id`, `status` FROM `nyx_parliament_candidates` WHERE `session_id` = ?
    ]], { sessionId }) or {}

    local activeOfficial = nil
    if session.office_id then
        activeOfficial = MySQL.single.await([[
            SELECT `office_id`, `citizen_id`, `consecutive_terms`, `status`
            FROM `nyx_parliament_officials`
            WHERE `office_id` = ? AND `status` = 'active'
        ]], { session.office_id })
    end

    local citId = player.citizenId
    local okElig, eligErr = Nyx.DemocraticElections.EvaluateCandidateEligibility(
        citId,
        session.office_id,
        session,
        existingCandidates,
        activeOfficial,
        Config
    )

    if not okElig then
        return { success = false, error = eligErr }
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
            (`candidate_id`, `session_id`, `citizen_id`, `display_name`, `party_affiliation`, `campaign_slogan`,
             `platform_summary`, `collateral_deposited`, `collateral_status`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'escrowed', ?)
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

    print(string.format("^2[Nyx:Parliament] Citizen %s registered as candidate '%s' for session '%s' (Status: %s, Collateral: $%.2f escrowed)^7",
        citId, displayName, sessionId, initialStatus, collateral))

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

-- 2. Voluntary Candidate Withdrawal with Collateral Refund
function Nyx.Parliament.WithdrawCandidacy(src, candidateId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    if not candidateId or type(candidateId) ~= "string" then
        return { success = false, error = "INVALID_CANDIDATE_ID" }
    end

    local candidate = MySQL.single.await([[
        SELECT c.*, s.`status` AS `session_status`, s.`election_phase`
        FROM `nyx_parliament_candidates` c
        JOIN `nyx_parliament_sessions` s ON c.`session_id` = s.`session_id`
        WHERE c.`candidate_id` = ?
    ]], { candidateId })

    if not candidate then
        return { success = false, error = "CANDIDATE_NOT_FOUND" }
    end

    if candidate.citizen_id ~= player.citizenId then
        return { success = false, error = "CANNOT_WITHDRAW_OTHER_CANDIDATE" }
    end

    if candidate.status == "withdrawn" then
        return { success = false, error = "ALREADY_WITHDRAWN" }
    end

    -- Allow withdrawal if session is in nomination or active voting before conclusion
    if candidate.session_status == "concluded" or candidate.session_status == "tallying" then
        return { success = false, error = "SESSION_ALREADY_TALLYING_OR_CONCLUDED" }
    end

    local collateral = tonumber(candidate.collateral_deposited) or 0.0
    local refundTxId = nil

    if collateral > 0.0 and candidate.collateral_status == "escrowed" then
        local debitAccount = "gov:city:master"
        local creditAccount = "char:" .. player.citizenId .. ":bank"

        local okTransfer, txResult = exports['nyx_treasury']:ExecuteTransfer(
            debitAccount,
            creditAccount,
            collateral,
            "election_collateral_refund",
            "parliament:" .. candidate.session_id,
            string.format("Electoral Collateral Refund (Withdrawal): %s", candidate.display_name),
            0.0
        )

        if okTransfer then
            refundTxId = type(txResult) == "table" and txResult.txId or tostring(txResult or "TX-REFUND")
        else
            print(string.format("^1[Nyx:Parliament] Warning: Collateral refund failed for withdrawing candidate %s^7", candidateId))
        end
    end

    MySQL.prepare.await([[
        UPDATE `nyx_parliament_candidates`
        SET `status` = 'withdrawn', `collateral_status` = 'refunded', `refund_treasury_tx_id` = ?
        WHERE `candidate_id` = ?
    ]], { refundTxId, candidateId })

    print(string.format("^3[Nyx:Parliament] Candidate %s (%s) withdrew from election '%s'. Collateral $%.2f refunded.^7",
        candidate.display_name, candidate.citizen_id, candidate.session_id, collateral))

    TriggerClientEvent("nyx:core:client:notify", src,
        string.format("ELECTION: Candidacy withdrawn. Collateral of $%.2f has been returned to your bank account.", collateral),
        "info"
    )

    return {
        success = true,
        candidateId = candidateId,
        status = "withdrawn",
        collateralRefunded = collateral,
        txId = refundTxId
    }
end

-- 3. Endorse Candidate
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

    if candidate.status == "withdrawn" or candidate.status == "disqualified" then
        return { success = false, error = "CANDIDATE_NOT_ACTIVE" }
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

-- 4. Reconcile Election Collateral Escrow across all Candidates upon Session Conclusion
function Nyx.Parliament.ReconcileElectionCollaterals(sessionId, winnerCandidateId, totalVotes)
    if not sessionId then return false, "INVALID_SESSION_ID" end

    local candidates = MySQL.query.await([[
        SELECT * FROM `nyx_parliament_candidates` WHERE `session_id` = ?
    ]], { sessionId }) or {}

    local thresholdPct = Config.CollateralRefundThresholdPct or 10.0
    local reconciledCount = 0

    for _, cand in ipairs(candidates) do
        if cand.collateral_status == "escrowed" and tonumber(cand.collateral_deposited) > 0 then
            local outcome = Nyx.DemocraticElections.EvaluateCollateralRefund(
                cand,
                totalVotes,
                winnerCandidateId,
                thresholdPct
            )

            if outcome.eligible and outcome.amount > 0 then
                local debitAccount = "gov:city:master"
                local creditAccount = "char:" .. cand.citizen_id .. ":bank"

                local okTransfer, txResult = exports['nyx_treasury']:ExecuteTransfer(
                    debitAccount,
                    creditAccount,
                    outcome.amount,
                    "election_collateral_refund",
                    "parliament:" .. sessionId,
                    string.format("Election Collateral Refund (%s): %s", outcome.reason, cand.display_name),
                    0.0
                )

                local txId = okTransfer and (type(txResult) == "table" and txResult.txId or tostring(txResult or "TX-REFUND")) or nil
                MySQL.prepare.await([[
                    UPDATE `nyx_parliament_candidates`
                    SET `collateral_status` = 'refunded', `refund_treasury_tx_id` = ?
                    WHERE `candidate_id` = ?
                ]], { txId, cand.candidate_id })

                print(string.format("^2[Nyx:Parliament] Collateral $%.2f refunded to candidate %s (%s, Reason: %s)^7",
                    outcome.amount, cand.display_name, cand.citizen_id, outcome.reason))
                reconciledCount = reconciledCount + 1
            else
                MySQL.prepare.await([[
                    UPDATE `nyx_parliament_candidates`
                    SET `collateral_status` = 'forfeited'
                    WHERE `candidate_id` = ?
                ]], { cand.candidate_id })

                print(string.format("^3[Nyx:Parliament] Collateral forfeited for candidate %s (%s, Reason: %s)^7",
                    cand.display_name, cand.citizen_id, outcome.reason))
                reconciledCount = reconciledCount + 1
            end
        end
    end

    return true, reconciledCount
end

-- 5. Instate Official following Election Concluded with Winner
function Nyx.Parliament.InstateOfficial(officeId, citizenId, displayName, sessionId)
    if not officeId or not citizenId then return false, "INVALID_OFFICIAL_PARAMETERS" end

    local officeInfo = Config.Offices and Config.Offices[officeId] or {
        title = "Municipal Official",
        termDays = 30,
        maxConsecutiveTerms = 2
    }

    local termDays = officeInfo.termDays or Config.OfficialTermDays or 30

    -- Query prior official status to calculate consecutive term count
    local priorOfficial = MySQL.single.await([[
        SELECT `citizen_id`, `consecutive_terms` FROM `nyx_parliament_officials` WHERE `office_id` = ?
    ]], { officeId })

    local consecutiveTerms = 1
    if priorOfficial and priorOfficial.citizen_id == citizenId then
        consecutiveTerms = (priorOfficial.consecutive_terms or 1) + 1
    end

    MySQL.prepare.await([[
        INSERT INTO `nyx_parliament_officials`
            (`office_id`, `title`, `citizen_id`, `display_name`, `elected_session_id`, `term_start`, `term_end`, `status`, `consecutive_terms`, `cooldown_until`)
        VALUES
            (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? DAY), 'active', ?, NULL)
        ON DUPLICATE KEY UPDATE
            `citizen_id` = VALUES(`citizen_id`),
            `display_name` = VALUES(`display_name`),
            `elected_session_id` = VALUES(`elected_session_id`),
            `term_start` = CURRENT_TIMESTAMP,
            `term_end` = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? DAY),
            `status` = 'active',
            `consecutive_terms` = ?,
            `cooldown_until` = NULL
    ]], {
        officeId,
        officeInfo.title,
        citizenId,
        displayName or "Elected Citizen",
        sessionId,
        termDays,
        consecutiveTerms,
        termDays,
        consecutiveTerms
    })

    -- Persist official instatement audit log
    pcall(function()
        MySQL.prepare.await([[
            INSERT INTO `nyx_parliament_term_audits`
                (`office_id`, `citizen_id`, `display_name`, `event_type`, `session_id`, `reason`, `notes`)
            VALUES (?, ?, ?, 'instated', ?, 'Electoral victory certified by Instant-Runoff Voting', ?)
        ]], {
            officeId,
            citizenId,
            displayName or "Elected Citizen",
            sessionId,
            string.format("Term %d, %d days duration until expiration", consecutiveTerms, termDays)
        })
    end)

    print(string.format("^2[Nyx:Parliament] Instated citizen %s as %s (%s) for %d-day term (Consecutive: %d).^7",
        citizenId, officeInfo.title, officeId, termDays, consecutiveTerms))

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
        termDays = termDays,
        consecutiveTerms = consecutiveTerms
    })

    return true
end

-- 6. Vacate Official (Recall, Term Expiration, or Resignation)
function Nyx.Parliament.VacateOfficial(officeId, reason, eventType)
    if not officeId then return false, "INVALID_OFFICE_ID" end

    local current = MySQL.single.await([[
        SELECT * FROM `nyx_parliament_officials` WHERE `office_id` = ? AND `status` = 'active'
    ]], { officeId })

    if not current then
        return false, "NO_ACTIVE_OFFICIAL_TO_VACATE"
    end

    local evt = eventType or "term_expired"
    local status = (evt == "recalled") and "recalled" or "expired"

    MySQL.prepare.await([[
        UPDATE `nyx_parliament_officials` SET `status` = ? WHERE `office_id` = ? AND `status` = 'active'
    ]], { status, officeId })

    -- Log to term audit ledger
    pcall(function()
        MySQL.prepare.await([[
            INSERT INTO `nyx_parliament_term_audits`
                (`office_id`, `citizen_id`, `display_name`, `event_type`, `reason`, `notes`)
            VALUES (?, ?, ?, ?, ?, ?)
        ]], {
            officeId,
            current.citizen_id,
            current.display_name,
            evt,
            reason or "Official status transition",
            string.format("Office %s vacated from citizen %s", officeId, current.citizen_id)
        })
    end)

    -- Revoke player metadata and state bag if online
    local targetPlayer = exports['nyx_core']:GetPlayerByCitizenId(current.citizen_id)
    if targetPlayer then
        targetPlayer:setMetadata("parliamentOffice", nil)
        Player(targetPlayer.source).state.parliamentOffice = nil
        TriggerClientEvent("nyx:core:client:notify", targetPlayer.source,
            string.format("OFFICIAL NOTICE: Your term as %s has concluded (%s).", current.title, reason or "Office vacated"),
            "warning"
        )
    end

    print(string.format("^3[Nyx:Parliament] Office '%s' vacated from %s (%s). Event: %s, Reason: %s^7",
        officeId, current.display_name, current.citizen_id, evt, reason or "vacated"))

    TriggerClientEvent("nyx:parliament:client:officialVacated", -1, {
        officeId = officeId,
        citizenId = current.citizen_id,
        eventType = evt,
        reason = reason
    })

    return true, current
end

-- 7. Automated Term Limit Expiration Checker
function Nyx.Parliament.CheckAndExpireOfficialTerms()
    local expiredOfficials = MySQL.query.await([[
        SELECT `office_id`, `title`, `citizen_id`, `display_name`, `term_end`
        FROM `nyx_parliament_officials`
        WHERE `status` = 'active' AND `term_end` <= CURRENT_TIMESTAMP
    ]]) or {}

    local count = 0
    for _, off in ipairs(expiredOfficials) do
        local ok, vacated = Nyx.Parliament.VacateOfficial(off.office_id, "Statutory term limit reached", "term_expired")
        if ok then
            count = count + 1
            print(string.format("^3[Nyx:Parliament] Term expired for %s (%s). Automatically dispatching general election...^7",
                off.display_name, off.office_id))

            -- Automatically schedule the successor general election
            Nyx.Parliament.ScheduleElectionSession(off.office_id)
        end
    end

    return count
end

-- 8. Automatically Dispatch General or Snap Election Session
function Nyx.Parliament.ScheduleElectionSession(officeId, nominationHours, votingHours)
    if not officeId then return false, "INVALID_OFFICE_ID" end

    -- Guard against duplicate active or scheduled election sessions for this office
    local activeSession = MySQL.single.await([[
        SELECT `session_id` FROM `nyx_parliament_sessions`
        WHERE `office_id` = ? AND `status` IN ('active', 'scheduled') AND `type` = 'election'
    ]], { officeId })

    if activeSession then
        return false, "ELECTION_ALREADY_ACTIVE", activeSession.session_id
    end

    local officeInfo = Config.Offices and Config.Offices[officeId] or {
        title = "Municipal Office",
        department = "Civic"
    }

    local nomHours = tonumber(nominationHours) or Config.NominationWindowHours or 48
    local voteHours = tonumber(votingHours) or Config.VotingWindowHours or 72
    local totalHours = nomHours + voteHours

    local year = os.date("%Y")
    local nonce = Nyx.RPC.GenerateNonce():sub(1, 6)
    local sessionId = Nyx.DemocraticElections.GenerateElectionSessionId(officeId, year, nonce)

    local title = string.format("%s Általános Választás (%s)", officeInfo.title, year)
    local description = string.format("Demokratikus, preferenciális rangsorolt (Instant-Runoff Voting) választás a(z) %s tisztség betöltésére.", officeInfo.title)

    local meta = {
        officeId = officeId,
        officeTitle = officeInfo.title,
        nominationWindowHours = nomHours,
        votingWindowHours = voteHours,
        options = {}
    }

    local inserted = MySQL.prepare.await([[
        INSERT INTO `nyx_parliament_sessions`
            (`session_id`, `title`, `description`, `type`, `category`, `office_id`, `election_phase`,
             `required_quorum`, `starts_at`, `nomination_ends_at`, `ends_at`, `status`, `metadata`)
        VALUES (?, ?, ?, 'election', 'elections', ?, 'nomination', ?, CURRENT_TIMESTAMP,
                DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? HOUR), DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? HOUR), 'active', ?)
    ]], {
        sessionId,
        title,
        description,
        officeId,
        Config.DefaultQuorum or 5,
        nomHours,
        totalHours,
        json.encode(meta)
    })

    if not inserted then
        return false, "DATABASE_INSERTION_FAILED"
    end

    -- Persist audit log
    pcall(function()
        MySQL.prepare.await([[
            INSERT INTO `nyx_parliament_term_audits`
                (`office_id`, `citizen_id`, `display_name`, `event_type`, `session_id`, `reason`, `notes`)
            VALUES (?, 'SYSTEM_ELECTORAL_BOARD', 'Autonomous Election Engine', 'election_scheduled', ?, 'Succession election initiated', ?)
        ]], {
            officeId,
            sessionId,
            string.format("Nomination: %d hours, Voting: %d hours", nomHours, voteHours)
        })
    end)

    print(string.format("^2[Nyx:Parliament] New democratic election scheduled: '%s' (%s, Phase: nomination, %d hrs nom, %d hrs vote)^7",
        title, sessionId, nomHours, voteHours))

    TriggerClientEvent("nyx:parliament:client:newSessionPosted", -1, sessionId, title)

    return true, sessionId
end

-- 9. Initiate Recall Petition
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

    local existingPetitions = MySQL.query.await([[
        SELECT * FROM `nyx_parliament_recall_petitions` WHERE `office_id` = ? AND `status` = 'active'
    ]], { officeId }) or {}

    local citId = player.citizenId
    local okElig, eligErr = Nyx.DemocraticElections.EvaluateRecallEligibility(
        official,
        citId,
        existingPetitions,
        os.time()
    )

    if not okElig then
        return { success = false, error = eligErr }
    end

    local petitionId = string.format("recall:%s_%d", officeId, os.time())
    local reqSigs = Config.RecallSignatureThreshold or 5

    local ok = MySQL.insert.await([[
        INSERT INTO `nyx_parliament_recall_petitions`
            (`petition_id`, `office_id`, `target_citizen_id`, `initiator_citizen_id`, `reason`, `signatures_count`, `required_signatures`, `expires_at`)
        VALUES (?, ?, ?, ?, ?, 1, ?, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 7 DAY))
    ]], {
        petitionId,
        officeId,
        official.citizen_id,
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

    print(string.format("^3[Nyx:Parliament] Recall petition filed against %s (%s) by citizen %s (Petition: %s)^7",
        official.display_name, officeId, citId, petitionId))

    return {
        success = true,
        petitionId = petitionId,
        signaturesCount = 1,
        requiredSignatures = reqSigs
    }
end

-- 10. Sign Recall Petition
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
                (`session_id`, `title`, `description`, `type`, `category`, `office_id`, `required_quorum`, `starts_at`, `ends_at`, `status`, `metadata`)
            VALUES (?, ?, ?, 'referendum', 'recall', ?, ?, CURRENT_TIMESTAMP, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 5 DAY), 'active', ?)
        ]], {
            referendumId,
            string.format("Recall Referendum: %s", petition.office_id:upper()),
            string.format("Popular recall election pursuant to certified petition %s. Reason: %s", petitionId, petition.reason),
            petition.office_id,
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

-- 11. Check and Expire Stale Recall Petitions
function Nyx.Parliament.CheckAndExpireRecallPetitions()
    local updated = MySQL.prepare.await([[
        UPDATE `nyx_parliament_recall_petitions`
        SET `status` = 'expired'
        WHERE `status` = 'active' AND `expires_at` <= CURRENT_TIMESTAMP
    ]])
    return updated or 0
end

-- ============================================================================
-- RPC Registrations for Elections & Candidacies
-- ============================================================================

Nyx.RPC.Register("parliament:registerCandidate", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end
    return Nyx.Parliament.RegisterCandidate(src, payload.sessionId, payload.displayName, payload.party, payload.platform, payload.slogan)
end)

Nyx.RPC.Register("parliament:withdrawCandidacy", function(src, candidateId)
    return Nyx.Parliament.WithdrawCandidacy(src, candidateId)
end)

Nyx.RPC.Register("parliament:endorseCandidate", function(src, candidateId)
    return Nyx.Parliament.EndorseCandidate(src, candidateId)
end)

Nyx.RPC.Register("parliament:getCandidates", function(src, sessionId)
    if not sessionId then return {} end
    local rows = MySQL.query.await([[
        SELECT `candidate_id`, `session_id`, `citizen_id`, `display_name`, `party_affiliation`,
               `campaign_slogan`, `platform_summary`, `collateral_deposited`, `collateral_status`,
               `endorsements_count`, `vote_count`, `vote_percentage`, `status`, `created_at`
        FROM `nyx_parliament_candidates`
        WHERE `session_id` = ?
        ORDER BY `endorsements_count` DESC, `vote_count` DESC, `created_at` ASC
    ]], { sessionId })
    return rows or {}
end)

Nyx.RPC.Register("parliament:getOfficials", function(src)
    local rows = MySQL.query.await([[
        SELECT `office_id`, `title`, `citizen_id`, `display_name`, `elected_session_id`,
               `term_start`, `term_end`, `status`, `consecutive_terms`, `cooldown_until`, `updated_at`
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

Nyx.RPC.Register("parliament:getTermAudits", function(src, officeId)
    local query = [[
        SELECT `audit_id`, `office_id`, `citizen_id`, `display_name`, `event_type`,
               `session_id`, `reason`, `notes`, `created_at`
        FROM `nyx_parliament_term_audits`
    ]]
    local params = {}
    if officeId and #officeId > 0 then
        query = query .. " WHERE `office_id` = ?"
        params[#params + 1] = officeId
    end
    query = query .. " ORDER BY `created_at` DESC LIMIT 50"

    local rows = MySQL.query.await(query, params)
    return rows or {}
end)

Nyx.RPC.Register("parliament:getBoothTerminals", function(src)
    local rows = MySQL.query.await([[
        SELECT `booth_id`, `label`, `location_zone`, `coords`, `total_ballots_cast`, `is_active`, `last_ping_at`
        FROM `nyx_parliament_booth_terminals`
        WHERE `is_active` = 1
    ]])
    return rows or {}
end)
