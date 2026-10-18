--[[
    Nyxframework: nyx_vehicles
    File: shared/keys.lua
    Description: Pure Lua 5.4 domain logic engine for metadata-driven ignition keys,
                 corporate fleet RFID proximity access, lockpicking probabilities,
                 and latent fingerprint forensic traces.
]]

Nyx = Nyx or {}
Nyx.VehicleKeys = Nyx.VehicleKeys or {}

-- 1. Pure Lua 5.4 Bitwise SHA-256 Hasher
local function sha256(str)
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

    return string.format("%08x%08x%08x%08x%08x%08x%08x%08x", H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8])
end

Nyx.VehicleKeys.Sha256 = sha256

-- 2. Validate Physical Key Item against target vehicle VIN and Plate
--- @param keyItem table
--- @param targetVin string
--- @param targetPlate string
--- @return boolean ok
--- @return string reason
function Nyx.VehicleKeys.ValidateKeyMatch(keyItem, targetVin, targetPlate)
    if not keyItem or type(keyItem) ~= "table" then
        return false, "INVALID_KEY_ITEM"
    end

    local itemId = keyItem.item_id or keyItem.name
    if itemId ~= "item_vehicle_key" and itemId ~= "car_keys" then
        return false, "NOT_A_KEY_ITEM"
    end

    local meta = keyItem.metadata or {}
    local keyVin = meta.vin
    local keyPlate = meta.plate

    if keyVin and targetVin and (tostring(keyVin) == tostring(targetVin)) then
        return true, "VIN_MATCH"
    end

    if keyPlate and targetPlate then
        local cleanKey = string.upper(string.gsub(tostring(keyPlate), "%s+", ""))
        local cleanTarget = string.upper(string.gsub(tostring(targetPlate), "%s+", ""))
        if cleanKey == cleanTarget and #cleanKey > 0 then
            return true, "PLATE_MATCH"
        end
    end

    return false, "KEY_MISMATCH"
end

-- 3. Validate Corporate RFID Access Token
--- @param rfidItem table
--- @param targetFactionId string
--- @param currentTime number|nil
--- @param requiredLevel string|nil
--- @return boolean ok
--- @return string reason
function Nyx.VehicleKeys.ValidateRfidAccess(rfidItem, targetFactionId, currentTime, requiredLevel)
    local levels = {
        driver = 1,
        manager = 2,
        executive = 3,
        admin = 4
    }

    if not rfidItem or type(rfidItem) ~= "table" then
        return false, "INVALID_RFID_ITEM"
    end

    local itemId = rfidItem.item_id or rfidItem.name
    if itemId ~= "rfid_fleet_card" then
        return false, "NOT_RFID_ITEM"
    end

    local meta = rfidItem.metadata or {}
    if meta.is_revoked == true or meta.isRevoked == true then
        return false, "TOKEN_REVOKED"
    end

    local exp = tonumber(meta.expires_at or meta.expiresAt)
    local now = tonumber(currentTime) or os.time()
    if exp and exp > 0 and now > exp then
        return false, "TOKEN_EXPIRED"
    end

    local itemFaction = meta.faction_id or meta.factionId
    if not itemFaction or itemFaction ~= targetFactionId then
        return false, "FACTION_MISMATCH"
    end

    local tokenLevel = meta.access_level or meta.accessLevel or "driver"
    local tokenRank = levels[tokenLevel] or 1
    local reqRank = levels[requiredLevel or "driver"] or 1

    if tokenRank < reqRank then
        return false, "INSUFFICIENT_ACCESS_LEVEL"
    end

    return true, "AUTHORIZED"
end

-- 4. Calculate Lockpick Chance, Alarms, and Pick Degradation
--- @param lockpickType string|nil
--- @param vehicleClass number|nil
--- @param securityUpgrade number|nil
--- @return table
function Nyx.VehicleKeys.CalculateLockpickChance(lockpickType, vehicleClass, securityUpgrade)
    local baseChances = {
        tool_lockpick = 0.50,
        tool_lockpick_advanced = 0.75,
        improvised_wire = 0.30
    }

    local pType = lockpickType or "tool_lockpick"
    local base = baseChances[pType] or 0.40

    local classMods = {
        [0] = 0.05,  -- Compacts
        [1] = 0.02,  -- Sedans
        [2] = 0.00,  -- SUVs
        [3] = 0.00,  -- Coupes
        [6] = -0.15, -- Sports
        [7] = -0.20  -- Super
    }

    local cls = tonumber(vehicleClass) or 0
    local mod = classMods[cls] or 0.00
    local sec = tonumber(securityUpgrade) or 0
    local secPenalty = sec * 0.10

    local successChance = math.max(0.05, math.min(0.95, base + mod - secPenalty))
    local alarmChanceFail = math.min(0.90, 0.35 + (sec * 0.15))
    local alarmChanceSuccess = math.min(0.50, 0.10 + (sec * 0.10))
    local breakChance = (pType == "tool_lockpick") and 0.25 or 0.10

    local round = function(val) return math.floor((val * 100) + 0.5) / 100 end

    return {
        successChance = round(successChance),
        alarmChanceFail = round(alarmChanceFail),
        alarmChanceSuccess = round(alarmChanceSuccess),
        breakChance = round(breakChance)
    }
end

-- 5. Determine Latent Forensic Fingerprint Trace
--- @param hasGloves boolean
--- @param citizenId string
--- @param coords table
--- @param salt string|nil
--- @return table
function Nyx.VehicleKeys.DetermineForensicTrace(hasGloves, citizenId, coords, salt)
    if hasGloves == true then
        return {
            leavesFingerprint = false,
            evidenceType = nil,
            hash = nil,
            surface = nil
        }
    end

    local c = coords or { x = 0.0, y = 0.0, z = 0.0 }
    local s = salt or "NYX-SALT"
    local sourceSerial = "FP-" .. tostring(citizenId or "UNKNOWN")
    local raw = string.format("%s:%s:%.2f,%.2f,%.2f:%s",
        sourceSerial,
        tostring(citizenId or "UNKNOWN"),
        tonumber(c.x) or 0.0,
        tonumber(c.y) or 0.0,
        tonumber(c.z) or 0.0,
        s
    )
    local fpHash = sha256(raw)

    return {
        leavesFingerprint = true,
        evidenceType = "fingerprint",
        sourceSerial = sourceSerial,
        hash = fpHash,
        surface = "vehicle_door_handle"
    }
end

-- 6. Format Key Badge for UI
--- @param keyType string
--- @return table
function Nyx.VehicleKeys.FormatKeyBadge(keyType)
    local t = keyType and string.lower(keyType) or "copy"
    if t == "master" then
        return { label = "FŐKULCS (MASTER)", cssClass = "badge-primary" }
    elseif t == "valet" then
        return { label = "SZERVÍZ / VALET", cssClass = "badge-warning" }
    elseif t == "fob" then
        return { label = "DIGITÁLIS FOB", cssClass = "badge-info" }
    else
        return { label = "MÁSOLAT (COPY)", cssClass = "badge-secondary" }
    end
end

-- 7. Zero-Trust Payload Validation for Physical Key Issuance
--- @param payload table
--- @return boolean ok
--- @return string reason
function Nyx.VehicleKeys.ValidateKeyCreationPayload(payload)
    if not payload or type(payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end

    local vin = payload.vin
    if not vin or type(vin) ~= "string" or #vin < 3 or #vin > 32 then
        return false, "INVALID_VIN"
    end

    local plate = payload.plate
    if not plate or type(plate) ~= "string" or #plate < 2 or #plate > 12 then
        return false, "INVALID_PLATE"
    end

    local keyType = payload.keyType or "copy"
    local allowedTypes = { master = true, copy = true, valet = true, fob = true }
    if not allowedTypes[keyType] then
        return false, "INVALID_KEY_TYPE"
    end

    local targetCitizenId = payload.targetCitizenId
    if not targetCitizenId or type(targetCitizenId) ~= "string" or #targetCitizenId < 2 then
        return false, "INVALID_TARGET"
    end

    return true, "OK"
end

-- 8. Zero-Trust Payload Validation for Corporate RFID Issuance
--- @param payload table
--- @return boolean ok
--- @return string reason
function Nyx.VehicleKeys.ValidateRfidCreationPayload(payload)
    if not payload or type(payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end

    local factionId = payload.factionId
    if not factionId or type(factionId) ~= "string" or #factionId < 2 or #factionId > 32 then
        return false, "INVALID_FACTION_ID"
    end

    local targetCitizenId = payload.targetCitizenId
    if targetCitizenId ~= nil and (type(targetCitizenId) ~= "string" or #targetCitizenId < 2) then
        return false, "INVALID_TARGET"
    end

    local accessLevel = payload.accessLevel or "driver"
    local allowedLevels = { driver = true, manager = true, executive = true, admin = true }
    if not allowedLevels[accessLevel] then
        return false, "INVALID_ACCESS_LEVEL"
    end

    local label = payload.label or "Corporate Fleet Keycard"
    if type(label) ~= "string" or #label > 64 then
        return false, "INVALID_LABEL"
    end

    return true, "OK"
end
