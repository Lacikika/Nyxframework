--[[
    Nyxframework: nyx_core
    File: client/rpc.lua
    Description: Client-side RPC bus supporting promises, execution timeouts, 64KB payload caps, and bidirectional calls.
]]

Nyx = Nyx or {}
Nyx.RPC = Nyx.RPC or {}

local pendingRequests = {}
local registeredHandlers = {}

-- Register a client-side RPC handler callable by the server
function Nyx.RPC.Register(route, handler)
    if not Nyx.RPC.IsValidRoute(route) then
        error(string.format("[Nyx:RPC:Client] Invalid route name: '%s'", tostring(route)))
    end

    registeredHandlers[route] = handler
    if Config and Config.Debug then
        print(string.format("^4[Nyx:RPC:Client]^7 Registered client route: ^3%s^7", route))
    end
end

-- Trigger a remote procedure call on the server
-- Returns a standard CitizenFX promise
function Nyx.RPC.Trigger(route, ...)
    if not Nyx.RPC.IsValidRoute(route) then
        local p = promise.new()
        p:reject(Nyx.RPC.Errors.INVALID_ROUTE)
        return p
    end

    local args = { ... }

    -- Enforce 64KB payload limit client-side before sending across network
    if not Nyx.RPC.IsPayloadWithinBounds(args) then
        local p = promise.new()
        p:reject(Nyx.RPC.Errors.PAYLOAD_TOO_LARGE)
        return p
    end

    local p = promise.new()
    local nonce = Nyx.RPC.GenerateNonce()

    pendingRequests[nonce] = {
        promise = p,
        route = route,
        timestamp = GetGameTimer()
    }

    TriggerServerEvent("nyx:core:rpc:request", nonce, route, args)

    -- Enforce Client Timeout
    SetTimeout((Config and Config.RPCTimeout) or 5000, function()
        if pendingRequests[nonce] then
            pendingRequests[nonce] = nil
            p:reject(Nyx.RPC.Errors.TIMEOUT)
        end
    end)

    return p
end

-- Synchronous/blocking coroutine helper for RPC
function Nyx.RPC.TriggerAwait(route, ...)
    local p = Nyx.RPC.Trigger(route, ...)
    return Citizen.Await(p)
end

-- Incoming Response from Server
RegisterNetEvent("nyx:core:rpc:response", function(nonce, success, payload, err)
    if not Nyx.RPC.IsValidNonce(nonce) then return end

    local pending = pendingRequests[nonce]
    if not pending then
        return
    end

    pendingRequests[nonce] = nil

    if success then
        pending.promise:resolve(payload)
    else
        pending.promise:reject(err or Nyx.RPC.Errors.INTERNAL_ERROR)
    end
end)

-- Incoming Client Request from Server (Bidirectional)
RegisterNetEvent("nyx:core:rpc:clientRequest", function(nonce, route, args)
    if not Nyx.RPC.IsValidNonce(nonce) or not Nyx.RPC.IsValidRoute(route) then
        return
    end

    -- Enforce 64KB payload check on server request payload
    if not Nyx.RPC.IsPayloadWithinBounds(args) then
        TriggerServerEvent("nyx:core:rpc:clientResponse", nonce, false, nil, Nyx.RPC.Errors.PAYLOAD_TOO_LARGE)
        return
    end

    local handler = registeredHandlers[route]
    if not handler then
        TriggerServerEvent("nyx:core:rpc:clientResponse", nonce, false, nil, Nyx.RPC.Errors.ROUTE_NOT_FOUND)
        return
    end

    CreateThread(function()
        local ok, result, customErr = xpcall(function()
            if type(args) == "table" then
                return handler(table.unpack(args))
            else
                return handler(args)
            end
        end, function(err)
            local trace = debug.traceback(tostring(err), 2)
            print(string.format("^1[Nyx:RPC:Client] Error in route '%s': %s\n%s^7", route, tostring(err), trace))
            return err
        end)

        if ok then
            -- Enforce 64KB payload check on client response payload
            if not Nyx.RPC.IsPayloadWithinBounds(result) then
                TriggerServerEvent("nyx:core:rpc:clientResponse", nonce, false, nil, Nyx.RPC.Errors.PAYLOAD_TOO_LARGE)
            else
                TriggerServerEvent("nyx:core:rpc:clientResponse", nonce, true, result, nil)
            end
        else
            TriggerServerEvent("nyx:core:rpc:clientResponse", nonce, false, nil, customErr or Nyx.RPC.Errors.INTERNAL_ERROR)
        end
    end)
end)
