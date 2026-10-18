--[[
    Nyxframework: nyx_core
    File: shared/rpc.lua
    Description: Shared RPC structures, route validation, and packet serialization utilities.
]]

Nyx = Nyx or {}
Nyx.RPC = Nyx.RPC or {}

-- Standardized RPC Error Codes
Nyx.RPC.Errors = {
    TIMEOUT = "TIMEOUT",
    RATE_LIMITED = "RATE_LIMITED",
    PAYLOAD_TOO_LARGE = "PAYLOAD_TOO_LARGE",
    ROUTE_NOT_FOUND = "ROUTE_NOT_FOUND",
    INTERNAL_ERROR = "INTERNAL_ERROR",
    UNAUTHORIZED = "UNAUTHORIZED",
    INVALID_ROUTE = "INVALID_ROUTE",
    INVALID_NONCE = "INVALID_NONCE"
}

-- Cryptographic / Pseudo-Random UUIDv4 Generator
local random = math.random
function Nyx.RPC.GenerateNonce()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and random(0, 15) or random(8, 11)
        return string.format("%x", v)
    end))
end

-- Validate nonce: non-empty string with maximum length of 64 chars
function Nyx.RPC.IsValidNonce(nonce)
    if type(nonce) ~= "string" then return false end
    if #nonce == 0 or #nonce > 64 then return false end
    return true
end

-- Validate route naming conventions: alphanumeric with ':', '.', '_', '-' up to 128 chars
function Nyx.RPC.IsValidRoute(route)
    if type(route) ~= "string" then return false end
    if #route == 0 or #route > 128 then return false end
    return (string.match(route, "^[%w%.:_%-]+$") ~= nil)
end

-- Check payload size constraints (capped at Config.MaxPayloadSize or 65536 bytes)
function Nyx.RPC.IsPayloadWithinBounds(payload, customCap)
    if payload == nil then return true end
    local maxSize = customCap or (Config and Config.MaxPayloadSize) or 65536
    local rawSize = 0

    local valType = type(payload)
    if valType == "string" then
        rawSize = #payload
    elseif valType == "number" or valType == "boolean" then
        rawSize = #tostring(payload)
    elseif valType == "table" then
        local ok, encoded = pcall(json.encode, payload)
        if not ok or not encoded then
            return false
        end
        rawSize = #encoded
    else
        -- Disallow raw userdata, functions, threads
        return false
    end

    return rawSize <= maxSize
end
