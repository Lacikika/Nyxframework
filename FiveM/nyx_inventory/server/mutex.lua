--[[
    Nyxframework: nyx_inventory
    File: server/mutex.lua
    Description: Zero-duplication concurrency control and deadlock-free dual-container mutex locking.
]]

Nyx = Nyx or {}
Nyx.Inventory = Nyx.Inventory or {}
Nyx.Inventory.Locks = {} -- [invId] = expirationTimestampMs

-- Standardized RPC Bridge to nyx_core
Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        exports['nyx_core']:RegisterRPC(route, handler)
    end,
    GenerateNonce = function()
        local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        return (string.gsub(template, '[xy]', function(c)
            local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format('%x', v)
        end))
    end
}

-- Check if container currently holds an active non-expired mutex lock
function Nyx.Inventory.IsLocked(invId)
    if not invId then return false end
    local lockExpiry = Nyx.Inventory.Locks[invId]
    if not lockExpiry then return false end

    if GetGameTimer() >= lockExpiry then
        Nyx.Inventory.Locks[invId] = nil
        return false
    end

    return true
end

-- Acquire exclusive mutex lock on a single container
function Nyx.Inventory.AcquireLock(invId, timeoutMs)
    if not invId then return false end
    local now = GetGameTimer()

    if Nyx.Inventory.IsLocked(invId) then
        return false
    end

    local duration = timeoutMs or Config.MutexTimeout or 2000
    Nyx.Inventory.Locks[invId] = now + duration
    return true
end

-- Release exclusive mutex lock on a container
function Nyx.Inventory.ReleaseLock(invId)
    if not invId then return end
    Nyx.Inventory.Locks[invId] = nil
end

-- Acquire deadlock-free dual mutex locks on two containers (e.g. cross-inventory slot transfer)
-- Enforces strict lexicographical sorting order (Dijkstra resource hierarchy) to prevent circular deadlock
function Nyx.Inventory.AcquireDualLock(invIdA, invIdB, timeoutMs)
    if not invIdA or not invIdB then return false end

    -- Intra-container move
    if invIdA == invIdB then
        return Nyx.Inventory.AcquireLock(invIdA, timeoutMs)
    end

    local first = invIdA < invIdB and invIdA or invIdB
    local second = invIdA < invIdB and invIdB or invIdA

    if not Nyx.Inventory.AcquireLock(first, timeoutMs) then
        return false
    end

    if not Nyx.Inventory.AcquireLock(second, timeoutMs) then
        Nyx.Inventory.ReleaseLock(first)
        return false
    end

    return true
end

-- Release dual mutex locks
function Nyx.Inventory.ReleaseDualLock(invIdA, invIdB)
    if invIdA == invIdB then
        Nyx.Inventory.ReleaseLock(invIdA)
    else
        Nyx.Inventory.ReleaseLock(invIdA)
        Nyx.Inventory.ReleaseLock(invIdB)
    end
end

-- Scoped execution helper with guaranteed lock release
function Nyx.Inventory.WithLock(invId, fn)
    if not Nyx.Inventory.AcquireLock(invId) then
        return false, "CONTAINER_BUSY"
    end

    local ok, res, err = xpcall(fn, function(e)
        return debug.traceback(tostring(e), 2)
    end)

    Nyx.Inventory.ReleaseLock(invId)

    if not ok then
        print(string.format("^1[Nyx:Mutex] Exception in locked transaction on '%s': %s^7", invId, tostring(res)))
        return false, "INTERNAL_MUTEX_ERROR"
    end

    return res, err
end

-- Scoped dual execution helper with guaranteed dual lock release
function Nyx.Inventory.WithDualLock(invIdA, invIdB, fn)
    if not Nyx.Inventory.AcquireDualLock(invIdA, invIdB) then
        return false, "CONTAINER_BUSY"
    end

    local ok, res, err = xpcall(fn, function(e)
        return debug.traceback(tostring(e), 2)
    end)

    Nyx.Inventory.ReleaseDualLock(invIdA, invIdB)

    if not ok then
        print(string.format("^1[Nyx:Mutex] Exception in dual-locked transaction between '%s' and '%s': %s^7", invIdA, invIdB, tostring(res)))
        return false, "INTERNAL_MUTEX_ERROR"
    end

    return res, err
end
