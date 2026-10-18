--[[
    Nyxframework: nyx_core
    File: server/rpc.lua
    Description: Server-side bidirectional RPC dispatcher with token-bucket rate limiting (50 req/s),
                 64KB payload cap enforcement, sustained flood protection, and error isolation.
]]

Nyx = Nyx or {}
Nyx.RPC = Nyx.RPC or {}

local registeredHandlers = {}
Nyx.RPC.Handlers = registeredHandlers
local pendingClientRequests = {}
Nyx.RPC.PendingClientRequests = pendingClientRequests
local rateLimiters = {}
Nyx.RPC.RateLimiters = rateLimiters

local metrics = {
    totalRequests = 0,
    totalBlocked = 0,
    totalKicked = 0
}
Nyx.RPC.Metrics = metrics

-- Helper: Current timestamp in milliseconds (safe for in-engine and offline test harnesses)
local function getNowMs()
    if type(GetGameTimer) == "function" then
        return GetGameTimer()
    elseif type(os.clock) == "function" then
        return math.floor(os.clock() * 1000)
    else
        return math.floor(os.time() * 1000)
    end
end

--- Evaluate Token Bucket Rate Limiting for a given source
--- @param src number|string Player source or identifier
--- @param route string|nil Target RPC route name
--- @param customCost number|nil Optional token cost override
--- @param overrideNow number|nil Optional timestamp in ms (for testing)
--- @return boolean allowed True if allowed to proceed, false if rate limited
--- @return number remainingTokens Available tokens after evaluation
--- @return string status "OK", "RATE_LIMITED", "KICKED", or "EXEMPT"
function Nyx.RPC.CheckRateLimit(src, route, customCost, overrideNow)
    local cfg = Config and Config.RateLimit
    if cfg and cfg.enabled == false then
        return true, 50.0, "EXEMPT"
    end

    if route and cfg and cfg.exemptRoutes and cfg.exemptRoutes[route] then
        return true, 50.0, "EXEMPT"
    end

    local now = overrideNow or getNowMs()
    local cap = (cfg and cfg.capacity) or 50.0
    local refill = (cfg and cfg.refillRate) or 50.0
    local cost = customCost or (route and cfg and cfg.routeCosts and cfg.routeCosts[route]) or (cfg and cfg.defaultCost) or 1.0

    local entry = rateLimiters[src]
    if not entry then
        entry = {
            tokens = cap,
            lastRefill = now,
            violations = 0,
            lastViolation = 0,
            totalRequests = 0,
            blockedRequests = 0,
            kicked = false
        }
        rateLimiters[src] = entry
    end

    if entry.kicked then
        return false, 0.0, "KICKED"
    end

    -- Refill tokens based on elapsed delta time
    local deltaSec = math.max(0.0, (now - entry.lastRefill) / 1000.0)
    entry.tokens = math.min(cap, entry.tokens + (deltaSec * refill))
    entry.lastRefill = now

    entry.totalRequests = entry.totalRequests + 1
    metrics.totalRequests = metrics.totalRequests + 1

    -- Check if token budget accommodates cost
    if entry.tokens < cost then
        entry.blockedRequests = entry.blockedRequests + 1
        metrics.totalBlocked = metrics.totalBlocked + 1

        local violationWindow = (cfg and cfg.violationWindowMs) or 5000
        if (now - entry.lastViolation) > violationWindow then
            entry.violations = 1
        else
            entry.violations = entry.violations + 1
        end
        entry.lastViolation = now

        local maxViolations = (cfg and cfg.maxViolations) or 10
        local kickOnSustained = (cfg and cfg.kickOnSustainedFlooding) ~= false
        local action = (cfg and cfg.actionOnExceed) or "throttle"

        if action == "kick" or (kickOnSustained and entry.violations >= maxViolations) then
            entry.kicked = true
            metrics.totalKicked = metrics.totalKicked + 1
            return false, entry.tokens, "KICKED"
        end

        return false, entry.tokens, "RATE_LIMITED"
    end

    -- Deduct tokens for allowed execution
    entry.tokens = entry.tokens - cost
    return true, entry.tokens, "OK"
end

--- Get rate limiter state telemetry for a source
--- @param src number|string
--- @return table|nil
function Nyx.RPC.GetRateLimitState(src)
    local entry = rateLimiters[src]
    if not entry then return nil end
    return {
        tokens = entry.tokens,
        lastRefill = entry.lastRefill,
        violations = entry.violations,
        lastViolation = entry.lastViolation,
        totalRequests = entry.totalRequests,
        blockedRequests = entry.blockedRequests,
        kicked = entry.kicked
    }
end

--- Reset rate limiter for a source
--- @param src number|string
function Nyx.RPC.ResetRateLimit(src)
    rateLimiters[src] = nil
end

--- Override rate limit parameters for a specific player (e.g. VIP/testing)
--- @param src number|string
--- @param customCap number
function Nyx.RPC.SetPlayerTokens(src, customCap)
    local entry = rateLimiters[src]
    if entry then
        entry.tokens = customCap
        entry.kicked = false
        entry.violations = 0
    else
        rateLimiters[src] = {
            tokens = customCap,
            lastRefill = getNowMs(),
            violations = 0,
            lastViolation = 0,
            totalRequests = 0,
            blockedRequests = 0,
            kicked = false
        }
    end
end

--- Retrieve aggregated RPC metrics
--- @return table
function Nyx.RPC.GetRateLimitMetrics()
    local activeCount = 0
    for _ in pairs(rateLimiters) do
        activeCount = activeCount + 1
    end
    return {
        totalRequests = metrics.totalRequests,
        totalBlocked = metrics.totalBlocked,
        totalKicked = metrics.totalKicked,
        activeLimiters = activeCount
    }
end

--- Cleanup resources on player disconnect
--- @param src number|string
function Nyx.RPC.CleanupSource(src)
    rateLimiters[src] = nil

    for nonce, pending in pairs(pendingClientRequests) do
        if pending.src == src then
            pending.promise:reject("PLAYER_DROPPED")
            pendingClientRequests[nonce] = nil
        end
    end
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
    if Config and Config.Debug then
        print(string.format("^4[Nyx:RPC]^7 Registered server route: ^3%s^7", route))
    end
end

-- Incoming Client Request Dispatcher with Zero-Trust Security Gates
RegisterNetEvent("nyx:core:rpc:request", function(nonce, route, args)
    local src = source

    -- 1. Validate Nonce & Route Security Invariants
    if not Nyx.RPC.IsValidNonce(nonce) then
        return
    end

    if not Nyx.RPC.IsValidRoute(route) then
        TriggerClientEvent("nyx:core:rpc:response", src, nonce, false, nil, Nyx.RPC.Errors.INVALID_ROUTE)
        return
    end

    -- 2. Token Bucket Rate Limiting (50 req/s, capacity 50)
    local allowed, remainingTokens, status = Nyx.RPC.CheckRateLimit(src, route)
    if not allowed then
        if status == "KICKED" then
            local reason = (Config and Config.RateLimit and Config.RateLimit.kickReason) or "[Nyx-Security] Socket exhaustion detected: RPC rate limit exceeded."
            print(string.format("^1[Nyx:Security] Kicking source %s for sustained RPC rate limit flooding on route '%s'!^7", tostring(src), tostring(route)))
            if type(DropPlayer) == "function" then
                DropPlayer(src, reason)
            end
            return
        end

        TriggerClientEvent("nyx:core:rpc:response", src, nonce, false, nil, Nyx.RPC.Errors.RATE_LIMITED)
        return
    end

    -- 3. Payload Cap Check (64KB Enforcement on incoming arguments)
    if not Nyx.RPC.IsPayloadWithinBounds(args) then
        print(string.format("^1[Nyx:Security] RPC payload cap exceeded (64KB) by source %s on route '%s'!^7", tostring(src), tostring(route)))
        TriggerClientEvent("nyx:core:rpc:response", src, nonce, false, nil, Nyx.RPC.Errors.PAYLOAD_TOO_LARGE)
        return
    end

    -- 4. Check Handler Existence
    local handler = registeredHandlers[route]
    if not handler then
        TriggerClientEvent("nyx:core:rpc:response", src, nonce, false, nil, Nyx.RPC.Errors.ROUTE_NOT_FOUND)
        return
    end

    -- 5. Safe Isolated Execution & Response Payload Cap (64KB Enforcement on output)
    CreateThread(function()
        local ok, result, customErr = xpcall(function()
            if type(args) == "table" then
                return handler(src, table.unpack(args))
            else
                return handler(src, args)
            end
        end, function(err)
            local trace = debug.traceback(tostring(err), 2)
            print(string.format("^1[Nyx:RPC] Internal error in route '%s' from source %s: %s\n%s^7", route, tostring(src), tostring(err), trace))
            return err
        end)

        if ok then
            -- Verify response payload bounds before transmission over wire
            if not Nyx.RPC.IsPayloadWithinBounds(result) then
                print(string.format("^1[Nyx:Security] Outgoing RPC response payload exceeds 64KB for route '%s' to source %s! Rejecting.^7", route, tostring(src)))
                TriggerClientEvent("nyx:core:rpc:response", src, nonce, false, nil, Nyx.RPC.Errors.PAYLOAD_TOO_LARGE)
            else
                TriggerClientEvent("nyx:core:rpc:response", src, nonce, true, result, nil)
            end
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

    local args = { ... }

    -- Enforce 64KB cap on outgoing server-to-client request
    if not Nyx.RPC.IsPayloadWithinBounds(args) then
        error(string.format("[Nyx:RPC] Outgoing payload exceeds 64KB limit for route '%s'", tostring(route)))
    end

    local p = promise.new()
    local nonce = Nyx.RPC.GenerateNonce()

    pendingClientRequests[nonce] = {
        promise = p,
        src = src,
        route = route,
        timestamp = getNowMs()
    }

    TriggerClientEvent("nyx:core:rpc:clientRequest", src, nonce, route, args)

    -- Execution Timeout Guard
    SetTimeout((Config and Config.RPCTimeout) or 5000, function()
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

    if not Nyx.RPC.IsValidNonce(nonce) then
        return
    end

    local pending = pendingClientRequests[nonce]
    if not pending or pending.src ~= src then
        return
    end

    pendingClientRequests[nonce] = nil

    if success then
        -- Enforce 64KB cap on incoming client response payload
        if not Nyx.RPC.IsPayloadWithinBounds(payload) then
            pending.promise:reject(Nyx.RPC.Errors.PAYLOAD_TOO_LARGE)
        else
            pending.promise:resolve(payload)
        end
    else
        pending.promise:reject(err or Nyx.RPC.Errors.INTERNAL_ERROR)
    end
end)

-- Cleanup on Player Disconnect
AddEventHandler("playerDropped", function()
    local src = source
    Nyx.RPC.CleanupSource(src)
end)
