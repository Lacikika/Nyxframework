--[[
    Nyxframework: nyx_parliament
    File: server/enactment.lua
    Description: Statutory bill enactment hook, database mutation, real-time law propagation,
                 election certification lifecycle, collateral reconciliation, automated term expiration,
                 and recall referendum execution.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- Enact a verified and ratified legislative bill
function Nyx.Parliament.EnactBill(session)
    if not session then return false, "INVALID_SESSION" end

    local metadata = session.metadata
    if type(metadata) == "string" then
        local ok, parsed = pcall(json.decode, metadata)
        if ok then metadata = parsed end
    end

    local actions = metadata and metadata.actions
    if not actions or #actions == 0 then
        return true -- No statutory amendments declared in this bill
    end

    -- Validate bounds prior to database execution
    local okValidate, valErr = Nyx.Parliament.ValidateBillActions(actions)
    if not okValidate then
        print(string.format("^1[Nyx:Parliament] Failed to enact bill '%s': %s^7", session.session_id, valErr))
        return false, valErr
    end

    print(string.format("^2[Nyx:Parliament] Enacting ratified legislation '%s' (%d statutory actions)...^7", session.title, #actions))

    for _, act in ipairs(actions) do
        local law = Nyx.Parliament.Laws[act.targetLawId]
        if law then
            local oldVal = law.currentValue and law.currentValue[act.field] and tonumber(law.currentValue[act.field]) or nil
            local numVal = tonumber(act.newValue)
            law.currentValue[act.field] = numVal
            law.lastAmended = session.session_id

            local jsonPath = "$." .. act.field
            MySQL.prepare.await([[
                UPDATE `nyx_parliament_laws`
                SET `current_value` = JSON_SET(`current_value`, ?, ?), `last_amended_by_session` = ?
                WHERE `law_id` = ?
            ]], { jsonPath, numVal, session.session_id, act.targetLawId })

            -- Persist immutable legislative amendment audit record
            pcall(function()
                MySQL.prepare.await([[
                    INSERT INTO `nyx_parliament_amendment_audit`
                        (`session_id`, `law_id`, `field`, `old_value`, `new_value`, `enacted_by_session_title`)
                    VALUES (?, ?, ?, ?, ?, ?)
                ]], { session.session_id, act.targetLawId, act.field, oldVal, numVal, session.title or session.session_id })
            end)

            -- Persist statutory override to MDT audit ledger if targeting MDT, speed, or penal
            pcall(function()
                MySQL.prepare.await([[
                    INSERT INTO `nyx_mdt_statutory_overrides`
                        (`law_id`, `enacted_session_id`, `statutory_field`, `previous_value`, `new_value`, `synced_to_mdt`)
                    VALUES (?, ?, ?, ?, ?, 1)
                ]], { act.targetLawId, session.session_id, act.field, oldVal or 0.0, numVal })
            end)

            -- Real-time downstream propagation: Intercept nyx_treasury tax rates
            if act.targetLawId == "tax:sales_rate" and act.field == "rate" then
                pcall(function()
                    exports['nyx_treasury']:SetTaxRate("sales", numVal, session.title)
                end)
            elseif act.targetLawId == "tax:transfer_rate" and act.field == "rate" then
                pcall(function()
                    exports['nyx_treasury']:SetTaxRate("transfer", numVal, session.title)
                end)
            end

            -- MDT Real-Time Dispatch Warning Overlay for Statutory Amendments
            if act.targetLawId:sub(1, 6) == "speed:" or act.targetLawId:sub(1, 6) == "penal:" or act.targetLawId == "tax:sales_cap" then
                pcall(function()
                    if exports['nyx_mdt'] and exports['nyx_mdt'].CreateDispatchWarning then
                        local warnTitle = string.format("JOGSZABÁLY MÓDOSÍTÁS: %s", law.title or act.targetLawId)
                        local warnDesc = string.format("A Parlament módosította a(z) %s törvényt (%s: %s -> %s). Hatályba lépett.",
                            act.targetLawId, act.field, tostring(oldVal or "N/A"), tostring(numVal))
                        exports['nyx_mdt']:CreateDispatchWarning({
                            category = "statutory_amendment",
                            severity = "medium",
                            title = warnTitle,
                            description = warnDesc,
                            locationLabel = "San Andreas Törvényhozás",
                            coords = { x = -545.0, y = -204.0, z = 38.2 }
                        })
                    end
                end)
            end
        end
    end

    -- Re-hydrate laws and update replicated State Bags
    Nyx.Parliament.HydrateLaws()

    -- Broadcast to law enforcement MDTs, courts, and civic interfaces
    TriggerEvent("nyx:parliament:lawsUpdated", actions)
    TriggerClientEvent("nyx:parliament:client:lawsUpdated", -1, actions)

    return true
end

-- Conclude and tabulate an active parliamentary, election, or referendum session
function Nyx.Parliament.ConcludeSession(sessionId)
    local session = MySQL.single.await([[
        SELECT * FROM `nyx_parliament_sessions` WHERE `session_id` = ?
    ]], { sessionId })

    if not session then return false, "SESSION_NOT_FOUND" end

    if session.status ~= "active" then
        return false, "SESSION_NOT_ACTIVE"
    end

    MySQL.prepare.await([[
        UPDATE `nyx_parliament_sessions` SET `status` = 'tallying', `election_phase` = 'tallying' WHERE `session_id` = ?
    ]], { sessionId })

    local winner, finalCounts, roundLogs, winStatus, candidateDetails = Nyx.Parliament.TabulateRankedChoice(sessionId)

    if not winner then
        return false, winStatus or finalCounts
    end

    -- Calculate total votes cast across final round
    local totalVotes = 0
    if finalCounts and type(finalCounts) == "table" then
        for _, count in pairs(finalCounts) do
            totalVotes = totalVotes + (tonumber(count) or 0)
        end
    end

    -- Record winner and concluded status
    MySQL.prepare.await([[
        UPDATE `nyx_parliament_sessions` 
        SET `status` = 'concluded', `election_phase` = 'concluded', `winner_option` = ? 
        WHERE `session_id` = ?
    ]], { winner, sessionId })

    print(string.format("^2[Nyx:Parliament] Session '%s' concluded. Winner: ^3%s^7 (%s, %d total votes tallied)",
        sessionId, tostring(winner), tostring(winStatus), totalVotes))

    local meta = {}
    if session.metadata then
        if type(session.metadata) == "string" then
            local ok, parsed = pcall(json.decode, session.metadata)
            if ok and type(parsed) == "table" then meta = parsed end
        elseif type(session.metadata) == "table" then
            meta = session.metadata
        end
    end

    -- 1. If general election, update candidate vote statistics, reconcile collateral, and instate winner
    if session.type == "election" then
        local officeId = session.office_id or meta.officeId
        if not officeId then
            local clean = session.session_id:gsub("^election:", "")
            local firstPart = clean:match("^([%a_]+)")
            if firstPart and Config.Offices and Config.Offices[firstPart] then
                officeId = firstPart
            else
                officeId = "mayor"
            end
        end

        -- Update candidate final vote tallies and percentages
        if finalCounts and type(finalCounts) == "table" then
            for candId, count in pairs(finalCounts) do
                local cVotes = tonumber(count) or 0
                local cPct = totalVotes > 0 and math.floor(((cVotes / totalVotes) * 100.0) * 100 + 0.5) / 100.0 or 0.00
                MySQL.prepare.await([[
                    UPDATE `nyx_parliament_candidates`
                    SET `vote_count` = ?, `vote_percentage` = ?
                    WHERE `candidate_id` = ?
                ]], { cVotes, cPct, candId })
            end
        end

        -- Reconcile candidate collateral deposits
        Nyx.Parliament.ReconcileElectionCollaterals(sessionId, winner, totalVotes)

        local citizenId = candidateDetails and (candidateDetails.citizen_id or candidateDetails.citizenId)
        local displayName = candidateDetails and (candidateDetails.display_name or candidateDetails.name)

        if not citizenId then
            local candRow = MySQL.single.await([[
                SELECT `citizen_id`, `display_name` FROM `nyx_parliament_candidates` WHERE `candidate_id` = ?
            ]], { winner })

            if candRow then
                citizenId = candRow.citizen_id
                displayName = candRow.display_name
            end
        end

        if citizenId then
            Nyx.Parliament.InstateOfficial(officeId, citizenId, displayName, sessionId)
        end
    end

    -- 2. If recall referendum, evaluate outcome
    if session.type == "referendum" then
        local officeId = session.office_id or meta.officeId
        local outcome = Nyx.DemocraticElections.EvaluateRecallReferendumOutcome(winner, officeId)

        if outcome.vacateOfficial and officeId then
            -- Recall succeeded: vacate official and automatically schedule snap election
            Nyx.Parliament.VacateOfficial(officeId, "Citizen recall referendum passed by popular ballot", "recalled")
            print(string.format("^1[Nyx:Parliament] Recall referendum PASSED! Office '%s' vacated. Scheduling snap election...^7", officeId))
            Nyx.Parliament.ScheduleElectionSession(officeId)
        elseif outcome.applyCooldown and officeId then
            -- Recall failed: official retained, apply 7-day recall immunity cooldown
            local cooldownDays = outcome.cooldownDays or Config.RecallImmunityDays or 7
            MySQL.prepare.await([[
                UPDATE `nyx_parliament_officials`
                SET `cooldown_until` = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? DAY)
                WHERE `office_id` = ? AND `status` = 'active'
            ]], { cooldownDays, officeId })

            print(string.format("^2[Nyx:Parliament] Recall referendum DEFEATED. Official in office '%s' retained with %d-day immunity cooldown.^7",
                officeId, cooldownDays))
        end
    end

    -- 3. If bill vote or statutory referendum passed, automatically trigger statutory enactment
    if (session.type == "bill_vote" or session.type == "referendum") and (winner == "PASS" or winner == "YES") then
        Nyx.Parliament.EnactBill(session)
    end

    TriggerClientEvent("nyx:parliament:client:sessionConcluded", -1, sessionId, winner)
    return true, winner, winStatus, roundLogs
end

-- Periodic Session & Official Lifecycle Thread
CreateThread(function()
    local intervalMs = (Config.SessionCheckInterval or 60) * 1000
    while true do
        Wait(intervalMs)

        -- 1. Advance nomination phase to voting phase when nomination period concludes
        pcall(function()
            MySQL.prepare.await([[
                UPDATE `nyx_parliament_sessions`
                SET `election_phase` = 'voting'
                WHERE `type` = 'election' AND `election_phase` = 'nomination'
                  AND `nomination_ends_at` IS NOT NULL AND `nomination_ends_at` <= CURRENT_TIMESTAMP
                  AND `status` = 'active'
            ]])
        end)

        -- 2. Conclude expired sessions
        pcall(function()
            local expiredRows = MySQL.query.await([[
                SELECT `session_id` FROM `nyx_parliament_sessions` 
                WHERE `status` = 'active' AND `ends_at` <= CURRENT_TIMESTAMP
            ]])

            if expiredRows then
                for _, row in ipairs(expiredRows) do
                    Nyx.Parliament.ConcludeSession(row.session_id)
                end
            end
        end)

        -- 3. Check and expire completed official term limits
        pcall(function()
            Nyx.Parliament.CheckAndExpireOfficialTerms()
        end)

        -- 4. Check and expire stale recall petitions
        pcall(function()
            Nyx.Parliament.CheckAndExpireRecallPetitions()
        end)
    end
end)
