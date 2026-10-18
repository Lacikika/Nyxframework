--[[
    Nyxframework: nyx_treasury
    File: client/exports.lua
    Description: Clean public client exports for opening and closing civic transparency terminals.
]]

Nyx = Nyx or {}

exports("OpenTreasuryDashboard", function()
    Nyx.Treasury.OpenTerminal()
end)

exports("CloseTreasuryDashboard", function()
    Nyx.Treasury.CloseTerminal()
end)

exports("IsTreasuryDashboardOpen", function()
    return Nyx.Treasury.IsOpen
end)

exports("GetFiscalState", function()
    return GlobalState.fiscalState or "SOLVENT"
end)

exports("IsCircuitBreakerTripped", function()
    local cb = GlobalState.fiscalCircuitBreaker
    return (cb and cb.tripped == true) or false
end)

exports("IsMunicipalDegraded", function()
    return GlobalState.municipalDegraded == true
end)

exports("GetWageMultiplier", function()
    local cb = GlobalState.fiscalCircuitBreaker
    return (cb and cb.wageMultiplier) or 1.00
end)
