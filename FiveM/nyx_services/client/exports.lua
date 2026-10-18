--[[
    Nyxframework: nyx_services
    File: client/exports.lua
    Description: Client export wrappers for power grid and utility state.
]]

exports("IsPlayerInBlackout", function()
    return IsPlayerInBlackout and IsPlayerInBlackout() or false
end)

exports("IsCoordsPowered", function(coords)
    return IsCoordsPowered and IsCoordsPowered(coords) or true
end)

exports("GetActiveBlackouts", function()
    return GetActiveBlackouts and GetActiveBlackouts() or {}
end)

exports("GetNearestFarm", function(maxDist)
    return Nyx.Services and Nyx.Services.GetNearestFarm and Nyx.Services.GetNearestFarm(maxDist)
end)

exports("GetNearestPantry", function(maxDist)
    return Nyx.Services and Nyx.Services.GetNearestPantry and Nyx.Services.GetNearestPantry(maxDist)
end)

exports("IsHarvestingCrop", function()
    return Nyx.Services and Nyx.Services.IsHarvesting and Nyx.Services.IsHarvesting() or false
end)

exports("GetNearestTransformer", function(maxDist)
    return Nyx.Services and Nyx.Services.GetNearestTransformer and Nyx.Services.GetNearestTransformer(maxDist)
end)

exports("IsSabotaging", function()
    return isSabotaging or false
end)
