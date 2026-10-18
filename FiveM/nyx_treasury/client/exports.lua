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
