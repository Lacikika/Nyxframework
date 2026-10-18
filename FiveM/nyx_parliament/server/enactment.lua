--[[
    Nyxframework: nyx_parliament
    File: server/enactment.lua
    Description: Statutory bill enactment hook, database mutation, and real-time law propagation.
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
            local numVal = tonumber(act.newValue)
            law.currentValue[act.field] = numVal
            law.lastAmended = session.session_id

            local jsonPath = "$." .. act.field
            MySQL.prepare([[
                UPDATE `nyx_parliament_laws`
                SET `current_value` = JSON_SET(`current_value`, ?, ?), `last_amended_by_session` = ?
                WHERE `law_id` = ?
            ]], { jsonPath, numVal, session.session_id, act.targetLawId })

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
        end
    end

    -- Broadcast to law enforcement MDTs, courts, and civic interfaces
    TriggerEvent("nyx:parliament:lawsUpdated", actions)
    TriggerClientEvent("nyx:parliament:client:lawsUpdated", -1, actions)

    return true
end

-- Conclude and tabulate an active parliamentary or election session
function Nyx.Parliament.ConcludeSession(sessionId)
    local session = MySQL.single.await("SELECT * FROM `nyx_parliament_sessions` WHERE `session_id` = ?", { sessionId })
    if not session then return false, "SESSION_NOT_FOUND" end

    if session.status ~= "active" then
        return false, "SESSION_NOT_ACTIVE"
    end

    MySQL.prepare("UPDATE `nyx_parliament_sessions` SET `status` = 'tallying' WHERE `session_id` = ?", { sessionId })

    local winner, finalCounts, roundLogs = Nyx.Parliament.TabulateRankedChoice(sessionId)

    if not winner then
        return false, finalCounts -- Error code or QUORUM_NOT_MET
    end

    -- Record winner
    MySQL.prepare([[
        UPDATE `nyx_parliament_sessions` 
        SET `status` = 'concluded', `winner_option` = ? 
        WHERE `session_id` = ?
    ]], { winner, sessionId })

    print(string.format("^2[Nyx:Parliament] Session '%s' concluded. Winner: ^3%s^7", sessionId, tostring(winner)))

    -- If bill or referendum passed, automatically trigger statutory enactment
    if (session.type == "bill_vote" or session.type == "referendum") and (winner == "PASS" or winner == "YES") then
        Nyx.Parliament.EnactBill(session)
    end

    TriggerClientEvent("nyx:parliament:client:sessionConcluded", -1, sessionId, winner)
    return true, winner
end

-- Periodic Session Lifecycle Thread (checks for expired sessions every Config.SessionCheckInterval)
CreateThread(function()
    local intervalMs = (Config.SessionCheckInterval or 60) * 1000
    while true do
        Wait(intervalMs)

        local expiredRows = MySQL.query.await([[
            SELECT `session_id` FROM `nyx_parliament_sessions` 
            WHERE `status` = 'active' AND `ends_at` <= CURRENT_TIMESTAMP
        ]])

        if expiredRows then
            for _, row in ipairs(expiredRows) do
                Nyx.Parliament.ConcludeSession(row.session_id)
            end
        end
    end
end)
