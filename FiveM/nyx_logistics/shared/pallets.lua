--[[
    Nyxframework: nyx_logistics
    File: shared/pallets.lua
    Description: Pure Lua 5.4 physical heavy freight pallet formulas, vehicle slot matrices,
                 dynamic prop resolution, and capacity invariants.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Pallets = {}

-- Constant Constraints
Nyx.Pallets.MaxWeight = (Config and Config.PalletMaxWeight) or 1000000 -- 1,000,000 grams = 1,000 kg
Nyx.Pallets.MaxSlots = (Config and Config.PalletMaxSlots) or 20         -- 20 heavy cargo slots

-- Prop Models by Load Bracket
Nyx.Pallets.Models = {
    Empty = "prop_pallet_01a",
    Light = "prop_boxpile_02b",
    Medium = "prop_boxpile_05a",
    Heavy = "prop_boxpile_06a"
}

-- Commercial Vehicle Slot Matrices
local function joaatSafe(key)
    if type(key) == "number" then return key end
    if type(joaat) == "function" then return joaat(key) end
    if type(GetHashKey) == "function" then return GetHashKey(key) end
    -- Fallback simple string hash for pure Lua test runner environments
    local hash = 0
    for i = 1, #key do
        hash = (hash + string.byte(key, i)) % 2147483647
    end
    return hash
end

Nyx.Pallets.VehicleProfiles = {
    ['flatbed'] = {
        name = "flatbed",
        maxSlots = 3,
        slots = {
            [1] = { offset = { x = 0.0, y = -1.20, z = 0.45 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.0, y = -2.80, z = 0.45 }, heading = 0.0, bone = 0 },
            [3] = { offset = { x = 0.0, y = -4.40, z = 0.45 }, heading = 0.0, bone = 0 }
        }
    },
    ['mule'] = {
        name = "mule",
        maxSlots = 2,
        slots = {
            [1] = { offset = { x = 0.0, y = -1.50, z = 0.20 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.0, y = -3.20, z = 0.20 }, heading = 0.0, bone = 0 }
        }
    },
    ['mule2'] = {
        name = "mule2",
        maxSlots = 2,
        slots = {
            [1] = { offset = { x = 0.0, y = -1.50, z = 0.20 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.0, y = -3.20, z = 0.20 }, heading = 0.0, bone = 0 }
        }
    },
    ['mule3'] = {
        name = "mule3",
        maxSlots = 2,
        slots = {
            [1] = { offset = { x = 0.0, y = -1.50, z = 0.20 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.0, y = -3.20, z = 0.20 }, heading = 0.0, bone = 0 }
        }
    },
    ['mule4'] = {
        name = "mule4",
        maxSlots = 2,
        slots = {
            [1] = { offset = { x = 0.0, y = -1.50, z = 0.20 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.0, y = -3.20, z = 0.20 }, heading = 0.0, bone = 0 }
        }
    },
    ['benson'] = {
        name = "benson",
        maxSlots = 4,
        slots = {
            [1] = { offset = { x = 0.0, y = -1.00, z = 0.30 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.0, y = -2.40, z = 0.30 }, heading = 0.0, bone = 0 },
            [3] = { offset = { x = 0.0, y = -3.80, z = 0.30 }, heading = 0.0, bone = 0 },
            [4] = { offset = { x = 0.0, y = -5.20, z = 0.30 }, heading = 0.0, bone = 0 }
        }
    },
    ['pounder'] = {
        name = "pounder",
        maxSlots = 6,
        slots = {
            [1] = { offset = { x = -0.45, y = -1.20, z = 0.40 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.45, y = -1.20, z = 0.40 }, heading = 0.0, bone = 0 },
            [3] = { offset = { x = -0.45, y = -2.80, z = 0.40 }, heading = 0.0, bone = 0 },
            [4] = { offset = { x = 0.45, y = -2.80, z = 0.40 }, heading = 0.0, bone = 0 },
            [5] = { offset = { x = -0.45, y = -4.40, z = 0.40 }, heading = 0.0, bone = 0 },
            [6] = { offset = { x = 0.45, y = -4.40, z = 0.40 }, heading = 0.0, bone = 0 }
        }
    },
    ['pounder2'] = {
        name = "pounder2",
        maxSlots = 6,
        slots = {
            [1] = { offset = { x = -0.45, y = -1.20, z = 0.40 }, heading = 0.0, bone = 0 },
            [2] = { offset = { x = 0.45, y = -1.20, z = 0.40 }, heading = 0.0, bone = 0 },
            [3] = { offset = { x = -0.45, y = -2.80, z = 0.40 }, heading = 0.0, bone = 0 },
            [4] = { offset = { x = 0.45, y = -2.80, z = 0.40 }, heading = 0.0, bone = 0 },
            [5] = { offset = { x = -0.45, y = -4.40, z = 0.40 }, heading = 0.0, bone = 0 },
            [6] = { offset = { x = 0.45, y = -4.40, z = 0.40 }, heading = 0.0, bone = 0 }
        }
    },
    ['forklift'] = {
        name = "forklift",
        maxSlots = 1,
        slots = {
            [1] = { offset = { x = 0.0, y = 1.40, z = -0.20 }, heading = 0.0, bone = 0 }
        }
    }
}

--- Resolves the vehicle pallet carrier profile by model name or hash
--- @param model string|number
--- @return table|nil
function Nyx.Pallets.GetVehicleProfile(model)
    if not model then return nil end
    if type(model) == "string" then
        local lower = string.lower(model)
        if Nyx.Pallets.VehicleProfiles[lower] then
            return Nyx.Pallets.VehicleProfiles[lower]
        end
        local h = joaatSafe(lower)
        for _, prof in pairs(Nyx.Pallets.VehicleProfiles) do
            if joaatSafe(prof.name) == h then
                return prof
            end
        end
    elseif type(model) == "number" then
        for _, prof in pairs(Nyx.Pallets.VehicleProfiles) do
            if joaatSafe(prof.name) == model then
                return prof
            end
        end
    end
    return nil
end

--- Resolves the 3D attachment offset for a given vehicle model and slot index
--- @param model string|number
--- @param slotIndex number
--- @return table|nil
function Nyx.Pallets.GetVehicleSlotOffset(model, slotIndex)
    local prof = Nyx.Pallets.GetVehicleProfile(model)
    if not prof or not prof.slots then return nil end
    slotIndex = tonumber(slotIndex) or 1
    return prof.slots[slotIndex]
end

--- Finds the lowest unoccupied pallet slot for a vehicle
--- @param model string|number
--- @param occupiedSlots table<number, boolean>
--- @return number|nil slotIndex, string|nil error
function Nyx.Pallets.FindAvailableSlot(model, occupiedSlots)
    local prof = Nyx.Pallets.GetVehicleProfile(model)
    if not prof then
        return nil, "VEHICLE_NOT_PALLET_CARRIER"
    end

    occupiedSlots = occupiedSlots or {}
    for i = 1, prof.maxSlots do
        if not occupiedSlots[i] then
            return i, nil
        end
    end

    return nil, "VEHICLE_PALLET_SLOTS_FULL"
end

--- Determines the appropriate visual 3D prop model based on cumulative weight and item count
--- @param totalWeight number
--- @param itemCount number
--- @return string
function Nyx.Pallets.ResolvePalletModel(totalWeight, itemCount)
    local count = tonumber(itemCount) or 0
    local weight = math.max(0, tonumber(totalWeight) or 0)

    if count <= 0 or weight <= 0 then
        return Nyx.Pallets.Models.Empty
    elseif weight <= 300000 then -- <= 300 kg
        return Nyx.Pallets.Models.Light
    elseif weight <= 700000 then -- <= 700 kg
        return Nyx.Pallets.Models.Medium
    else
        return Nyx.Pallets.Models.Heavy
    end
end

--- Checks if a pallet can hold additional weight without exceeding the 1,000 kg cap
--- @param currentWeight number
--- @param addedWeight number
--- @return boolean
function Nyx.Pallets.CanHoldWeight(currentWeight, addedWeight)
    local cur = math.max(0, tonumber(currentWeight) or 0)
    local add = math.max(0, tonumber(addedWeight) or 0)
    return (cur + add) <= Nyx.Pallets.MaxWeight
end

--- Checks if a pallet can accept another slot item
--- @param currentSlotCount number
--- @return boolean
function Nyx.Pallets.CanHoldSlot(currentSlotCount)
    local cur = math.max(0, tonumber(currentSlotCount) or 0)
    return cur < Nyx.Pallets.MaxSlots
end

--- Validates if a pallet is eligible to be sealed for secure transit
--- @param itemCount number
--- @param totalWeight number
--- @return boolean, string|nil
function Nyx.Pallets.CanSealPallet(itemCount, totalWeight)
    local count = tonumber(itemCount) or 0
    local weight = tonumber(totalWeight) or 0

    if count <= 0 then
        return false, "CANNOT_SEAL_EMPTY_PALLET"
    end
    if weight <= 0 then
        return false, "INVALID_WEIGHT"
    end
    return true, nil
end

-- ============================================================================
-- Industrial Freight Pallet Breaching & Forensic Contamination Engine
-- ============================================================================

-- Tool Profiles for Prying Open Tamper-Sealed Heavy Freight Pallets
Nyx.Pallets.BreachTools = {
    ['tool_crowbar'] = {
        name = 'tool_crowbar',
        label = 'Heavy Forged Crowbar',
        baseSuccess = 0.85,
        wearPerAttempt = 6.0,
        noiseRadius = 25.0,
        lacerationRisk = 0.12,
        lacerationDamage = 8,
        fingerprintRisk = 0.85,
        alarmTripChance = 0.40,
        durationMs = 4500
    },
    ['weapon_crowbar'] = {
        name = 'weapon_crowbar',
        label = 'Standard Crowbar',
        baseSuccess = 0.80,
        wearPerAttempt = 8.0,
        noiseRadius = 28.0,
        lacerationRisk = 0.16,
        lacerationDamage = 10,
        fingerprintRisk = 0.85,
        alarmTripChance = 0.45,
        durationMs = 5000
    },
    ['tool_lockpick'] = {
        name = 'tool_lockpick',
        label = 'Precision Pick / Prying Wire',
        baseSuccess = 0.30,
        wearPerAttempt = 35.0,
        noiseRadius = 10.0,
        lacerationRisk = 0.05,
        lacerationDamage = 4,
        fingerprintRisk = 0.80,
        alarmTripChance = 0.15,
        durationMs = 8000
    }
}

-- Pure Lua 5.4 SHA-256 Hasher for Deterministic Toolmark Striations
local function sha256_pure(str)
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

Nyx.Pallets.Sha256 = sha256_pure

--- Generates a unique, formatted tamper security seal serial
--- @param palletId string
--- @param timestamp number|nil
--- @return string
function Nyx.Pallets.GenerateSealSerial(palletId, timestamp)
    local ts = tonumber(timestamp) or os.time()
    local suffix = string.sub(tostring(palletId or "PLT"), -6):upper()
    return string.format("SEAL-%s-%04d", suffix, ts % 10000)
end

--- Computes deterministic SHA-256 toolmark hash from crowbar serial and crime scene coordinates
--- @param toolSerial string
--- @param citizenId string
--- @param coords table
--- @param salt string|nil
--- @return string
function Nyx.Pallets.DetermineToolmarkHash(toolSerial, citizenId, coords, salt)
    toolSerial = toolSerial or "CRW-UNKNOWN"
    citizenId = citizenId or "UNKNOWN"
    coords = coords or { x = 0.0, y = 0.0, z = 0.0 }
    salt = salt or "TOOLMARK_SALT"
    local raw = string.format("TOOLMARK:%s:%s:%.2f,%.2f,%.2f:%s",
        toolSerial,
        citizenId,
        coords.x or 0.0,
        coords.y or 0.0,
        coords.z or 0.0,
        salt
    )
    return sha256_pure(raw)
end

--- Calculates the physical outcome, tool wear, acoustic noise, and forensic traces of a crowbar breach
--- @param toolName string
--- @param toolDurability number
--- @param hasGloves boolean
--- @param isUnionMember boolean
--- @param randomSeed number|nil
--- @return table outcome
function Nyx.Pallets.CalculateBreachOutcome(toolName, toolDurability, hasGloves, isUnionMember, randomSeed)
    local profile = Nyx.Pallets.BreachTools[toolName] or Nyx.Pallets.BreachTools['tool_crowbar']
    toolDurability = math.max(0.0, math.min(100.0, tonumber(toolDurability) or 100.0))

    -- Base success calculation
    local successChance = profile.baseSuccess
    if isUnionMember == true then
        successChance = successChance + 0.10
    end
    if toolDurability < 25.0 then
        successChance = successChance - 0.15
    end
    successChance = math.max(0.05, math.min(0.98, successChance))

    -- Pseudo-random determinism if seed supplied, else math.random
    local r1, r2, r3, r4
    if randomSeed then
        r1 = ((randomSeed * 9301 + 49297) % 233280) / 233280.0
        r2 = (((randomSeed + 1) * 9301 + 49297) % 233280) / 233280.0
        r3 = (((randomSeed + 2) * 9301 + 49297) % 233280) / 233280.0
        r4 = (((randomSeed + 3) * 9301 + 49297) % 233280) / 233280.0
    else
        r1 = math.random()
        r2 = math.random()
        r3 = math.random()
        r4 = math.random()
    end

    local success = (r1 <= successChance)

    -- Tool wear deduction (failure puts additional strain on metal)
    local wear = profile.wearPerAttempt * (success and 1.0 or 1.5)
    local remainingDurability = math.max(0.0, toolDurability - wear)
    local isBroken = (remainingDurability <= 0.0)

    -- Forensic Fingerprints: 100% immune if wearing gloves, otherwise based on risk roll
    local fingerprintLeft = false
    if not hasGloves then
        fingerprintLeft = (r2 <= profile.fingerprintRisk)
    end

    -- Biological DNA / Laceration: Slipping on metal bandings or wood splinters
    local effectiveLacerationRisk = hasGloves and (profile.lacerationRisk * 0.15) or profile.lacerationRisk
    local dnaLeft = (r3 <= effectiveLacerationRisk)
    local lacerationDamage = dnaLeft and profile.lacerationDamage or 0

    -- Commercial Alarm Trip: Acoustic vibration or tamper sensor trip
    local alarmTriggered = (r4 <= profile.alarmTripChance)

    return {
        success = success,
        successChance = math.floor(successChance * 100) / 100,
        wearDeduction = math.floor(wear * 10) / 10,
        remainingDurability = math.floor(remainingDurability * 10) / 10,
        isBroken = isBroken,
        hasGloves = (hasGloves == true),
        fingerprintLeft = fingerprintLeft,
        dnaLeft = dnaLeft,
        lacerationDamage = lacerationDamage,
        alarmTriggered = alarmTriggered,
        noiseRadius = profile.noiseRadius,
        durationMs = profile.durationMs,
        toolLabel = profile.label
    }
end

--- Zero-trust RPC payload validation for pallet breach
--- @param payload table
--- @return boolean, string|nil
function Nyx.Pallets.ValidateBreachPayload(payload)
    if not payload or type(payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end

    local palletId = payload.palletId
    if not palletId or type(palletId) ~= "string" or #palletId < 3 or #palletId > 64 then
        return false, "INVALID_PALLET_ID"
    end

    local toolItem = payload.toolItem or "tool_crowbar"
    if type(toolItem) ~= "string" or not Nyx.Pallets.BreachTools[toolItem] then
        return false, "INVALID_BREACH_TOOL"
    end

    if payload.coords then
        if type(payload.coords) ~= "table" or type(payload.coords.x) ~= "number" or type(payload.coords.y) ~= "number" then
            return false, "INVALID_COORDINATES"
        end
    end

    return true, nil
end

--- Formats visual badge for freight pallet security status
--- @param pallet table
--- @return string
function Nyx.Pallets.FormatPalletStatusBadge(pallet)
    if not pallet then return "[UNKNOWN]" end
    if pallet.is_tampered then
        return "[TAMPERED / BREACHED]"
    elseif pallet.is_sealed then
        return "[SEALED / SECURE]"
    else
        return "[OPEN / UNSEALED]"
    end
end

