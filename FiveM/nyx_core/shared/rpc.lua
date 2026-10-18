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

-- Validate route naming conventions: alphanumeric with ':', '.', '_', '-'
function Nyx.RPC.IsValidRoute(route)
    if type(route) ~= "string" then return false end
    if #route == 0 or #route > 128 then return false end
    return (string.match(route, "^[%w%.:_%-]+$") ~= nil)
end

-- Check payload size constraints (capped at Config.MaxPayloadSize)
function Nyx.RPC.IsPayloadWithinBounds(payload)
    if payload == nil then return true end
    local rawSize = 0
    if type(payload) == "string" then
        rawSize = #payload
    else
        local ok, encoded = pcall(json.encode, payload)
        if not ok or not encoded then
            return false
        end
        rawSize = #encoded
    end
    return rawSize <= (Config.MaxPayloadSize or 65536)
end
