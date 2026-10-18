--[[
    Nyxframework: nyx_treasury
    File: server/exports.lua
    Description: Clean public server exports for treasury operations, transfers, and tax calculation.
]]

Nyx = Nyx or {}

exports("ExecuteTransfer", function(debitAcc, creditAcc, amount, category, authorizedBy, memo, taxDeducted)
    return Nyx.Treasury.ExecuteTransfer(debitAcc, creditAcc, amount, category, authorizedBy, memo, taxDeducted)
end)

exports("ProcessPOSTransaction", function(buyerAcc, sellerAcc, grossAmount, memo, zoneId)
    return Nyx.Treasury.ProcessPOSTransaction(buyerAcc, sellerAcc, grossAmount, memo, zoneId)
end)

exports("ProcessP2PTransfer", function(senderCitizenId, receiverCitizenId, grossAmount, memo)
    return Nyx.Treasury.ProcessP2PTransfer(senderCitizenId, receiverCitizenId, grossAmount, memo)
end)

exports("CalculateTaxSplit", function(grossAmount, rate, zoneId)
    return Nyx.Treasury.CalculateTaxSplit(grossAmount, rate, zoneId)
end)

exports("GetZoneTaxRate", function(zoneId)
    return Nyx.Treasury.GetZoneTaxRate(zoneId)
end)

exports("GetAccountBalance", function(accountId)
    return Nyx.Treasury.GetBalance(accountId)
end)

exports("GetWageMultiplier", function()
    return Nyx.Treasury.GetWageMultiplier()
end)

exports("SetTaxRate", function(taxType, newRate, ratifiedBy)
    return Nyx.Treasury.SetTaxRate(taxType, newRate, ratifiedBy)
end)

exports("GetConsumerPriceIndex", function()
    local ok, summary = pcall(function()
        return exports['nyx_logistics']:GetMarketSummary()
    end)
    if ok and summary then
        return summary.citywideCpi, summary.zones
    end
    return 1.0, {}
end)

exports("TriggerPayroll", function()
    return Nyx.Treasury.ProcessPublicPayroll()
end)

exports("GetFiscalState", function()
    return Nyx.Treasury.GetFiscalState()
end)

exports("IsCircuitBreakerTripped", function()
    return Nyx.Treasury.IsCircuitTripped()
end)

exports("TripFiscalCircuit", function(reason, authorizedBy)
    return Nyx.Treasury.TripCircuitBreaker(reason, authorizedBy)
end)

exports("ResetFiscalCircuit", function(authorizedBy, reason)
    return Nyx.Treasury.ResetCircuitBreaker(authorizedBy, reason)
end)

exports("GetDrainVelocity", function()
    return Nyx.Treasury.GetDrainVelocity()
end)

exports("GetCircuitTelemetry", function()
    return Nyx.Treasury.GetCircuitTelemetry()
end)

exports("IsMunicipalDegraded", function()
    local state = Nyx.Treasury.GetFiscalState()
    return (state == "CRITICAL_DEFICIT" or Nyx.Treasury.IsCircuitTripped() or Nyx.Treasury.IsInfrastructureDegraded())
end)

exports("GetMunicipalFiscalTier", function()
    return Nyx.Treasury.GetMunicipalFiscalTier()
end)

exports("GetMunicipalFiscalState", function()
    return Nyx.Treasury.GetMunicipalFiscalState()
end)

exports("IsInfrastructureDegraded", function()
    return Nyx.Treasury.IsInfrastructureDegraded()
end)

exports("IsMunicipalBankrupt", function()
    return Nyx.Treasury.IsMunicipalBankrupt()
end)

exports("CalculateImpoundReleaseCost", function(baseFee, daysImpounded, dailyRate)
    local tier = Nyx.Treasury.GetMunicipalFiscalTier()
    return Nyx.Degradation.CalculateImpoundReleaseCost(baseFee, daysImpounded, dailyRate, tier)
end)

exports("CalculatePublicRepairCost", function(baseLabor, damageRatio, partsMultiplier, hasRepairKit)
    local tier = Nyx.Treasury.GetMunicipalFiscalTier()
    return Nyx.Degradation.CalculatePublicRepairCost(baseLabor, damageRatio, partsMultiplier, tier, hasRepairKit)
end)

-- Judicial Subpoena Forensic Audit Exports
exports("ExecuteSubpoenaAudit", function(src, warrantId, targetType, targetId)
    return Nyx.Treasury.ExecuteSubpoenaAudit(src, warrantId, targetType, targetId)
end)

exports("GetSubpoenaAuditReport", function(auditUuid)
    return Nyx.Treasury.GetSubpoenaAuditReport(auditUuid)
end)

exports("FreezeCommercialTarget", function(src, warrantId, targetType, targetId, reason)
    return Nyx.Treasury.FreezeCommercialTarget(src, warrantId, targetType, targetId, reason)
end)

-- Armored Cash Transit & Bank Vault Exports
exports("DepositCashTransitBox", function(src, boxUuid, vaultId)
    return Nyx.Treasury.DepositCashTransitBox(src, boxUuid, vaultId)
end)

exports("BreachCashTransitBox", function(src, toolName)
    return Nyx.Treasury.BreachCashTransitBox(src, toolName)
end)

exports("GetBankVaults", function()
    return Nyx.Treasury.GetBankVaults()
end)

exports("GetCashTransitBox", function(boxUuid)
    return Nyx.Treasury.GetCashTransitBox(boxUuid)
end)

exports("GetTransitHistory", function(factionId)
    return Nyx.Treasury.GetTransitHistory(factionId)
end)

-- Auditable Public Treasury Ledger & Allocation Monitor Exports
exports("GetBalanceSheet", function()
    local dbAccounts = MySQL.query.await("SELECT `account_id`, `label`, `balance`, `type`, `circuit_exempt` FROM `nyx_treasury_accounts`") or {}
    return Nyx.PublicLedger.CalculateBalanceSheet(dbAccounts, Config.TargetReserve or 5000000.00, Config.CriticalReserve or 500000.00)
end)

exports("GetPublicOverview", function()
    local dbAccounts = MySQL.query.await("SELECT `account_id`, `label`, `balance`, `type`, `circuit_exempt` FROM `nyx_treasury_accounts`") or {}
    local sheet = Nyx.PublicLedger.CalculateBalanceSheet(dbAccounts, Config.TargetReserve or 5000000.00, Config.CriticalReserve or 500000.00)
    local master = Nyx.Treasury.GetBalance(Config.Accounts.Master or "gov:city:master")
    local telemetry = Nyx.PublicLedger.CalculateFiscalTelemetry(master, Nyx.Treasury.GetCircuitTelemetry(), Config.TargetReserve, Config.CriticalReserve, Config.CautionReserve)
    return {
        balanceSheet = sheet,
        fiscalTelemetry = telemetry
    }
end)

exports("ExecuteRevenueSweep", function(executedBy)
    return Nyx.Treasury.SweepTaxes(executedBy)
end)

exports("GetRevenueSweeps", function(limit)
    limit = math.max(1, math.min(50, tonumber(limit) or 15))
    return MySQL.query.await("SELECT * FROM `nyx_treasury_revenue_sweeps` ORDER BY `sweep_id` DESC LIMIT ?", { limit }) or {}
end)

