--[[
    Nyxframework: nyx_parliament
    File: server/exports.lua
    Description: Clean public server exports for law queries, fine retrieval, and election tabulation.
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
