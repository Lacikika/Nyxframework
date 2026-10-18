--[[
    Nyxframework: nyx_factions
    File: server/exports.lua
    Description: Clean public server exports for organizations, RBAC permissions,
                 multi-sig vaults, dividends, and commercial fleets.
]]

Nyx = Nyx or {}

-- Charters & Overview
exports("CreateCharter", function(src, legalName, charterType, initialDeposit)
    return Nyx.Factions.CreateCharter(src, legalName, charterType, initialDeposit)
end)

exports("GetFaction", function(factionId)
    return Nyx.Factions.GetFaction(factionId)
end)

exports("GetFactionOverview", function(factionId)
    return Nyx.Factions.GetFactionOverview(factionId)
end)

-- RBAC Permissions & Members
exports("HasPermission", function(citizenId, factionId, requiredNode)
    return Nyx.Factions.HasPermission(citizenId, factionId, requiredNode)
end)

exports("AddMember", function(actorCitizenId, factionId, targetCitizenId, roleTitle, nodes, equity, wage)
    return Nyx.Factions.AddMember(actorCitizenId, factionId, targetCitizenId, roleTitle, nodes, equity, wage)
end)

exports("UpdateMember", function(actorCitizenId, factionId, targetCitizenId, roleTitle, nodes, equity, wage)
    return Nyx.Factions.UpdateMember(actorCitizenId, factionId, targetCitizenId, roleTitle, nodes, equity, wage)
end)

exports("RemoveMember", function(actorCitizenId, factionId, targetCitizenId)
    return Nyx.Factions.RemoveMember(actorCitizenId, factionId, targetCitizenId)
end)

exports("GetFactionMembers", function(factionId)
    return Nyx.Factions.GetFactionMembers(factionId)
end)

-- Corporate Treasury Vaults
exports("GetFactionVaults", function(factionId)
    return Nyx.Factions.GetFactionVaults(factionId)
end)

exports("GetVault", function(vaultId)
    return Nyx.Factions.GetVault(vaultId)
end)

exports("CreateVault", function(actorCitizenId, factionId, vaultLabel, dailyLimit)
    return Nyx.Factions.CreateVault(actorCitizenId, factionId, vaultLabel, dailyLimit)
end)

exports("SetVaultFreeze", function(actorCitizenId, factionId, vaultId, isFrozen, reason)
    return Nyx.Factions.SetVaultFreeze(actorCitizenId, factionId, vaultId, isFrozen, reason)
end)

exports("TransferVaultFunds", function(actorCitizenId, factionId, fromVaultId, toVaultId, amount, memo)
    return Nyx.Factions.TransferVaultFunds(actorCitizenId, factionId, fromVaultId, toVaultId, amount, memo)
end)

exports("DepositToVault", function(src, factionId, vaultId, amount)
    return Nyx.Factions.DepositToVault(src, factionId, vaultId, amount)
end)

-- Granular Sign-Off Rules
exports("GetSignoffRules", function(factionId, vaultId)
    return Nyx.Factions.GetSignoffRules(factionId, vaultId)
end)

exports("EvaluateSignoffRule", function(factionId, vaultId, amount)
    return Nyx.Factions.EvaluateSignoffRule(factionId, vaultId, amount)
end)

exports("SetSignoffRule", function(actorCitizenId, factionId, ruleData)
    return Nyx.Factions.SetSignoffRule(actorCitizenId, factionId, ruleData)
end)

exports("DeleteSignoffRule", function(actorCitizenId, factionId, ruleId)
    return Nyx.Factions.DeleteSignoffRule(actorCitizenId, factionId, ruleId)
end)

-- Multi-Signature Vault Requests
exports("InitiateWithdrawal", function(src, factionId, vaultId, targetAccount, amount, reason)
    -- Backward compatibility: If 5 args passed (no vaultId), shift parameters
    if reason == nil and type(amount) == "string" then
        return Nyx.Factions.InitiateWithdrawal(src, factionId, nil, vaultId, targetAccount, amount)
    end
    return Nyx.Factions.InitiateWithdrawal(src, factionId, vaultId, targetAccount, amount, reason)
end)

exports("ApproveMultiSigRequest", function(src, requestId, note)
    return Nyx.Factions.ApproveMultiSigRequest(src, requestId, note)
end)

exports("RejectMultiSigRequest", function(src, requestId, reason)
    return Nyx.Factions.RejectMultiSigRequest(src, requestId, reason)
end)

exports("CancelMultiSigRequest", function(src, requestId, reason)
    return Nyx.Factions.CancelMultiSigRequest(src, requestId, reason)
end)

exports("ExecuteTimelockedMultiSig", function(src, requestId)
    return Nyx.Factions.ExecuteTimelockedMultiSig(src, requestId)
end)

exports("GetMultiSigAuditLog", function(factionId, limit)
    return Nyx.Factions.GetMultiSigAuditLog(factionId, limit)
end)

-- Dividends & Equity Public Offerings
exports("DistributeDividends", function(factionId, netProfit, rate, executingCitizenId)
    return Nyx.Factions.DistributeDividends(factionId, netProfit, rate, executingCitizenId)
end)

exports("PreviewDividends", function(factionId, netProfit, rate)
    return Nyx.Factions.PreviewDividends(factionId, netProfit, rate)
end)

exports("ProcessAutomatedDividendCycles", function()
    return Nyx.Factions.ProcessAutomatedDividendCycles()
end)

exports("GetDividendHistory", function(factionId, limit)
    return Nyx.Factions.GetDividendHistory(factionId, limit)
end)

exports("GetConsolidatedCapTable", function(factionId)
    return Nyx.Factions.GetConsolidatedCapTable(factionId)
end)

exports("CreatePublicOffering", function(actorCitizenId, factionId, data)
    return Nyx.Factions.CreatePublicOffering(actorCitizenId, factionId, data)
end)

exports("PurchaseEquityShares", function(investorCitizenId, offeringId, sharesRequested)
    return Nyx.Factions.PurchaseEquityShares(investorCitizenId, offeringId, sharesRequested)
end)

exports("CancelPublicOffering", function(actorCitizenId, offeringId, reason)
    return Nyx.Factions.CancelPublicOffering(actorCitizenId, offeringId, reason)
end)

exports("GetPublicOfferings", function(statusFilter)
    return Nyx.Factions.GetPublicOfferings(statusFilter)
end)

exports("GetOfferingDetails", function(offeringId)
    return Nyx.Factions.GetOfferingDetails(offeringId)
end)

exports("GetCitizenPortfolio", function(citizenId)
    return Nyx.Factions.GetCitizenPortfolio(citizenId)
end)

-- Commercial Fleets
exports("RegisterFleetVehicle", function(actorCitizenId, factionId, modelHash, depotId, customPlate)
    return Nyx.Factions.RegisterVehicle(actorCitizenId, factionId, modelHash, depotId, customPlate)
end)

exports("SpawnFleetVehicle", function(src, factionId, vin, depotId)
    return Nyx.Factions.SpawnVehicle(src, factionId, vin, depotId)
end)

exports("StoreFleetVehicle", function(src, factionId, vin, depotId, conditionData)
    return Nyx.Factions.StoreVehicle(src, factionId, vin, depotId, conditionData)
end)

exports("GetFactionFleet", function(factionId)
    return Nyx.Factions.GetFactionFleet(factionId)
end)

-- Trade Unions & Collective Bargaining
exports("RegisterUnion", function(src, legalName, industrySector, duesAmount, duesMode)
    return Nyx.Factions.RegisterUnion(src, legalName, industrySector, duesAmount, duesMode)
end)

exports("JoinUnion", function(src, unionId, enterpriseFactionId)
    return Nyx.Factions.JoinUnion(src, unionId, enterpriseFactionId)
end)

exports("LeaveUnion", function(src, unionId)
    return Nyx.Factions.LeaveUnion(src, unionId)
end)

exports("GetUnion", function(unionId)
    return Nyx.Factions.GetUnion(unionId)
end)

exports("GetAllUnions", function()
    return Nyx.Factions.GetAllUnions()
end)

exports("GetCitizenUnionMembership", function(citizenId)
    return Nyx.Factions.GetCitizenUnionMembership(citizenId)
end)

exports("ProcessUnionDues", function(citizenId, grossWage, enterpriseFactionId)
    return Nyx.Factions.ProcessUnionDues(citizenId, grossWage, enterpriseFactionId)
end)

exports("DepositStrikeFund", function(src, unionId, amount)
    return Nyx.Factions.DepositStrikeFund(src, unionId, amount)
end)

exports("ClaimStrikeRelief", function(src, unionId)
    return Nyx.Factions.ClaimStrikeRelief(src, unionId)
end)

exports("ProposeCBA", function(src, unionId, enterpriseFactionId, title, wageFloor, overtimeMultiplier, hazardBonus)
    return Nyx.Factions.ProposeCBA(src, unionId, enterpriseFactionId, title, wageFloor, overtimeMultiplier, hazardBonus)
end)

exports("RatifyCBA", function(src, cbaId)
    return Nyx.Factions.RatifyCBA(src, cbaId)
end)

exports("GetEnterpriseCBA", function(enterpriseFactionId)
    return Nyx.Factions.GetEnterpriseCBA(enterpriseFactionId)
end)

exports("CallStrikeVote", function(src, unionId, enterpriseFactionId, reason)
    return Nyx.Factions.CallStrikeVote(src, unionId, enterpriseFactionId, reason)
end)

exports("CastStrikeVote", function(src, strikeId, vote)
    return Nyx.Factions.CastStrikeVote(src, strikeId, vote)
end)

exports("IsEnterpriseOnStrike", function(enterpriseFactionId)
    return Nyx.Factions.IsEnterpriseOnStrike(enterpriseFactionId)
end)

exports("EndStrike", function(strikeId, resolutionReason)
    return Nyx.Factions.EndStrike(strikeId, resolutionReason)
end)

exports("PetitionLaborArbitration", function(src, strikeId)
    return Nyx.Factions.PetitionLaborArbitration(src, strikeId)
end)

exports("ExecuteArbitrationAward", function(arbitratorCitId, strikeId, underpaidHours, hourlyDeficit, penaltyRate, revisedWageFloor)
    return Nyx.Factions.ExecuteArbitrationAward(arbitratorCitId, strikeId, underpaidHours, hourlyDeficit, penaltyRate, revisedWageFloor)
end)

-- Inactivity & Succession Exports
exports("CheckFactionInactivity", function()
    if Nyx.Factions.CheckFactionInactivity then
        return Nyx.Factions.CheckFactionInactivity()
    end
    return nil
end)

exports("SetFactionStewardDelegate", function(src, factionId, delegateCitizenId)
    if Nyx.Factions.SetFactionStewardDelegate then
        return Nyx.Factions.SetFactionStewardDelegate(src, factionId, delegateCitizenId)
    end
    return false, "UNAVAILABLE"
end)

exports("GetFactionInactivityStatus", function(factionId)
    return MySQL.single.await([[
        SELECT `faction_id`, `legal_name`, `founder_citizen_id`, `steward_delegate_citizen_id`,
               `inactivity_status`, `inactivity_warning_at`, `is_active`
        FROM `nyx_factions_registry`
        WHERE `faction_id` = ?
    ]], { factionId })
end)

-- Corporate RBAC & Citizen Organizations
exports("GetCitizenFactions", function(citizenId)
    return Nyx.Factions.GetCitizenFactions(citizenId)
end)

exports("GetRBACAuditLog", function(factionId, limit)
    return Nyx.Factions.GetRBACAuditLog(factionId, limit)
end)

-- Commercial Front Registers & Laundering Exports
exports("GetCommercialRegister", function(registerId)
    return Nyx.Laundering.GetRegister(registerId)
end)

exports("GetFactionCommercialRegisters", function(factionId)
    return Nyx.Laundering.GetFactionRegisters(factionId)
end)

exports("InjectDirtyCash", function(src, payload)
    return Nyx.Laundering.InjectDirtyCash(src, payload)
end)

exports("ProcessRegisterLaunderingTick", function(registerId)
    return Nyx.Laundering.ProcessRegisterLaunderingTick(registerId)
end)

exports("FreezeRegister", function(registerId, judgeCitId, reason)
    return Nyx.Laundering.FreezeRegister(registerId, judgeCitId, reason)
end)

exports("UnfreezeRegister", function(registerId, judgeCitId)
    return Nyx.Laundering.UnfreezeRegister(registerId, judgeCitId)
end)
