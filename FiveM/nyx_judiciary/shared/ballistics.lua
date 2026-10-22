--[[
    Nyxframework: nyx_judiciary
    File: shared/ballistics.lua
    Description: Deterministic forensic ballistics engine, barrel rifling microstriation formulas,
                 firing pin & breech face signature hashing, and NIBIN match correlation algorithms.
]]

Nyx = Nyx or {}
Nyx.Ballistics = Nyx.Ballistics or {}

-- Pure Lua SHA-256 Hasher
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

Nyx.Ballistics.Sha256 = sha256

-- Helper: Map weapon model / hash to standard caliber string
function Nyx.Ballistics.GetCaliber(weaponModelOrHash)
    if not weaponModelOrHash then return "9mm" end
    local str = string.lower(tostring(weaponModelOrHash))

    if str:find("pistol") or str:find("smg") or str:find("combatpistol") or str == tostring(`WEAPON_PISTOL`) or str == tostring(`WEAPON_COMBATPISTOL`) or str == tostring(`WEAPON_SMG`) then
        return "9mm"
    elseif str:find("appistol") or str:find("vintagepistol") or str:find("snspistol") then
        return ".45_ACP"
    elseif str:find("carbine") or str:find("rifle") or str:find("specialcarbine") or str == tostring(`WEAPON_CARBINERIFLE`) or str == tostring(`WEAPON_SPECIALCARBINE`) then
        return "5.56x45mm"
    elseif str:find("mg") or str:find("sniper") or str:find("heavy") then
        return "7.62x51mm"
    elseif str:find("shotgun") or str:find("pumpshotgun") or str == tostring(`WEAPON_PUMPSHOTGUN`) then
        return "12-gauge"
    end

    return "9mm"
end

-- Pure Formula 1: Barrel Rifling Microstriation Signature Hash
-- SHA-256(RIFLING:<weaponSerial>:<weaponModel>:<caliber>:<salt>)
function Nyx.Ballistics.ComputeRiflingHash(weaponSerial, weaponModel, caliber, salt)
    weaponSerial = weaponSerial or "UNKNOWN_SERIAL"
    weaponModel = weaponModel or "weapon_pistol"
    caliber = caliber or Nyx.Ballistics.GetCaliber(weaponModel)
    salt = salt or "RIFLE_SALT_99"

    local raw = string.format("RIFLING:%s:%s:%s:%s", weaponSerial, weaponModel, caliber, salt)
    return sha256(raw)
end

-- Pure Formula 2: Firing Pin & Breech Face Impressions Signature Hash
-- SHA-256(MECHANICAL:<weaponSerial>:<breechFaceType>:<firingPinType>:<salt>)
function Nyx.Ballistics.ComputeBreechPinHash(weaponSerial, breechFaceType, firingPinType, salt)
    weaponSerial = weaponSerial or "UNKNOWN_SERIAL"
    breechFaceType = breechFaceType or "STANDARD_RECTANGULAR"
    firingPinType = firingPinType or "HEMISPHERICAL_PIN"
    salt = salt or "BREECH_SALT_88"

    local raw = string.format("MECHANICAL:%s:%s:%s:%s", weaponSerial, breechFaceType, firingPinType, salt)
    return sha256(raw)
end

-- Pure Formula 3: Shell Casing Ejection Mark Signature Hash
-- SHA-256(CASING_EJECT:<weaponSerial>:<breechPinHash>:<ejectionAngleDeg>:<salt>)
function Nyx.Ballistics.ComputeCasingEjectionHash(weaponSerial, breechPinHash, ejectionAngleDeg, salt)
    weaponSerial = weaponSerial or "UNKNOWN_SERIAL"
    breechPinHash = breechPinHash or "0000000000000000000000000000000000000000000000000000000000000000"
    ejectionAngleDeg = tonumber(ejectionAngleDeg) or 45.0
    salt = salt or "EJECT_SALT_77"

    local raw = string.format("CASING_EJECT:%s:%s:%.2f:%s", weaponSerial, breechPinHash, ejectionAngleDeg, salt)
    return sha256(raw)
end

-- Pure Formula 4: NIBIN Correlation Match Logic
-- Evaluates two ballistics records (entryA and entryB)
-- Returns matchStatus ('CONFIRMED_MATCH', 'CANDIDATE_MATCH', 'UNMATCHED') and matchScore (0.0 - 1.0)
function Nyx.Ballistics.EvaluateNIBINMatch(entryA, entryB)
    if not entryA or not entryB then
        return "UNMATCHED", 0.0
    end

    -- Direct serial match
    if entryA.weaponSerial and entryB.weaponSerial and entryA.weaponSerial == entryB.weaponSerial and entryA.weaponSerial ~= "NYX-UNKNOWN" then
        return "CONFIRMED_MATCH", 1.0
    end

    -- Rifling microstriation match
    if entryA.riflingHash and entryB.riflingHash and entryA.riflingHash == entryB.riflingHash then
        return "CONFIRMED_MATCH", 0.98
    end

    -- Casing ejection mark match
    if entryA.casingEjectionHash and entryB.casingEjectionHash and entryA.casingEjectionHash == entryB.casingEjectionHash then
        return "CONFIRMED_MATCH", 0.95
    end

    -- Caliber check + Breech pin / partial hash similarity (Candidate Match)
    if entryA.caliber and entryB.caliber and entryA.caliber == entryB.caliber then
        if entryA.casingEjectionHash and entryB.casingEjectionHash then
            -- Substring prefix match for partial striations / scratched barrels
            if entryA.casingEjectionHash:sub(1, 16) == entryB.casingEjectionHash:sub(1, 16) then
                return "CANDIDATE_MATCH", 0.75
            end
        end
        if entryA.riflingHash and entryB.riflingHash then
            if entryA.riflingHash:sub(1, 16) == entryB.riflingHash:sub(1, 16) then
                return "CANDIDATE_MATCH", 0.70
            end
        end
    end

    return "UNMATCHED", 0.0
end
