--[[
    Nyxframework: nyx_factions
    File: client/exports.lua
    Description: Clean client exports for faction terminal proximity and depot state.
]]

exports("GetTerminals", function()
    return Config.Terminals or {}
end)

exports("GetFleetDepots", function()
    return Config.FleetDepots or {}
end)

exports("GetVaultsConfig", function()
    return Config.Vaults or {}
end)
