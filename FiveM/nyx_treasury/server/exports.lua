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
    return (state == "CRITICAL_DEFICIT" or Nyx.Treasury.IsCircuitTripped())
end)
