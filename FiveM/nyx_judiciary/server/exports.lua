--[[
    Nyxframework: nyx_judiciary
    File: server/exports.lua
    Description: Clean public server exports for judiciary, forensics, warrants, and jury pipelines.
]]

Nyx = Nyx or {}

-- Forensic Event Registration
exports("RegisterBallisticEvent", function(src, weaponHash, coords)
    return Nyx.Judiciary.RegisterBallisticEvent(src, weaponHash, coords)
end)

exports("RegisterTraumaEvent", function(victimSrc, attackerSrc, damageType, coords)
    return Nyx.Judiciary.RegisterTraumaEvent(victimSrc, attackerSrc, damageType, coords)
end)

exports("RegisterFingerprintEvent", function(src, surfaceDesc, coords)
    return Nyx.Judiciary.RegisterFingerprintEvent(src, surfaceDesc, coords)
end)

-- Evidence Collection & Verification
exports("CollectEvidence", function(src, evidenceId, useGloves)
    return Nyx.Judiciary.CollectEvidence(src, evidenceId, useGloves)
end)

exports("VerifyEvidence", function(evidenceIdOrHash)
    return Nyx.Judiciary.VerifyEvidence(evidenceIdOrHash)
end)

-- Dockets & Cases
exports("FileDocket", function(plaintiffCitId, defendantCitId, title, caseType, brief, presidingJudgeId)
    return Nyx.Judiciary.CreateDocket(plaintiffCitId, defendantCitId, title, caseType, brief, presidingJudgeId)
end)

exports("LinkEvidence", function(docketId, evidenceId, authorizedCitId)
    return Nyx.Judiciary.LinkEvidence(docketId, evidenceId, authorizedCitId)
end)

exports("ScheduleDocket", function(docketId, scheduledTimestamp, presidingJudgeId)
    return Nyx.Judiciary.ScheduleDocket(docketId, scheduledTimestamp, presidingJudgeId)
end)

exports("GetDocket", function(docketId)
    return Nyx.Judiciary.GetDocket(docketId)
end)

-- Warrants & MDT Integration
exports("IssueWarrant", function(issuingJudgeCitId, targetCitId, warrantType, causeSummary, targetEntityId, durationHours)
    return Nyx.Judiciary.IssueWarrant(issuingJudgeCitId, targetCitId, warrantType, causeSummary, targetEntityId, durationHours)
end)

exports("RescindWarrant", function(warrantId, judgeCitId, reason)
    return Nyx.Judiciary.RescindWarrant(warrantId, judgeCitId, reason)
end)

exports("ExecuteWarrant", function(warrantId, officerCitId)
    return Nyx.Judiciary.ExecuteWarrant(warrantId, officerCitId)
end)

exports("GetActiveWarrants", function(targetCitId)
    return Nyx.Judiciary.GetActiveWarrants(targetCitId)
end)

-- Juries & Civic Summons
exports("SummonJury", function(docketId, requiredCount)
    return Nyx.Judiciary.SummonJury(docketId, requiredCount)
end)

exports("CastSecretBallot", function(docketId, citizenId, voteOutcome)
    return Nyx.Judiciary.CastSecretBallot(docketId, citizenId, voteOutcome)
end)

-- Automated Rulings & Execution
exports("ExecuteVerdict", function(docketId, verdictPayload, presidingJudgeCitId)
    return Nyx.Judiciary.ExecuteVerdict(docketId, verdictPayload, presidingJudgeCitId)
end)
