--[[
    Nyxframework: nyx_treasury
    File: server/exports.lua
    Description: Clean public server exports for treasury operations, transfers, and tax calculation.
]]

Nyx = Nyx or {}

exports("ExecuteTransfer", function(debitAcc, creditAcc, amount, category, authorizedBy, memo, taxDeducted)
    return Nyx.Treasury.ExecuteTransfer(debitAcc, creditAcc, amount, category, authorizedBy, memo, taxDeducted)
end)

exports("ProcessPOSTransaction", function(buyerAcc, sellerAcc, grossAmount, memo)
    return Nyx.Treasury.ProcessPOSTransaction(buyerAcc, sellerAcc, grossAmount, memo)
end)

exports("ProcessP2PTransfer", function(senderCitizenId, receiverCitizenId, grossAmount, memo)
    return Nyx.Treasury.ProcessP2PTransfer(senderCitizenId, receiverCitizenId, grossAmount, memo)
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

exports("TriggerPayroll", function()
    Nyx.Treasury.ProcessPublicPayroll()
end)
