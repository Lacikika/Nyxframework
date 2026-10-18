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

-- Dividends & Equity
exports("DistributeDividends", function(factionId, netProfit, rate, executingCitizenId)
    return Nyx.Factions.DistributeDividends(factionId, netProfit, rate, executingCitizenId)
end)

exports("PreviewDividends", function(factionId, netProfit, rate)
    return Nyx.Factions.PreviewDividends(factionId, netProfit, rate)
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
