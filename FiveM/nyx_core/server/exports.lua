--[[
    Nyxframework: nyx_core
    File: server/exports.lua
    Description: Clean public server export wrappers for other modular framework resources.
]]

Nyx = Nyx or {}

-- Player Registry Lookups
exports("GetPlayer", function(src)
    return Nyx.GetPlayer(src)
end)

exports("GetPlayerByCitizenId", function(citizenId)
    return Nyx.GetPlayerByCitizenId(citizenId)
end)

exports("GetPlayers", function()
    return Nyx.GetPlayers()
end)

-- RPC Registration & Dispatch
exports("RegisterRPC", function(route, handler)
    Nyx.RPC.Register(route, handler)
end)

exports("TriggerClientRPC", function(src, route, ...)
    return Nyx.RPC.TriggerClient(src, route, ...)
end)

-- Virtual Routing Bucket Controls
exports("SetLimbo", function(src)
    Nyx.Buckets.SetLimbo(src)
end)

exports("SetDefaultBucket", function(src)
    Nyx.Buckets.SetDefault(src)
end)

exports("SetRoutingBucket", function(src, bucketId)
    Nyx.Buckets.Set(src, bucketId)
end)

exports("GetRoutingBucket", function(src)
    return Nyx.Buckets.Get(src)
end)

-- Player Inventory Weight Management
exports("UpdatePlayerWeight", function(src, currentWeight, maxWeight, ratio)
    local player = Nyx.GetPlayer(src)
    if not player then return nil end
    return player:setWeight(currentWeight, maxWeight)
end)

exports("GetPlayerWeight", function(src)
    local player = Nyx.GetPlayer(src)
    if not player then return 0, 30000, 0.0 end
    local w = player:getWeight()
    return w.current or 0, w.max or 30000, w.ratio or 0.0
end)
