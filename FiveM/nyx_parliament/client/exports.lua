--[[
    Nyxframework: nyx_parliament
    File: client/exports.lua
    Description: Clean public client exports for parliament and election UI controls.
]]

Nyx = Nyx or {}

exports("OpenVotingUI", function()
    Nyx.Parliament.OpenVotingUI()
end)

exports("CloseVotingUI", function()
    Nyx.Parliament.CloseVotingUI()
end)

exports("IsVotingUIOpen", function()
    return Nyx.Parliament.IsOpen
end)
