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

exports("GetMeterStatus", function(meterId, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("services:getMeter", function(res)
            if cb then cb(res and res.success, res and res.meter) end
        end, meterId)
    end
end)

exports("PayUtilityBill", function(meterId, amount, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("services:payUtilityBill", function(res)
            if cb then cb(res and res.success, res and res.data, res and res.error) end
        end, meterId, amount)
    end
end)
