--[[
    Nyxframework: nyx_parliament
    File: server/exports.lua
    Description: Clean public server exports for law queries, penal code, election tabulation,
                 and candidate management.
]]

Nyx = Nyx or {}

exports("GetLaw", function(lawId)
    return Nyx.Parliament.GetLaw(lawId)
end)

exports("GetLawValue", function(lawId, field)
    return Nyx.Parliament.GetLawValue(lawId, field)
end)

exports("GetFine", function(lawId)
    local val = Nyx.Parliament.GetLawValue(lawId, "fine")
    return tonumber(val) or 0
end)

exports("GetSentence", function(lawId)
    local val = Nyx.Parliament.GetLawValue(lawId, "months")
    return tonumber(val) or 0
end)

exports("GetPenalCode", function()
    return Nyx.Parliament.GetPenalCode()
end)

exports("GetSalesTaxRate", function()
    local val = Nyx.Parliament.GetLawValue("tax:sales_rate", "rate")
    return tonumber(val) or 0.08
end)

exports("GetTransferTaxRate", function()
    local val = Nyx.Parliament.GetLawValue("tax:transfer_rate", "rate")
    return tonumber(val) or 0.02
end)

exports("TabulateSession", function(sessionId)
    return Nyx.Parliament.ConcludeSession(sessionId)
end)

exports("CalculateIRV", function(ballots, candidates, options)
    return Nyx.IRV.Tabulate(ballots, candidates, options)
end)

exports("RegisterCandidate", function(src, sessionId, displayName, party, platform)
    return Nyx.Parliament.RegisterCandidate(src, sessionId, displayName, party, platform)
end)

exports("EndorseCandidate", function(src, candidateId)
    return Nyx.Parliament.EndorseCandidate(src, candidateId)
end)

exports("InstateOfficial", function(officeId, citizenId, displayName, sessionId)
    return Nyx.Parliament.InstateOfficial(officeId, citizenId, displayName, sessionId)
end)

exports("GetOfficial", function(officeId)
    return MySQL.single.await([[
        SELECT * FROM `nyx_parliament_officials` WHERE `office_id` = ? AND `status` = 'active'
    ]], { officeId })
end)

exports("GetActiveOfficials", function()
    return MySQL.query.await([[
        SELECT * FROM `nyx_parliament_officials` WHERE `status` = 'active'
    ]]) or {}
end)

exports("HydrateLaws", function()
    return Nyx.Parliament.HydrateLaws()
end)

exports("GetOverview", function(src)
    return exports['nyx_core']:TriggerRPCAwait and exports['nyx_core']:TriggerRPCAwait("parliament:getOverview")
end)

exports("GetAmendmentAuditLogs", function(filterLawId)
    local query = "SELECT * FROM `nyx_parliament_amendment_audit`"
    local params = {}
    if filterLawId and #filterLawId > 0 then
        query = query .. " WHERE `law_id` = ?"
        params[#params + 1] = filterLawId
    end
    query = query .. " ORDER BY `enacted_at` DESC LIMIT 50"
    return MySQL.query.await(query, params) or {}
end)

exports("WithdrawCandidacy", function(src, candidateId)
    return Nyx.Parliament.WithdrawCandidacy(src, candidateId)
end)

exports("ScheduleElectionSession", function(officeId, nomHours, voteHours)
    return Nyx.Parliament.ScheduleElectionSession(officeId, nomHours, voteHours)
end)

exports("VacateOfficial", function(officeId, reason, eventType)
    return Nyx.Parliament.VacateOfficial(officeId, reason, eventType)
end)

exports("CheckAndExpireOfficialTerms", function()
    return Nyx.Parliament.CheckAndExpireOfficialTerms()
end)

exports("ReconcileElectionCollaterals", function(sessionId, winnerId, totalVotes)
    return Nyx.Parliament.ReconcileElectionCollaterals(sessionId, winnerId, totalVotes)
end)

exports("GetTermAudits", function(officeId)
    local query = "SELECT * FROM `nyx_parliament_term_audits`"
    local params = {}
    if officeId and #officeId > 0 then
        query = query .. " WHERE `office_id` = ?"
        params[#params + 1] = officeId
    end
    query = query .. " ORDER BY `created_at` DESC LIMIT 50"
    return MySQL.query.await(query, params) or {}
end)

exports("GetBoothTerminals", function()
    return MySQL.query.await("SELECT * FROM `nyx_parliament_booth_terminals` WHERE `is_active` = 1") or {}
end)

