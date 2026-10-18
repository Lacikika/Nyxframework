--[[
    Nyxframework: nyx_judiciary
    File: shared/warrants.lua
    Description: Pure Lua 5.4 algorithmic engine for probable cause petition verification,
                 SHA-256 judicial signature generation & verification, cellular triangulation
                 tracking ping math, and legal warrant access matrix evaluation.
]]

Nyx = Nyx or {}
Nyx.Warrants = {}

-- ----------------------------------------------------------------------------
-- 1. Pure Lua 5.4 Cryptographic SHA-256 Engine
-- ----------------------------------------------------------------------------
local band, bor, bxor, bnot = function(a, b) return a & b end, function(a, b) return a | b end, function(a, b) return a ~ b end, function(a) return ~a & 0xFFFFFFFF end
local rshift, lshift = function(a, b) return (a & 0xFFFFFFFF) >> b end, function(a, b) return (a << b) & 0xFFFFFFFF end

local function ror(x, n)
    return (rshift(x, n) | lshift(x, 32 - n)) & 0xFFFFFFFF
end

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

local function sha256(str)
    local H = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    }

    local len = #str
    local bit_len = len * 8
    local pad = { str:byte(1, len) }
    pad[#pad + 1] = 0x80
    while (#pad % 64) ~= 56 do
        pad[#pad + 1] = 0x00
    end

    for i = 7, 0, -1 do
        pad[#pad + 1] = (bit_len >> (i * 8)) & 0xFF
    end

    local W = {}
    for chunk = 1, #pad, 64 do
        for t = 0, 15 do
            local idx = chunk + t * 4
            W[t] = (lshift(pad[idx], 24) | lshift(pad[idx + 1], 16) | lshift(pad[idx + 2], 8) | pad[idx + 3]) & 0xFFFFFFFF
        end
        for t = 16, 63 do
            local s0 = bxor(bxor(ror(W[t - 15], 7), ror(W[t - 15], 18)), rshift(W[t - 15], 3))
            local s1 = bxor(bxor(ror(W[t - 2], 17), ror(W[t - 2], 19)), rshift(W[t - 2], 10))
            W[t] = (W[t - 16] + s0 + W[t - 7] + s1) & 0xFFFFFFFF
        end

        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]

        for t = 0, 63 do
            local S1 = bxor(bxor(ror(e, 6), ror(e, 11)), ror(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local temp1 = (h + S1 + ch + K[t + 1] + W[t]) & 0xFFFFFFFF
            local S0 = bxor(bxor(ror(a, 2), ror(a, 13)), ror(a, 22))
            local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
            local temp2 = (S0 + maj) & 0xFFFFFFFF

            h = g
            g = f
            f = e
            e = (d + temp1) & 0xFFFFFFFF
            d = c
            c = b
            b = a
            a = (temp1 + temp2) & 0xFFFFFFFF
        end

        H[1] = (H[1] + a) & 0xFFFFFFFF
        H[2] = (H[2] + b) & 0xFFFFFFFF
        H[3] = (H[3] + c) & 0xFFFFFFFF
        H[4] = (H[4] + d) & 0xFFFFFFFF
        H[5] = (H[5] + e) & 0xFFFFFFFF
        H[6] = (H[6] + f) & 0xFFFFFFFF
        H[7] = (H[7] + g) & 0xFFFFFFFF
        H[8] = (H[8] + h) & 0xFFFFFFFF
    end

    return string.format("%08x%08x%08x%08x%08x%08x%08x%08x",
        H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8])
end

Nyx.Warrants.SHA256 = sha256

-- ----------------------------------------------------------------------------
-- 2. Probable Cause Petition Validation & Sanitization
-- ----------------------------------------------------------------------------
local VALID_WARRANT_TYPES = {
    ['arrest'] = true,
    ['search_property'] = true,
    ['search_vehicle'] = true,
    ['subpoena'] = true,
    ['wiretap'] = true
}

local VALID_SUBPOENA_SCOPES = {
    ['all'] = true,
    ['financial'] = true,
    ['property'] = true,
    ['telecom'] = true
}

function Nyx.Warrants.ValidatePetition(data)
    if type(data) ~= "table" then
        return false, "INVALID_PETITION_PAYLOAD"
    end

    local petitionerId = data.petitionerCitizenId
    if not petitionerId or type(petitionerId) ~= "string" or #petitionerId < 2 then
        return false, "MISSING_OR_INVALID_PETITIONER_ID"
    end

    local targetId = data.targetCitizenId
    if not targetId or type(targetId) ~= "string" or #targetId < 2 then
        return false, "MISSING_OR_INVALID_TARGET_CITIZEN_ID"
    end

    local wType = data.warrantType
    if not wType or not VALID_WARRANT_TYPES[wType] then
        return false, "INVALID_OR_UNSUPPORTED_WARRANT_TYPE"
    end

    local cause = data.probableCauseSummary
    if not cause or type(cause) ~= "string" or #cause < 20 then
        return false, "INSUFFICIENT_PROBABLE_CAUSE_NARRATIVE"
    end

    local maxHours = (Config and Config.Warrants and Config.Warrants.MaxExpirationHours) or 336
    local defHours = (Config and Config.Warrants and Config.Warrants.DefaultExpirationHours) or 72
    local hours = tonumber(data.requestedDurationHours) or defHours
    if hours < 1 then hours = 1 end
    if hours > maxHours then hours = maxHours end

    local subpoenaScope = nil
    if wType == "subpoena" then
        subpoenaScope = data.subpoenaScope or "financial"
        if not VALID_SUBPOENA_SCOPES[subpoenaScope] then
            subpoenaScope = "financial"
        end
    end

    local targetEntity = data.targetEntityId
    if targetEntity and type(targetEntity) == "string" then
        targetEntity = targetEntity:gsub("^%s*(.-)%s*$", "%1")
        if #targetEntity == 0 then targetEntity = nil end
    else
        targetEntity = nil
    end

    return true, {
        petitionerCitizenId = petitionerId,
        targetCitizenId = targetId,
        warrantType = wType,
        subpoenaScope = subpoenaScope,
        targetEntityId = targetEntity,
        probableCauseSummary = cause,
        requestedDurationHours = hours
    }
end

-- ----------------------------------------------------------------------------
-- 3. Cryptographic Judicial Signature & Verification
-- ----------------------------------------------------------------------------
function Nyx.Warrants.GenerateJudicialSignature(petitionId, judgeCitId, targetCitId, warrantType, timestamp, salt)
    local s = salt or "NYX_JUDICIAL_SEAL"
    local t = tonumber(timestamp) or os.time()
    local raw = string.format("%s:%s:%s:%s:%d:%s",
        tostring(petitionId),
        tostring(judgeCitId),
        tostring(targetCitId),
        tostring(warrantType),
        t,
        tostring(s)
    )
    return sha256(raw)
end

function Nyx.Warrants.VerifyJudicialSignature(signature, petitionId, judgeCitId, targetCitId, warrantType, timestamp, salt)
    if not signature or type(signature) ~= "string" or #signature ~= 64 then
        return false, "INVALID_SIGNATURE_LENGTH"
    end

    local expected = Nyx.Warrants.GenerateJudicialSignature(petitionId, judgeCitId, targetCitId, warrantType, timestamp, salt)
    local diff = 0
    for i = 1, 64 do
        diff = diff | (string.byte(signature, i) ~ string.byte(expected, i))
    end

    if diff == 0 then
        return true, "VALID"
    else
        return false, "SIGNATURE_TAMPER_DETECTED"
    end
end

-- ----------------------------------------------------------------------------
-- 4. Cellular Triangulation Tracking Ping & Uncertainty Math
-- ----------------------------------------------------------------------------
function Nyx.Warrants.CalculateTrackingPing(actualCoords, accuracyRadius, seed)
    if not actualCoords then return nil end

    local x = tonumber(actualCoords.x) or 0.0
    local y = tonumber(actualCoords.y) or 0.0
    local z = tonumber(actualCoords.z) or 0.0
    local radius = math.max(10.0, math.min(150.0, tonumber(accuracyRadius) or 35.0))

    local angle, u
    if seed and type(seed) == "number" then
        -- Deterministic pseudo-random generation for unit tests
        local aSeed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        angle = ((aSeed % 10000) / 10000.0) * (2 * math.pi)
        local rSeed = (aSeed * 1103515245 + 12345) & 0x7FFFFFFF
        u = ((rSeed % 10000) / 10000.0)
    else
        angle = math.random() * (2 * math.pi)
        u = math.random()
    end

    -- Uniform disk sampling via square root
    local dist = radius * math.sqrt(u)
    local pingX = math.floor((x + (dist * math.cos(angle))) * 100) / 100
    local pingY = math.floor((y + (dist * math.sin(angle))) * 100) / 100
    local pingZ = math.floor(z * 100) / 100

    return {
        coords = { x = pingX, y = pingY, z = pingZ },
        accuracyRadius = radius,
        timestamp = os.time(),
        triangulationDelta = math.floor(dist * 100) / 100
    }
end

-- ----------------------------------------------------------------------------
-- 5. Legal Warrant Access Matrix Evaluation
-- ----------------------------------------------------------------------------
function Nyx.Warrants.EvaluateWarrantAccess(warrantList, accessType, entityId)
    if type(warrantList) ~= "table" then
        return false, "NO_ACTIVE_WARRANTS"
    end

    local currentTime = os.time()

    for _, w in ipairs(warrantList) do
        local isStatusActive = (w.status == "active")
        local notExpired = true
        if w.expires_at then
            local expEpoch = w.expiresEpoch or w.expires_at
            if type(expEpoch) == "string" then
                -- if ISO or SQL timestamp, compare or treat as valid if flag passed
                expEpoch = currentTime + 1000
            end
            if type(expEpoch) == "number" and expEpoch <= currentTime then
                notExpired = false
            end
        end

        if isStatusActive and notExpired then
            if accessType == "financial_records" then
                if w.type == "subpoena" and (not w.subpoena_scope or w.subpoena_scope == "all" or w.subpoena_scope == "financial") then
                    return true, w
                elseif w.type == "arrest" and (w.subpoena_scope == "all" or w.subpoena_scope == "financial") then
                    return true, w
                end
            elseif accessType == "property_search" then
                if w.type == "search_property" then
                    if not entityId or not w.target_entity_id or w.target_entity_id == entityId or w.target_entity_id == "all" then
                        return true, w
                    end
                end
            elseif accessType == "vehicle_search" then
                if w.type == "search_vehicle" then
                    if not entityId or not w.target_entity_id then
                        return true, w
                    end
                    local cleanW = w.target_entity_id:gsub("%s+", ""):upper()
                    local cleanE = tostring(entityId):gsub("%s+", ""):upper()
                    if cleanW == cleanE or cleanW == "ALL" then
                        return true, w
                    end
                end
            elseif accessType == "live_tracking" then
                if (w.type == "wiretap" or w.type == "arrest") and (w.tracking_active == 1 or w.tracking_active == true) then
                    return true, w
                end
            elseif accessType == "custodial_arrest" then
                if w.type == "arrest" then
                    return true, w
                end
            end
        end
    end

    return false, "UNAUTHORIZED_NO_ACTIVE_WARRANT"
end

-- ----------------------------------------------------------------------------
-- 6. Evaluate State Machine Transitions
-- ----------------------------------------------------------------------------
function Nyx.Warrants.CanTransitionStatus(currentStatus, targetStatus)
    local transitions = {
        ['pending_review'] = { ['approved'] = true, ['rejected'] = true, ['withdrawn'] = true },
        ['approved'] = { ['active'] = true, ['rescinded'] = true },
        ['active'] = { ['executed'] = true, ['expired'] = true, ['rescinded'] = true },
        ['rejected'] = {},
        ['withdrawn'] = {},
        ['executed'] = {},
        ['expired'] = {},
        ['rescinded'] = {}
    }

    local allowed = transitions[currentStatus]
    return (allowed and allowed[targetStatus] == true)
end
