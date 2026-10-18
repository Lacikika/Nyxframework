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

-- Multi-Signature Vault
exports("InitiateWithdrawal", function(src, factionId, targetAccount, amount, reason)
    return Nyx.Factions.InitiateWithdrawal(src, factionId, targetAccount, amount, reason)
end)

exports("ApproveMultiSigRequest", function(src, requestId)
    return Nyx.Factions.ApproveMultiSigRequest(src, requestId)
end)

exports("RejectMultiSigRequest", function(src, requestId, reason)
    return Nyx.Factions.RejectMultiSigRequest(src, requestId, reason)
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
