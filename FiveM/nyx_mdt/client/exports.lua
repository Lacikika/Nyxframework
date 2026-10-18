--[[
    Nyxframework: nyx_mdt
    File: client/exports.lua
    Description: Public client exports for opening MDT terminal.
]]

exports('OpenMDT', function()
    ExecuteCommand("mdt")
end)
