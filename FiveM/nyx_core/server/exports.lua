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

-- RPC Security, Rate Limiting & Payload Bounds
exports("CheckRPCRateLimit", function(src, route, customCost)
    return Nyx.RPC.CheckRateLimit(src, route, customCost)
end)

exports("GetRPCRateLimitState", function(src)
    return Nyx.RPC.GetRateLimitState(src)
end)

exports("ResetRPCRateLimit", function(src)
    Nyx.RPC.ResetRateLimit(src)
end)

exports("IsRPCPayloadValid", function(payload, customCap)
    return Nyx.RPC.IsPayloadWithinBounds(payload, customCap)
end)

exports("GetRPCRateLimitMetrics", function()
    return Nyx.RPC.GetRateLimitMetrics()
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

exports("SetEntityRoutingBucket", function(entity, bucketId)
    return Nyx.Buckets.SetEntity(entity, bucketId)
end)

exports("GetEntityRoutingBucket", function(entity)
    return Nyx.Buckets.GetEntity(entity)
end)


-- Player Inventory Weight Management & Heavy Freight Physics
exports("UpdatePlayerWeight", function(src, currentWeight, maxWeight, ratio)
    local player = Nyx.GetPlayer(src)
    if not player then return nil end
    return player:setWeight(currentWeight, maxWeight)
end)

exports("GetPlayerWeight", function(src)
    local defaultMax = (Config.WeightPenalties and Config.WeightPenalties.defaultPlayerCapacity) or 60000
    local player = Nyx.GetPlayer(src)
    if not player then return 0, defaultMax, 0.0 end
    local w = player:getWeight()
    return w.current or 0, w.max or defaultMax, w.ratio or 0.0
end)

exports("SetPlayerHeavyFreight", function(src, isCarrying, dropId, model)
    local player = Nyx.GetPlayer(src)
    if not player then return false end
    return player:setHeavyFreight(isCarrying, dropId, model)
end)

exports("IsPlayerCarryingHeavyFreight", function(src)
    local player = Nyx.GetPlayer(src)
    if not player then return false end
    return player.isCarryingHeavyFreight == true
end)

exports("CalculateWeightTier", function(ratio, isHeavyFreight)
    if Nyx.Weights and Nyx.Weights.CalculateTier then
        return Nyx.Weights.CalculateTier(ratio, isHeavyFreight)
    end
    return "tier_0", { label = "TIER_0", moveRate = 1.0, sprintAllowed = true, jumpAllowed = true, climbAllowed = true }
end)

exports("GetWeightTierData", function(tierKey)
    if Nyx.Weights and Nyx.Weights.GetTier then
        return Nyx.Weights.GetTier(tierKey)
    end
    return nil
end)

exports("IsHeavyFreightWeight", function(grams)
    if Nyx.Weights and Nyx.Weights.IsHeavyFreight then
        return Nyx.Weights.IsHeavyFreight(grams)
    end
    return (tonumber(grams) or 0) > 50000
end)

-- Staggered Resource Bootloader Exports
exports("RegisterBootStage", function(resourceName, stage, priority, callback)
    if Nyx.Bootloader and Nyx.Bootloader.RegisterBootStage then
        return Nyx.Bootloader.RegisterBootStage(resourceName, stage, priority, callback)
    end
    return false
end)

exports("IsDatabaseReady", function()
    if Nyx.Bootloader and Nyx.Bootloader.IsDatabaseReady then
        return Nyx.Bootloader.IsDatabaseReady()
    end
    return false
end)

exports("IsBootComplete", function()
    if Nyx.Bootloader and Nyx.Bootloader.IsBootComplete then
        return Nyx.Bootloader.IsBootComplete()
    end
    return false
end)

exports("GetBootState", function()
    if Nyx.Bootloader and Nyx.Bootloader.GetBootState then
        return Nyx.Bootloader.GetBootState()
    end
    return "UNKNOWN"
end)

exports("GetBootReport", function()
    if Nyx.Bootloader and Nyx.Bootloader.GetBootReport then
        return Nyx.Bootloader.GetBootReport()
    end
    return nil
end)

exports("AwaitDatabase", function()
    if Nyx.Bootloader and Nyx.Bootloader.AwaitDatabase then
        return Nyx.Bootloader.AwaitDatabase()
    end
    return true
end)

exports("AwaitBootStage", function(stageOrResource)
    if Nyx.Bootloader and Nyx.Bootloader.AwaitBootStage then
        return Nyx.Bootloader.AwaitBootStage(stageOrResource)
    end
    return true
end)

exports("DispatchBootloader", function(customStaggerMs)
    if Nyx.Bootloader and Nyx.Bootloader.Dispatch then
        return Nyx.Bootloader.Dispatch(customStaggerMs)
    end
    return false, "BOOTLOADER_NOT_LOADED"
end)

-- 14-Resource End-to-End Stress Simulation & Idle Benchmarking
exports("RunStressSimulation", function(options)
    if Nyx.StressSimulation and Nyx.StressSimulation.ExecuteRun then
        return Nyx.StressSimulation.ExecuteRun(options)
    end
    return false, "STRESS_SIMULATION_NOT_LOADED"
end)

exports("GetLastStressRunResults", function()
    if Nyx.StressSimulation and Nyx.StressSimulation.GetLastRunResults then
        return Nyx.StressSimulation.GetLastRunResults()
    end
    return nil
end)

exports("IsStressSimulationRunning", function()
    if Nyx.StressSimulation and Nyx.StressSimulation.IsRunning then
        return Nyx.StressSimulation.IsRunning()
    end
    return false
end)

exports("ProfileBaselineIdlePerformance", function(samples)
    if Nyx.StressSimulation and Nyx.StressSimulation.ProfileBaselineIdlePerformance then
        return Nyx.StressSimulation.ProfileBaselineIdlePerformance(samples)
    end
    return nil
end)

