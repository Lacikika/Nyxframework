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

exports("PetitionWarrant", function(petitionerCitId, targetCitId, warrantType, causeSummary, targetEntityId, subpoenaScope, durationHours)
    return Nyx.Judiciary.PetitionWarrant(petitionerCitId, targetCitId, warrantType, causeSummary, targetEntityId, subpoenaScope, durationHours)
end)

exports("ReviewPetition", function(petitionId, judgeCitId, decision, reviewNotes)
    return Nyx.Judiciary.ReviewPetition(petitionId, judgeCitId, decision, reviewNotes)
end)

exports("GetPendingPetitions", function()
    return Nyx.Judiciary.GetPendingPetitions()
end)

exports("GetSubpoenaFinancials", function(targetCitId, requestingOfficerCitId)
    return Nyx.Judiciary.GetSubpoenaFinancials(targetCitId, requestingOfficerCitId)
end)

exports("GetActiveTrackingWarrants", function()
    return Nyx.Judiciary.GetActiveTrackingWarrants()
end)

exports("RecordTrackingPing", function(warrantId, targetCitId, coords, accuracyRadius, sourceType)
    return Nyx.Judiciary.RecordTrackingPing(warrantId, targetCitId, coords, accuracyRadius, sourceType)
end)

-- Juries, Civic Summons & Courtroom Routing
exports("SummonJury", function(docketId, requiredCount)
    return Nyx.Judiciary.SummonJury(docketId, requiredCount)
end)

exports("SeatJuror", function(docketId, citizenId, preferredSeat)
    return Nyx.Judiciary.SeatJuror(docketId, citizenId, preferredSeat)
end)

exports("ExcuseJuror", function(docketId, citizenId, reason)
    return Nyx.Judiciary.ExcuseJuror(docketId, citizenId, reason)
end)

exports("StartTrial", function(docketId, presidingJudgeCitId)
    return Nyx.Judiciary.StartTrial(docketId, presidingJudgeCitId)
end)

exports("StartDeliberation", function(docketId, presidingJudgeCitId)
    return Nyx.Judiciary.StartDeliberation(docketId, presidingJudgeCitId)
end)

exports("CastSecretBallot", function(docketId, citizenId, voteOutcome)
    return Nyx.Judiciary.CastSecretBallot(docketId, citizenId, voteOutcome)
end)

exports("ConcludeTrial", function(docketId, verdictRuling)
    return Nyx.Judiciary.ConcludeTrial(docketId, verdictRuling)
end)

exports("GetJuryStatus", function(docketId)
    return Nyx.Judiciary.GetJuryStatus(docketId)
end)

exports("AllocateCourtroomBucket", function(docketId)
    return Nyx.Judiciary.AllocateCourtroomBucket(docketId)
end)

-- Automated Rulings & Execution
exports("ExecuteVerdict", function(docketId, verdictPayload, presidingJudgeCitId)
    return Nyx.Judiciary.ExecuteVerdict(docketId, verdictPayload, presidingJudgeCitId)
end)

-- Cryptographic Chain-of-Custody & Forensic Ledger Exports
exports("GetEvidenceChainOfCustody", function(evidenceId)
    return Nyx.Judiciary.GetEvidenceChainOfCustody(evidenceId)
end)

exports("VerifyChainOfCustody", function(evidenceId)
    return Nyx.Judiciary.VerifyChainOfCustody(evidenceId)
end)

exports("TransferCustody", function(src, evidenceId, targetCitId, notes)
    return Nyx.Judiciary.TransferCustody(src, evidenceId, targetCitId, notes)
end)

exports("StoreInLocker", function(src, evidenceId, lockerId, notes)
    return Nyx.Judiciary.StoreInLocker(src, evidenceId, lockerId, notes)
end)

exports("CheckoutFromLocker", function(src, evidenceId, lockerId, reason)
    return Nyx.Judiciary.CheckoutFromLocker(src, evidenceId, lockerId, reason)
end)

exports("SubmitLabAnalysis", function(src, evidenceId, analysisType, findings)
    return Nyx.Judiciary.SubmitLabAnalysis(src, evidenceId, analysisType, findings)
end)

exports("SubmitExhibitToCourt", function(src, evidenceId, docketId, exhibitLabel, notes)
    return Nyx.Judiciary.SubmitExhibitToCourt(src, evidenceId, docketId, exhibitLabel, notes)
end)

exports("RegisterSwabEvent", function(src, targetCitId, swabType, coords, isGSRPositive)
    return Nyx.Judiciary.RegisterSwabEvent(src, targetCitId, swabType, coords, isGSRPositive)
end)

exports("RegisterPhotoEvidence", function(src, cameraLocation, snapshotHashOrData, coords, notes)
    return Nyx.Judiciary.RegisterPhotoEvidence(src, cameraLocation, snapshotHashOrData, coords, notes)
end)

exports("AppendCustodyBlock", function(evidenceId, action, custodianCitId, recipientCitId, facilityId, notes, blockMetadata)
    return Nyx.Judiciary.AppendCustodyBlock(evidenceId, action, custodianCitId, recipientCitId, facilityId, notes, blockMetadata)
end)

exports("ComputeChainHash", function(prevHash, evidenceId, sequenceId, action, custodianCitId, recipientCitId, facilityId, timestamp, salt)
    return Nyx.Judiciary.ComputeChainHash(prevHash, evidenceId, sequenceId, action, custodianCitId, recipientCitId, facilityId, timestamp, salt)
end)

exports("GetEvidenceList", function(filterQuery, evidenceType, isSealedOnly, limit, offset)
    return Nyx.Judiciary.GetEvidenceList(filterQuery, evidenceType, isSealedOnly, limit, offset)
end)

exports("LogEvidenceVerification", function(evidenceId, verifierCitizenId, status, isValid, chainLength, rootHash, headHash)
    return Nyx.Judiciary.LogEvidenceVerification(evidenceId, verifierCitizenId, status, isValid, chainLength, rootHash, headHash)
end)

exports("GetEvidenceChainOfCustody", function(evidenceId)
    return Nyx.Judiciary.GetEvidenceChainOfCustody(evidenceId)
end)

exports("VerifyChainOfCustody", function(evidenceId)
    return Nyx.Judiciary.VerifyChainOfCustody(evidenceId)
end)

exports("ConcludeTrial", function(docketId, verdictRuling)
    return Nyx.Judiciary.ConcludeTrial(docketId, verdictRuling)
end)

-- Penal Labor & Correctional Rehabilitation
exports("IncarcerateCitizen", function(citizenId, sentenceMonths, cellAssigned)
    return Nyx.Judiciary.IncarcerateCitizen(citizenId, sentenceMonths, cellAssigned)
end)

exports("GetPenalRecord", function(citizenId)
    return Nyx.Judiciary.GetPenalRecord(citizenId)
end)

exports("GetWorkshopSupplies", function(stashId)
    return Nyx.Judiciary.GetWorkshopSupplies(stashId)
end)

exports("ExecuteLaborCycle", function(src, payload)
    return Nyx.Judiciary.ExecuteLaborCycle(src, payload)
end)

exports("ReleaseInmate", function(citizenId, optionalSrc)
    return Nyx.Judiciary.ReleaseInmate(citizenId, optionalSrc)
end)

exports("GetPenalLaborLogs", function(citizenId, limit)
    return Nyx.Judiciary.GetPenalLaborLogs(citizenId, limit)
end)

