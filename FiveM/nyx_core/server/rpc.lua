--[[
    Nyxframework: nyx_core
    File: server/rpc.lua
    Description: Server-side bidirectional RPC dispatcher with token-bucket rate limiting,
                 payload size enforcement, and error isolation.
]]

Nyx = Nyx or {}
Nyx.RPC = Nyx.RPC or {}

local registeredHandlers = {}
Nyx.RPC.Handlers = registeredHandlers
local pendingClientRequests = {}
local rateLimiters = {}

-- Rate Limiting: Token Bucket per source
local function checkRateLimit(src)
    local now = GetGameTimer()
    local cap = Config.RateLimit.capacity or 50
    local refill = Config.RateLimit.refillRate or 50
    local entry = rateLimiters[src]

    if not entry then
        entry = { tokens = cap - 1, lastRefill = now }
        rateLimiters[src] = entry
        return true
    end

    local deltaSec = (now - entry.lastRefill) / 1000.0
    entry.tokens = math.min(cap, entry.tokens + (deltaSec * refill))
    entry.lastRefill = now

    if entry.tokens < 1.0 then
        return false
    end

    entry.tokens = entry.tokens - 1.0
    return true
end

-- Register a server-side RPC handler
function Nyx.RPC.Register(route, handler)
    if not Nyx.RPC.IsValidRoute(route) then
        error(string.format("[Nyx:RPC] Invalid route name: '%s'", tostring(route)))
    end

    if registeredHandlers[route] then
        print(string.format("^3[Nyx:RPC] WARNING: Overwriting existing RPC route '%s'^7", route))
    end

    registeredHandlers[route] = handler
    if Config.Debug then
        print(string.format("^4[Nyx:RPC]^7 Registered server route: ^3%s^7", route))
    end
end

-- Incoming Client Request Dispatcher
RegisterNetEvent("nyx:core:rpc:request", function(nonce, route, args)
    local src = source

    -- 1. Validate Nonce & Route
    if type(nonce) ~= "string" or #nonce == 0 then
        return
    end

    if not Nyx.RPC.IsValidRoute(route) then
        TriggerClientEvent("nyx:core:rpc:response", src, nonce, false, nil, Nyx.RPC.Errors.INVALID_ROUTE)
        return
    end

    -- 2. Token Bucket Rate Limit Check
    if not checkRateLimit(src) then
        print(string.format("^1[Nyx:Security] RPC Rate limit exceeded by source %s on route '%s'!^7", src, route))
        if Config.RateLimit.actionOnExceed == "kick" then
            DropPlayer(src, Config.RateLimit.kickReason or "Socket exhaustion detected.")
            return
        end
        TriggerClientEvent("nyx:core:rpc:response", src, nonce, false, nil, Nyx.RPC.Errors.RATE_LIMITED)
        return
    end

    -- 3. Payload Cap Check
    if not Nyx.RPC.IsPayloadWithinBounds(args) then
        TriggerClientEvent("nyx:core:rpc:response", src, nonce, false, nil, Nyx.RPC.Errors.PAYLOAD_TOO_LARGE)
        return
    end

    -- 4. Check Handler Existence
    local handler = registeredHandlers[route]
    if not handler then
        TriggerClientEvent("nyx:core:rpc:response", src, nonce, false, nil, Nyx.RPC.Errors.ROUTE_NOT_FOUND)
        return
    end

    -- 5. Safe Isolated Execution
    CreateThread(function()
        local ok, result, customErr = xpcall(function()
            if type(args) == "table" then
                return handler(src, table.unpack(args))
            else
                return handler(src, args)
            end
        end, function(err)
            local trace = debug.traceback(tostring(err), 2)
            print(string.format("^1[Nyx:RPC] Internal error in route '%s' from source %s: %s\n%s^7", route, src, tostring(err), trace))
            return err
        end)

        if ok then
            TriggerClientEvent("nyx:core:rpc:response", src, nonce, true, result, nil)
        else
            TriggerClientEvent("nyx:core:rpc:response", src, nonce, false, nil, customErr or Nyx.RPC.Errors.INTERNAL_ERROR)
        end
    end)
end)

-- Bidirectional: Trigger RPC on a specific Client
function Nyx.RPC.TriggerClient(src, route, ...)
    if not Nyx.RPC.IsValidRoute(route) then
        error(string.format("[Nyx:RPC] Invalid client route name: '%s'", tostring(route)))
    end

    local p = promise.new()
    local nonce = Nyx.RPC.GenerateNonce()
    local args = { ... }

    pendingClientRequests[nonce] = {
        promise = p,
        src = src,
        route = route,
        timestamp = GetGameTimer()
    }

    TriggerClientEvent("nyx:core:rpc:clientRequest", src, nonce, route, args)

    -- Execution Timeout Guard
    SetTimeout(Config.RPCTimeout or 5000, function()
        if pendingClientRequests[nonce] then
            pendingClientRequests[nonce] = nil
            p:reject(Nyx.RPC.Errors.TIMEOUT)
        end
    end)

    return p
end

-- Response from Client back to Server
RegisterNetEvent("nyx:core:rpc:clientResponse", function(nonce, success, payload, err)
    local src = source
    local pending = pendingClientRequests[nonce]

    if not pending or pending.src ~= src then
        return
    end

    pendingClientRequests[nonce] = nil

    if success then
        pending.promise:resolve(payload)
    else
        pending.promise:reject(err or Nyx.RPC.Errors.INTERNAL_ERROR)
    end
end)

-- Cleanup on Player Disconnect
AddEventHandler("playerDropped", function()
    local src = source
    rateLimiters[src] = nil

    for nonce, pending in pairs(pendingClientRequests) do
        if pending.src == src then
            pending.promise:reject("PLAYER_DROPPED")
            pendingClientRequests[nonce] = nil
        end
    end
end)
