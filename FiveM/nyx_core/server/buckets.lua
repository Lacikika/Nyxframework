--[[
    Nyxframework: nyx_core
    File: server/buckets.lua
    Description: Virtual routing bucket manager isolating pre-spawn players from the world.
]]

Nyx = Nyx or {}
Nyx.Buckets = {}

-- Assign a connecting player to an isolated virtual limbo bucket (1000 + source)
function Nyx.Buckets.SetLimbo(src)
    local sourceNum = tonumber(src)
    if not sourceNum then return end

    local virtualBucket = (Config.VirtualBucketOffset or 1000) + sourceNum

    -- Isolate network traffic and disable NPC/traffic population
    SetPlayerRoutingBucket(tostring(sourceNum), virtualBucket)
    if SetRoutingBucketPopulationEnabled then
        SetRoutingBucketPopulationEnabled(virtualBucket, false)
    end
    if SetRoutingBucketEntityLockdownMode then
        SetRoutingBucketEntityLockdownMode(virtualBucket, "strict")
    end
    if Player and Player(sourceNum) and Player(sourceNum).state then
        Player(sourceNum).state.routingBucket = virtualBucket
    end

    if Config.Debug then
        print(string.format("^4[Nyx:Buckets]^7 Assigned source %d to virtual limbo bucket %d^7", sourceNum, virtualBucket))
    end
end

-- Reset player routing bucket to the public world (default 0)
function Nyx.Buckets.SetDefault(src)
    local sourceNum = tonumber(src)
    if not sourceNum then return end

    local defaultBucket = Config.DefaultRoutingBucket or 0
    SetPlayerRoutingBucket(tostring(sourceNum), defaultBucket)
    if Player and Player(sourceNum) and Player(sourceNum).state then
        Player(sourceNum).state.routingBucket = defaultBucket
    end

    if Config.Debug then
        print(string.format("^4[Nyx:Buckets]^7 Restored source %d to public routing bucket %d^7", sourceNum, defaultBucket))
    end
end

-- Explicit custom routing bucket setter
function Nyx.Buckets.Set(src, bucketId)
    local sourceNum = tonumber(src)
    local bucketNum = tonumber(bucketId)
    if not sourceNum or not bucketNum then return end

    SetPlayerRoutingBucket(tostring(sourceNum), bucketNum)
    if Player and Player(sourceNum) and Player(sourceNum).state then
        Player(sourceNum).state.routingBucket = bucketNum
    end
end

-- Query current routing bucket
function Nyx.Buckets.Get(src)
    local sourceNum = tonumber(src)
    if not sourceNum then return 0 end
    return GetPlayerRoutingBucket(tostring(sourceNum))
end

-- Explicit custom entity routing bucket setter
function Nyx.Buckets.SetEntity(entity, bucketId)
    local bucketNum = tonumber(bucketId) or 0
    if not entity or not DoesEntityExist(entity) then return false end
    SetEntityRoutingBucket(entity, bucketNum)
    return true
end

-- Query current entity routing bucket
function Nyx.Buckets.GetEntity(entity)
    if not entity or not DoesEntityExist(entity) then return 0 end
    return GetEntityRoutingBucket(entity)
end

-- Configure properties of a virtual routing bucket
function Nyx.Buckets.ConfigureBucket(bucketId, populationEnabled, entityWipe)
    local bucketNum = tonumber(bucketId)
    if not bucketNum then return end
    if SetRoutingBucketPopulationEnabled then
        SetRoutingBucketPopulationEnabled(bucketNum, populationEnabled == true)
    end
    if SetRoutingBucketEntityLockdownMode then
        SetRoutingBucketEntityLockdownMode(bucketNum, entityWipe == true and "strict" or "relaxed")
    end
end

