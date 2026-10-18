--[[
    Nyxframework: nyx_core
    File: client/exports.lua
    Description: Clean public client export wrappers for other modular framework resources.
]]

Nyx = Nyx or {}

exports("GetPlayerData", function()
    return Nyx.Client.PlayerData
end)

exports("IsPlayerLoaded", function()
    return Nyx.Client.IsLoaded
end)

exports("TriggerRPC", function(route, ...)
    return Nyx.RPC.Trigger(route, ...)
end)

exports("TriggerRPCAwait", function(route, ...)
    return Nyx.RPC.TriggerAwait(route, ...)
end)

exports("RegisterClientRPC", function(route, handler)
    Nyx.RPC.Register(route, handler)
end)
