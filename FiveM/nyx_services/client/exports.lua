--[[
    Nyxframework: nyx_services
    File: client/exports.lua
    Description: Client export wrappers for power grid and utility state.
]]

exports("IsPlayerInBlackout", function()
    return IsPlayerInBlackout and IsPlayerInBlackout() or false
end)
