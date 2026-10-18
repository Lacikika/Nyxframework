--[[
    Nyxframework: nyx_judiciary
    File: server/evidence.lua
    Description: Authoritative forensic chain-of-custody engine, deterministic SHA-256 fingerprinting,
                 transient crime scene tracking, and tamper verification.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}
Nyx.Judiciary.ActiveEvidence = {} -- [evidenceId] = { evidenceId, type, hash, originCitizenId, coords, metadata, expiresAt }

-- Pure Lua 5.4 SHA-256 Cryptographic Hasher
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

-- Expose SHA-256 in Judiciary namespace
Nyx.Judiciary.Sha256 = sha256

-- Utility: Generate random alphanumeric salt
local function generateSalt(len)
    len = len or (Config.Forensics and Config.Forensics.SaltLength or 8)
    local chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local res = {}
    for i = 1, len do
        local rand = math.random(1, #chars)
        res[i] = chars:sub(rand, rand)
    end
    return table.concat(res)
end

-- Utility: Generate UUIDv4 string
local function generateUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

-- Caliber mapping helper
local function getCaliberByWeapon(weaponHash)
    local hash = tonumber(weaponHash) or 0
    if hash == `WEAPON_PISTOL` or hash == `WEAPON_COMBATPISTOL` or hash == `WEAPON_SMG` then
        return "9mm"
    elseif hash == `WEAPON_CARBINERIFLE` or hash == `WEAPON_SPECIALCARBINE` then
        return "5.56x45mm"
    elseif hash == `WEAPON_PUMPSHOTGUN` then
        return "12-gauge"
    end
    return "unknown"
end

-- 1. Register Ballistic Discharge Event (Casings, Projectiles)
function Nyx.Judiciary.RegisterBallisticEvent(src, weaponHash, coords)
    local player = Nyx.GetPlayer(src)
    if not player then return end

    local serialNumber = player:getMetadata("equippedWeaponSerial") or "NYX-UNKNOWN"
    local caliber = getCaliberByWeapon(weaponHash)
    local salt = generateSalt()
    local dropId = generateUUID()

    -- Deterministic Fingerprint Formula: SHA-256(SourceSerial || OriginCitizenID || Coordinates || Salt)
    local rawString = string.format("%s:%s:%.2f,%.2f,%.2f:%s",
        serialNumber,
        player.citizenId,
        coords.x, coords.y, coords.z,
        salt
    )
    local hash = sha256(rawString)

    local evidenceData = {
        evidenceId = dropId,
        type = "casing",
        hash = hash,
        originCitizenId = player.citizenId,
        coords = vector3(coords.x, coords.y, coords.z),
        metadata = {
            weaponSerial = serialNumber,
            caliber = caliber,
            weaponHash = weaponHash,
            salt = salt,
            originCitizenId = player.citizenId,
            coords = { x = coords.x, y = coords.y, z = coords.z }
        },
        expiresAt = os.time() + (Config.Forensics and Config.Forensics.TransientDecaySeconds or 3600)
    }

    Nyx.Judiciary.ActiveEvidence[dropId] = evidenceData

    -- Broadcast transient evidence node to nearby forensic personnel
    TriggerClientEvent("nyx:judiciary:client:evidenceCreated", -1, {
        evidenceId = dropId,
        type = "casing",
        coords = { x = coords.x, y = coords.y, z = coords.z }
    })

    if Config.Debug then
        print(string.format("^2[Nyx:Judiciary]^7 Ballistic drop registered: %s (Hash: %s)^7", dropId, hash:sub(1, 12)))
    end

    return dropId, hash
end

-- 2. Register Trauma & Biological Event (Blood, DNA)
function Nyx.Judiciary.RegisterTraumaEvent(victimSrc, attackerSrc, damageType, coords)
    local victim = Nyx.GetPlayer(victimSrc)
    if not victim then return end

    local bloodType = victim:getMetadata("bloodType") or "O+"
    local salt = generateSalt()
    local dropId = generateUUID()
    local sourceSerial = "BLOOD-" .. bloodType

    local rawString = string.format("%s:%s:%.2f,%.2f,%.2f:%s",
        sourceSerial,
        victim.citizenId,
        coords.x, coords.y, coords.z,
        salt
    )
    local hash = sha256(rawString)

    local evidenceData = {
        evidenceId = dropId,
        type = "blood",
        hash = hash,
        originCitizenId = victim.citizenId,
        coords = vector3(coords.x, coords.y, coords.z),
        metadata = {
            sourceSerial = sourceSerial,
            bloodType = bloodType,
            damageType = damageType or "blunt",
            salt = salt,
            originCitizenId = victim.citizenId,
            coords = { x = coords.x, y = coords.y, z = coords.z }
        },
        expiresAt = os.time() + (Config.Forensics and Config.Forensics.TransientDecaySeconds or 3600)
    }

    Nyx.Judiciary.ActiveEvidence[dropId] = evidenceData

    TriggerClientEvent("nyx:judiciary:client:evidenceCreated", -1, {
        evidenceId = dropId,
        type = "blood",
        coords = { x = coords.x, y = coords.y, z = coords.z }
    })

    return dropId, hash
end

-- 3. Register Latent Fingerprint Event
function Nyx.Judiciary.RegisterFingerprintEvent(src, surfaceDesc, coords)
    local player = Nyx.GetPlayer(src)
    if not player then return end

    local sourceSerial = "FP-" .. player.citizenId
    local salt = generateSalt()
    local dropId = generateUUID()

    local rawString = string.format("%s:%s:%.2f,%.2f,%.2f:%s",
        sourceSerial,
        player.citizenId,
        coords.x, coords.y, coords.z,
        salt
    )
    local hash = sha256(rawString)

    local evidenceData = {
        evidenceId = dropId,
        type = "fingerprint",
        hash = hash,
        originCitizenId = player.citizenId,
        coords = vector3(coords.x, coords.y, coords.z),
        metadata = {
            sourceSerial = sourceSerial,
            surface = surfaceDesc or "generic",
            salt = salt,
            originCitizenId = player.citizenId,
            coords = { x = coords.x, y = coords.y, z = coords.z }
        },
        expiresAt = os.time() + (Config.Forensics and Config.Forensics.TransientDecaySeconds or 3600)
    }

    Nyx.Judiciary.ActiveEvidence[dropId] = evidenceData

    TriggerClientEvent("nyx:judiciary:client:evidenceCreated", -1, {
        evidenceId = dropId,
        type = "fingerprint",
        coords = { x = coords.x, y = coords.y, z = coords.z }
    })

    return dropId, hash
end

-- 4. Authoritative Collection & Contamination Check
function Nyx.Judiciary.CollectEvidence(src, evidenceId, useGloves)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "PLAYER_NOT_FOUND" end

    local drop = Nyx.Judiciary.ActiveEvidence[evidenceId]
    if not drop then return false, "EVIDENCE_NOT_FOUND" end

    -- Distance verification
    local pPos = player:getPosition()
    local playerVec = vector3(pPos.x, pPos.y, pPos.z)
    local dist = #(playerVec - drop.coords)
    local maxDist = Config.Forensics and Config.Forensics.MaxCollectionDistance or 2.5
    if dist > maxDist then
        return false, "TOO_FAR_FROM_EVIDENCE"
    end

    -- Contamination Check: Verify whether collector is wearing gloves
    local isContaminated = 0
    local contaminationSource = nil

    local hasGloves = false
    if useGloves == true or player:getMetadata("glovesEquipped") == true then
        hasGloves = true
    end

    if not hasGloves then
        -- Compromised chain-of-custody: collector's skin touches evidence
        isContaminated = 1
        contaminationSource = player.citizenId
    end

    -- Persist evidence item into the judiciary evidence database table
    local metadataJson = json.encode(drop.metadata)
    local insertOk = MySQL.prepare.await([[
        INSERT INTO `nyx_judiciary_evidence`
            (`evidence_id`, `type`, `evidence_hash`, `collector_citizen_id`, `is_contaminated`, `contamination_source`, `metadata`)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        drop.evidenceId,
        drop.type,
        drop.hash,
        player.citizenId,
        isContaminated,
        contaminationSource,
        metadataJson
    })

    if not insertOk then
        return false, "DATABASE_COMMIT_FAILED"
    end

    -- Give sealed evidence bag item to the collector's inventory
    local invId = "citizen:" .. player.citizenId
    local bagMetadata = {
        evidenceId = drop.evidenceId,
        evidenceHash = drop.hash,
        evidenceType = drop.type,
        isContaminated = (isContaminated == 1),
        contaminationSource = contaminationSource,
        collectorCitizenId = player.citizenId,
        collectedAt = os.time(),
        details = drop.metadata
    }

    local added, reason = exports['nyx_inventory']:AddItem(invId, Config.Forensics.EvidenceBagItem or "evidence_bag", 1, bagMetadata)
    if not added then
        if Config.Debug then
            print(string.format("^3[Nyx:Judiciary]^7 Warning: Could not add evidence_bag item to %s: %s^7", invId, tostring(reason)))
        end
    end

    -- Remove transient evidence drop from active crime scene
    Nyx.Judiciary.ActiveEvidence[evidenceId] = nil

    -- Broadcast removal to all clients
    TriggerClientEvent("nyx:judiciary:client:evidenceRemoved", -1, evidenceId)

    return true, {
        evidenceId = drop.evidenceId,
        evidenceHash = drop.hash,
        isContaminated = (isContaminated == 1),
        contaminationSource = contaminationSource
    }
end

-- 5. Cryptographic Tamper Verification Routine
function Nyx.Judiciary.VerifyEvidence(evidenceIdOrHash)
    if not evidenceIdOrHash then return false, "INVALID_INPUT" end

    local row = MySQL.single.await([[
        SELECT `evidence_id`, `docket_id`, `type`, `evidence_hash`, `collector_citizen_id`,
               `is_contaminated`, `contamination_source`, `metadata`, `created_at`
        FROM `nyx_judiciary_evidence`
        WHERE `evidence_id` = ? OR `evidence_hash` = ?
    ]], { evidenceIdOrHash, evidenceIdOrHash })

    if not row then
        return false, "EVIDENCE_NOT_FOUND"
    end

    local meta = {}
    if type(row.metadata) == "string" then
        local ok, parsed = pcall(json.decode, row.metadata)
        if ok and type(parsed) == "table" then
            meta = parsed
        end
    elseif type(row.metadata) == "table" then
        meta = row.metadata
    end

    -- Reconstruct raw fingerprint string from verified metadata
    local serial = meta.weaponSerial or meta.sourceSerial or "UNKNOWN"
    local originCitId = meta.originCitizenId or meta.citizenId or "UNKNOWN"
    local coords = meta.coords or { x = 0.0, y = 0.0, z = 0.0 }
    local salt = meta.salt or ""

    local reconstructedRaw = string.format("%s:%s:%.2f,%.2f,%.2f:%s",
        serial,
        originCitId,
        coords.x or 0.0, coords.y or 0.0, coords.z or 0.0,
        salt
    )
    local recomputedHash = sha256(reconstructedRaw)

    -- Integrity Validation
    if recomputedHash ~= row.evidence_hash then
        return false, "HASH_MISMATCH_TAMPERED", {
            recomputedHash = recomputedHash,
            storedHash = row.evidence_hash,
            evidenceId = row.evidence_id
        }
    end

    -- Contamination Evaluation
    if tonumber(row.is_contaminated) == 1 then
        return true, "CHAIN_COMPROMISED_CONTAMINATED", {
            evidenceId = row.evidence_id,
            evidenceHash = row.evidence_hash,
            contaminationSource = row.contamination_source,
            collector = row.collector_citizen_id,
            type = row.type,
            metadata = meta
        }
    end

    return true, "CHAIN_OF_CUSTODY_VALID", {
        evidenceId = row.evidence_id,
        evidenceHash = row.evidence_hash,
        collector = row.collector_citizen_id,
        type = row.type,
        metadata = meta
    }
end

-- 6. Periodic Sweep for Natural Decay of Uncollected Crime Scene Clues
function Nyx.Judiciary.SweepExpiredEvidence()
    local now = os.time()
    local expired = {}

    for id, evidence in pairs(Nyx.Judiciary.ActiveEvidence) do
        if now >= evidence.expiresAt then
            table.insert(expired, id)
        end
    end

    for _, id in ipairs(expired) do
        Nyx.Judiciary.ActiveEvidence[id] = nil
        TriggerClientEvent("nyx:judiciary:client:evidenceRemoved", -1, id)
    end
end
