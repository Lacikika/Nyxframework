--[[
    Nyxframework: nyx_judiciary
    File: server/evidence.lua
    Description: Authoritative forensic chain-of-custody engine, deterministic SHA-256 fingerprinting,
                 transient crime scene tracking, cryptographic block hash chaining, and tamper verification.
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

Nyx.Judiciary.GenerateSalt = generateSalt

-- Utility: Generate UUIDv4 string
local function generateUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

Nyx.Judiciary.GenerateUUID = generateUUID

-- Utility: Compute cryptographic block hash for chain of custody
local function computeChainHash(prevHash, evidenceId, sequenceId, action, custodianCitId, recipientCitId, facilityId, timestamp, salt)
    local raw = string.format("%s:%s:%d:%s:%s:%s:%s:%d:%s",
        tostring(prevHash or "GENESIS"),
        tostring(evidenceId),
        tonumber(sequenceId) or 1,
        tostring(action),
        tostring(custodianCitId or "NONE"),
        tostring(recipientCitId or "NONE"),
        tostring(facilityId or "NONE"),
        tonumber(timestamp) or 0,
        tostring(salt or "")
    )
    return sha256(raw)
end

Nyx.Judiciary.ComputeChainHash = computeChainHash

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

-- 4. Register Forensic Swab Event (GSR or DNA)
function Nyx.Judiciary.RegisterSwabEvent(src, targetCitId, swabType, coords, isGSRPositive)
    local officer = Nyx.GetPlayer(src)
    if not officer then return false, "OFFICER_NOT_FOUND" end

    swabType = swabType or "gsr"
    local salt = generateSalt()
    local dropId = generateUUID()
    local gsrFlag = isGSRPositive and "POS" or "NEG"

    -- Deterministic Formula: SHA-256(SWAB-<Type> || TargetCitizenId || GSRFlag || Coords || Salt)
    local rawString = string.format("SWAB-%s:%s:%s:%.2f,%.2f,%.2f:%s",
        swabType,
        targetCitId or "UNKNOWN",
        gsrFlag,
        coords.x, coords.y, coords.z,
        salt
    )
    local hash = sha256(rawString)

    local evidenceData = {
        evidenceId = dropId,
        type = "swab",
        hash = hash,
        originCitizenId = targetCitId or officer.citizenId,
        coords = vector3(coords.x, coords.y, coords.z),
        metadata = {
            swabType = swabType,
            targetCitizenId = targetCitId,
            isGSRPositive = (isGSRPositive == true),
            collectorCitizenId = officer.citizenId,
            salt = salt,
            coords = { x = coords.x, y = coords.y, z = coords.z }
        },
        expiresAt = os.time() + (Config.Forensics and Config.Forensics.TransientDecaySeconds or 3600)
    }

    Nyx.Judiciary.ActiveEvidence[dropId] = evidenceData

    TriggerClientEvent("nyx:judiciary:client:evidenceCreated", -1, {
        evidenceId = dropId,
        type = "swab",
        coords = { x = coords.x, y = coords.y, z = coords.z }
    })

    return dropId, hash
end

-- 5. Register CCTV Camera Snapshot / Photographic Evidence
function Nyx.Judiciary.RegisterPhotoEvidence(src, cameraLocation, snapshotHashOrData, coords, notes)
    local officer = Nyx.GetPlayer(src)
    if not officer then return false, "PLAYER_NOT_FOUND" end

    local salt = generateSalt()
    local evidenceId = generateUUID()
    cameraLocation = cameraLocation or "MUNICIPAL_CCTV_CAM"
    local snapshot = snapshotHashOrData or ("SNAP-" .. os.time())

    -- Deterministic Formula: SHA-256(PHOTO || CameraLocation || Snapshot || Coords || Salt)
    local rawString = string.format("PHOTO:%s:%s:%.2f,%.2f,%.2f:%s",
        cameraLocation,
        snapshot,
        coords.x, coords.y, coords.z,
        salt
    )
    local hash = sha256(rawString)

    local metadata = {
        cameraLocation = cameraLocation,
        snapshotHash = snapshot,
        collectorCitizenId = officer.citizenId,
        notes = notes or "Surveillance camera frame capture",
        salt = salt,
        coords = { x = coords.x, y = coords.y, z = coords.z }
    }

    local timestamp = os.time()
    local genesisFacility = "person:" .. officer.citizenId

    -- Directly persist photo evidence and genesis chain entry
    local insertOk = MySQL.prepare.await([[
        INSERT INTO `nyx_judiciary_evidence`
            (`evidence_id`, `type`, `evidence_hash`, `collector_citizen_id`, `current_custodian_id`,
             `current_facility`, `current_chain_hash`, `chain_length`, `is_contaminated`, `is_sealed`, `metadata`)
        VALUES (?, 'photo', ?, ?, ?, ?, ?, 1, 0, 1, ?)
    ]], {
        evidenceId,
        hash,
        officer.citizenId,
        officer.citizenId,
        genesisFacility,
        hash, -- Initial chain hash before genesis block calculation
        json.encode(metadata)
    })

    if not insertOk then
        return false, "DATABASE_ERROR"
    end

    -- Genesis Block for Photo Evidence
    local blockSalt = generateSalt()
    local entryHash = computeChainHash(hash, evidenceId, 1, "COLLECTED", officer.citizenId, nil, genesisFacility, timestamp, blockSalt)

    MySQL.prepare.await([[
        INSERT INTO `nyx_judiciary_chain_of_custody`
            (`evidence_id`, `sequence_id`, `action`, `custodian_citizen_id`, `recipient_citizen_id`,
             `facility_id`, `previous_hash`, `entry_hash`, `notes`, `metadata`)
        VALUES (?, 1, 'COLLECTED', ?, NULL, ?, ?, ?, 'Initial photographic capture and digital sealing', ?)
    ]], {
        evidenceId,
        officer.citizenId,
        genesisFacility,
        hash,
        entryHash,
        json.encode({ salt = blockSalt, timestamp = timestamp, isDigital = true })
    })

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_evidence`
        SET `current_chain_hash` = ?,
            `chain_length` = 1
        WHERE `evidence_id` = ?
    ]], { entryHash, evidenceId })

    -- Add sealed item to officer's inventory
    local invId = "citizen:" .. officer.citizenId
    local bagMetadata = {
        evidenceId = evidenceId,
        evidenceHash = hash,
        currentChainHash = entryHash,
        sequence = 1,
        evidenceType = "photo",
        collectorCitizenId = officer.citizenId,
        collectedAt = timestamp,
        details = metadata
    }
    exports['nyx_inventory']:AddItem(invId, Config.Forensics.EvidenceBagItem or "evidence_bag", 1, bagMetadata)

    return true, {
        evidenceId = evidenceId,
        evidenceHash = hash,
        currentChainHash = entryHash,
        sequence = 1
    }
end

-- 6. Authoritative Collection & Genesis Chain-of-Custody Creation
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

    local timestamp = os.time()
    local genesisFacility = "person:" .. player.citizenId
    local genesisSalt = generateSalt()

    -- Compute Genesis Block Hash (Sequence 1, Previous Hash = Root Evidence Hash)
    local genesisEntryHash = computeChainHash(
        drop.hash,
        drop.evidenceId,
        1,
        "COLLECTED",
        player.citizenId,
        nil,
        genesisFacility,
        timestamp,
        genesisSalt
    )

    -- Persist evidence item into the judiciary evidence database table
    local metadataJson = json.encode(drop.metadata)
    local insertOk = MySQL.prepare.await([[
        INSERT INTO `nyx_judiciary_evidence`
            (`evidence_id`, `type`, `evidence_hash`, `collector_citizen_id`, `current_custodian_id`,
             `current_facility`, `current_chain_hash`, `chain_length`, `is_contaminated`,
             `contamination_source`, `is_sealed`, `metadata`)
        VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, 1, ?)
    ]], {
        drop.evidenceId,
        drop.type,
        drop.hash,
        player.citizenId,
        player.citizenId,
        genesisFacility,
        genesisEntryHash,
        isContaminated,
        contaminationSource,
        metadataJson
    })

    if not insertOk then
        return false, "DATABASE_COMMIT_FAILED"
    end

    -- Insert Genesis Block into immutable chain-of-custody registry
    local blockMeta = {
        salt = genesisSalt,
        timestamp = timestamp,
        isContaminated = (isContaminated == 1),
        contaminationSource = contaminationSource
    }

    local blockOk = MySQL.prepare.await([[
        INSERT INTO `nyx_judiciary_chain_of_custody`
            (`evidence_id`, `sequence_id`, `action`, `custodian_citizen_id`, `recipient_citizen_id`,
             `facility_id`, `previous_hash`, `entry_hash`, `notes`, `metadata`)
        VALUES (?, 1, 'COLLECTED', ?, NULL, ?, ?, ?, 'Initial crime scene forensic collection', ?)
    ]], {
        drop.evidenceId,
        player.citizenId,
        genesisFacility,
        drop.hash,
        genesisEntryHash,
        json.encode(blockMeta)
    })

    if not blockOk then
        print(string.format("^1[Nyx:Judiciary]^7 Error creating genesis block for %s^7", drop.evidenceId))
    end

    -- Give sealed evidence bag item to the collector's inventory
    local invId = "citizen:" .. player.citizenId
    local bagMetadata = {
        evidenceId = drop.evidenceId,
        evidenceHash = drop.hash,
        currentChainHash = genesisEntryHash,
        sequence = 1,
        evidenceType = drop.type,
        isContaminated = (isContaminated == 1),
        contaminationSource = contaminationSource,
        collectorCitizenId = player.citizenId,
        collectedAt = timestamp,
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
        currentChainHash = genesisEntryHash,
        sequence = 1,
        isContaminated = (isContaminated == 1),
        contaminationSource = contaminationSource
    }
end

-- 7. Internal Helper: Append Verifiable Cryptographic Block to Chain of Custody
function Nyx.Judiciary.AppendCustodyBlock(evidenceId, action, custodianCitId, recipientCitId, facilityId, notes, blockMetadata)
    if not evidenceId or not action then
        return false, "INVALID_ARGUMENTS"
    end

    if not Config.Forensics or not Config.Forensics.AllowedActions or not Config.Forensics.AllowedActions[action] then
        return false, "INVALID_ACTION"
    end

    local evidence = MySQL.single.await([[
        SELECT `evidence_id`, `evidence_hash`, `current_custodian_id`, `current_facility`,
               `current_chain_hash`, `chain_length`, `is_sealed`
        FROM `nyx_judiciary_evidence`
        WHERE `evidence_id` = ?
    ]], { evidenceId })

    if not evidence then
        return false, "EVIDENCE_NOT_FOUND"
    end

    local latestBlock = MySQL.single.await([[
        SELECT `sequence_id`, `entry_hash`
        FROM `nyx_judiciary_chain_of_custody`
        WHERE `evidence_id` = ?
        ORDER BY `sequence_id` DESC
        LIMIT 1
    ]], { evidenceId })

    local newSeq = (latestBlock and tonumber(latestBlock.sequence_id) or 0) + 1
    local prevHash = latestBlock and latestBlock.entry_hash or evidence.evidence_hash
    local salt = generateSalt()
    local timestamp = os.time()

    local entryHash = computeChainHash(prevHash, evidenceId, newSeq, action, custodianCitId, recipientCitId, facilityId, timestamp, salt)

    local meta = blockMetadata or {}
    meta.salt = salt
    meta.timestamp = timestamp

    local insertOk = MySQL.prepare.await([[
        INSERT INTO `nyx_judiciary_chain_of_custody`
            (`evidence_id`, `sequence_id`, `action`, `custodian_citizen_id`, `recipient_citizen_id`,
             `facility_id`, `previous_hash`, `entry_hash`, `notes`, `metadata`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        evidenceId,
        newSeq,
        action,
        custodianCitId,
        recipientCitId or nil,
        facilityId or nil,
        prevHash,
        entryHash,
        notes or nil,
        json.encode(meta)
    })

    if not insertOk then
        return false, "DATABASE_ERROR"
    end

    -- Update parent evidence record
    local newCustodian = recipientCitId or custodianCitId
    local newFacility = facilityId or evidence.current_facility
    local isSealed = (action ~= 'DESTROYED') and 1 or 0

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_evidence`
        SET `current_custodian_id` = ?,
            `current_facility` = ?,
            `current_chain_hash` = ?,
            `chain_length` = ?,
            `is_sealed` = ?
        WHERE `evidence_id` = ?
    ]], { newCustodian, newFacility, entryHash, newSeq, isSealed, evidenceId })

    return true, {
        evidenceId = evidenceId,
        sequenceId = newSeq,
        action = action,
        entryHash = entryHash,
        previousHash = prevHash,
        custodian = newCustodian,
        facility = newFacility
    }
end

-- 8. Transfer Physical Custody (Officer-to-Officer / Handoff)
function Nyx.Judiciary.TransferCustody(src, evidenceId, targetCitId, notes)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "PLAYER_NOT_FOUND" end

    if not targetCitId or targetCitId == player.citizenId then
        return false, "INVALID_TARGET"
    end

    local evidence = MySQL.single.await([[
        SELECT `evidence_id`, `current_custodian_id` FROM `nyx_judiciary_evidence` WHERE `evidence_id` = ?
    ]], { evidenceId })

    if not evidence then
        return false, "EVIDENCE_NOT_FOUND"
    end

    if evidence.current_custodian_id and evidence.current_custodian_id ~= player.citizenId then
        local job = player:getMetadata("job")
        if not (job == "judge" or job == "admin") then
            return false, "NOT_CURRENT_CUSTODIAN"
        end
    end

    local targetFacility = "person:" .. targetCitId
    local ok, res = Nyx.Judiciary.AppendCustodyBlock(
        evidenceId,
        "TRANSFERRED",
        player.citizenId,
        targetCitId,
        targetFacility,
        notes or "Direct physical custody transfer",
        { transferredBy = player.citizenId, recipientCitizenId = targetCitId }
    )

    return ok, res
end

-- 9. Check Evidence into Secure Station Locker / Court Vault
function Nyx.Judiciary.StoreInLocker(src, evidenceId, lockerId, notes)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "PLAYER_NOT_FOUND" end

    local locker = Config.Forensics.Lockers and Config.Forensics.Lockers[lockerId]
    if not locker then
        return false, "INVALID_LOCKER_ID"
    end

    local evidence = MySQL.single.await([[
        SELECT `evidence_id`, `current_custodian_id` FROM `nyx_judiciary_evidence` WHERE `evidence_id` = ?
    ]], { evidenceId })

    if not evidence then
        return false, "EVIDENCE_NOT_FOUND"
    end

    local ok, res = Nyx.Judiciary.AppendCustodyBlock(
        evidenceId,
        "SECURED_IN_LOCKER",
        player.citizenId,
        nil,
        lockerId,
        notes or ("Secured in " .. locker.name),
        { lockerId = lockerId, lockerName = locker.name, storedBy = player.citizenId }
    )

    return ok, res
end

-- 10. Check Evidence out of Secure Depository
function Nyx.Judiciary.CheckoutFromLocker(src, evidenceId, lockerId, reason)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "PLAYER_NOT_FOUND" end

    local job = player:getMetadata("job") or "unemployed"
    if not Config.Forensics.AuthorizedJobs[job] and not (player.hasPermission and player:hasPermission("police")) then
        return false, "UNAUTHORIZED_ROLE"
    end

    local evidence = MySQL.single.await([[
        SELECT `evidence_id`, `current_facility` FROM `nyx_judiciary_evidence` WHERE `evidence_id` = ?
    ]], { evidenceId })

    if not evidence then
        return false, "EVIDENCE_NOT_FOUND"
    end

    if evidence.current_facility ~= lockerId then
        return false, "EVIDENCE_NOT_IN_SPECIFIED_LOCKER"
    end

    local myFacility = "person:" .. player.citizenId
    local ok, res = Nyx.Judiciary.AppendCustodyBlock(
        evidenceId,
        "CHECKED_OUT_LAB",
        "LOCKER:" .. lockerId,
        player.citizenId,
        myFacility,
        reason or "Checked out for active criminal investigation",
        { lockerId = lockerId, checkedOutBy = player.citizenId, reason = reason }
    )

    return ok, res
end

-- 11. Certified Forensic Laboratory Analysis & Report Generation
function Nyx.Judiciary.SubmitLabAnalysis(src, evidenceId, analysisType, findings)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "PLAYER_NOT_FOUND" end

    local analysisConfig = Config.Forensics.LabAnalysisTypes and Config.Forensics.LabAnalysisTypes[analysisType]
    if not analysisConfig then
        return false, "INVALID_ANALYSIS_TYPE"
    end

    local evidence = MySQL.single.await([[
        SELECT `evidence_id`, `type`, `metadata`, `lab_analysis` FROM `nyx_judiciary_evidence` WHERE `evidence_id` = ?
    ]], { evidenceId })

    if not evidence then
        return false, "EVIDENCE_NOT_FOUND"
    end

    -- Append LAB_ANALYZED block to chain
    local ok, res = Nyx.Judiciary.AppendCustodyBlock(
        evidenceId,
        "LAB_ANALYZED",
        player.citizenId,
        nil,
        "lab:davis:forensics",
        "Certified Analysis: " .. analysisConfig.label,
        {
            analysisType = analysisType,
            analysisLabel = analysisConfig.label,
            findings = findings,
            technician = player.citizenId,
            fee = analysisConfig.fee
        }
    )

    if not ok then
        return false, res
    end

    -- Update lab_analysis report log in evidence record
    local currentReports = {}
    if evidence.lab_analysis then
        if type(evidence.lab_analysis) == "string" then
            local okDecode, parsed = pcall(json.decode, evidence.lab_analysis)
            if okDecode and type(parsed) == "table" then
                currentReports = parsed
            end
        elseif type(evidence.lab_analysis) == "table" then
            currentReports = evidence.lab_analysis
        end
    end

    local report = {
        reportId = generateUUID(),
        analysisType = analysisType,
        analysisLabel = analysisConfig.label,
        findings = findings,
        certifiedTechnician = player.citizenId,
        timestamp = os.time(),
        blockHash = res.entryHash
    }

    table.insert(currentReports, report)

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_evidence`
        SET `lab_analysis` = ?
        WHERE `evidence_id` = ?
    ]], { json.encode(currentReports), evidenceId })

    return true, {
        evidenceId = evidenceId,
        report = report,
        chainBlock = res
    }
end

-- 12. Submit Evidence as Formal Court Exhibit Linked to Docket
function Nyx.Judiciary.SubmitExhibitToCourt(src, evidenceId, docketId, exhibitLabel, notes)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "PLAYER_NOT_FOUND" end

    local docket = MySQL.single.await([[
        SELECT `docket_id`, `status` FROM `nyx_judiciary_dockets` WHERE `docket_id` = ?
    ]], { docketId })

    if not docket then
        return false, "DOCKET_NOT_FOUND"
    end

    if docket.status == 'concluded' or docket.status == 'dismissed' then
        return false, "DOCKET_CLOSED"
    end

    exhibitLabel = exhibitLabel or ("Exhibit #" .. os.time())

    -- Update docket link and exhibit label
    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_evidence`
        SET `docket_id` = ?,
            `exhibit_label` = ?
        WHERE `evidence_id` = ?
    ]], { docketId, exhibitLabel, evidenceId })

    local ok, res = Nyx.Judiciary.AppendCustodyBlock(
        evidenceId,
        "SUBMITTED_EXHIBIT",
        player.citizenId,
        nil,
        "vault_court_district",
        notes or ("Entered into court record as " .. exhibitLabel),
        { docketId = docketId, exhibitLabel = exhibitLabel, submittedBy = player.citizenId }
    )

    return ok, res
end

-- 13. Query Full Historical Chain-of-Custody Ledger
function Nyx.Judiciary.GetEvidenceChainOfCustody(evidenceId)
    if not evidenceId then return {} end

    local blocks = MySQL.query.await([[
        SELECT `log_id`, `evidence_id`, `sequence_id`, `action`, `custodian_citizen_id`,
               `recipient_citizen_id`, `facility_id`, `previous_hash`, `entry_hash`,
               `notes`, `metadata`, `created_at`
        FROM `nyx_judiciary_chain_of_custody`
        WHERE `evidence_id` = ?
        ORDER BY `sequence_id` ASC
    ]], { evidenceId })

    local result = {}
    for _, blk in ipairs(blocks or {}) do
        local meta = {}
        if type(blk.metadata) == "string" then
            local ok, parsed = pcall(json.decode, blk.metadata)
            if ok and type(parsed) == "table" then meta = parsed end
        elseif type(blk.metadata) == "table" then
            meta = blk.metadata
        end
        blk.metadata = meta
        table.insert(result, blk)
    end

    return result
end

-- 14. Full Cryptographic Hash Chain Verification & Tamper Detection
function Nyx.Judiciary.VerifyChainOfCustody(evidenceId)
    if not evidenceId then return false, "INVALID_INPUT" end

    local evidence = MySQL.single.await([[
        SELECT `evidence_id`, `docket_id`, `type`, `evidence_hash`, `collector_citizen_id`,
               `current_custodian_id`, `current_facility`, `current_chain_hash`, `chain_length`,
               `is_contaminated`, `contamination_source`, `is_sealed`, `metadata`, `lab_analysis`, `exhibit_label`
        FROM `nyx_judiciary_evidence`
        WHERE `evidence_id` = ? OR `evidence_hash` = ?
    ]], { evidenceId, evidenceId })

    if not evidence then
        return false, "EVIDENCE_NOT_FOUND"
    end

    -- 1. Check physical fingerprint integrity of root evidence
    local meta = {}
    if type(evidence.metadata) == "string" then
        local ok, parsed = pcall(json.decode, evidence.metadata)
        if ok and type(parsed) == "table" then meta = parsed end
    elseif type(evidence.metadata) == "table" then
        meta = evidence.metadata
    end

    local recomputedRootHash = nil
    if evidence.type == "casing" or evidence.type == "blood" or evidence.type == "fingerprint" then
        local serial = meta.weaponSerial or meta.sourceSerial or "UNKNOWN"
        local originCitId = meta.originCitizenId or meta.citizenId or "UNKNOWN"
        local coords = meta.coords or { x = 0.0, y = 0.0, z = 0.0 }
        local salt = meta.salt or ""
        local raw = string.format("%s:%s:%.2f,%.2f,%.2f:%s",
            serial, originCitId, coords.x or 0.0, coords.y or 0.0, coords.z or 0.0, salt
        )
        recomputedRootHash = sha256(raw)
    elseif evidence.type == "swab" then
        local swabType = meta.swabType or "gsr"
        local targetCitId = meta.targetCitizenId or "UNKNOWN"
        local gsrFlag = meta.isGSRPositive and "POS" or "NEG"
        local coords = meta.coords or { x = 0.0, y = 0.0, z = 0.0 }
        local salt = meta.salt or ""
        local raw = string.format("SWAB-%s:%s:%s:%.2f,%.2f,%.2f:%s",
            swabType, targetCitId, gsrFlag, coords.x or 0.0, coords.y or 0.0, coords.z or 0.0, salt
        )
        recomputedRootHash = sha256(raw)
    elseif evidence.type == "photo" then
        local camLoc = meta.cameraLocation or "UNKNOWN"
        local snap = meta.snapshotHash or ""
        local coords = meta.coords or { x = 0.0, y = 0.0, z = 0.0 }
        local salt = meta.salt or ""
        local raw = string.format("PHOTO:%s:%s:%.2f,%.2f,%.2f:%s",
            camLoc, snap, coords.x or 0.0, coords.y or 0.0, coords.z or 0.0, salt
        )
        recomputedRootHash = sha256(raw)
    end

    if recomputedRootHash and recomputedRootHash ~= evidence.evidence_hash then
        return false, "ROOT_EVIDENCE_TAMPERED", {
            expected = evidence.evidence_hash,
            recomputed = recomputedRootHash
        }
    end

    -- 2. Fetch entire chain of custody
    local blocks = MySQL.query.await([[
        SELECT `log_id`, `evidence_id`, `sequence_id`, `action`, `custodian_citizen_id`,
               `recipient_citizen_id`, `facility_id`, `previous_hash`, `entry_hash`,
               `notes`, `metadata`, `created_at`
        FROM `nyx_judiciary_chain_of_custody`
        WHERE `evidence_id` = ?
        ORDER BY `sequence_id` ASC
    ]], { evidence.evidence_id })

    if not blocks or #blocks == 0 then
        return false, "CHAIN_EMPTY"
    end

    -- 3. Verify chronological cryptographic continuity and hash linkages
    local prevHashExpected = evidence.evidence_hash -- Sequence 1 points to root evidence_hash

    for i, blk in ipairs(blocks) do
        local seq = tonumber(blk.sequence_id)
        if seq ~= i then
            return false, "SEQUENCE_GAP_DETECTED", { expectedSeq = i, actualSeq = seq }
        end

        if blk.previous_hash ~= prevHashExpected then
            return false, "CHAIN_HASH_DISCONTINUITY", {
                sequence = seq,
                action = blk.action,
                expectedPrevHash = prevHashExpected,
                actualPrevHash = blk.previous_hash
            }
        end

        -- Parse block metadata for salt and timestamp
        local blkMeta = {}
        if type(blk.metadata) == "string" then
            local ok, parsed = pcall(json.decode, blk.metadata)
            if ok and type(parsed) == "table" then blkMeta = parsed end
        elseif type(blk.metadata) == "table" then
            blkMeta = blk.metadata
        end

        local bSalt = blkMeta.salt or ""
        local bTime = blkMeta.timestamp or 0

        local recomputedEntryHash = computeChainHash(
            blk.previous_hash,
            blk.evidence_id,
            seq,
            blk.action,
            blk.custodian_citizen_id,
            blk.recipient_citizen_id,
            blk.facility_id,
            bTime,
            bSalt
        )

        if recomputedEntryHash ~= blk.entry_hash then
            return false, "BLOCK_TAMPER_DETECTED", {
                sequence = seq,
                action = blk.action,
                storedHash = blk.entry_hash,
                recomputedHash = recomputedEntryHash
            }
        end

        prevHashExpected = blk.entry_hash
    end

    -- 4. Verify parent record matches tip of chain
    if blocks[#blocks].entry_hash ~= evidence.current_chain_hash then
        return false, "CHAIN_HEAD_MISMATCH", {
            parentChainHash = evidence.current_chain_hash,
            latestBlockHash = blocks[#blocks].entry_hash
        }
    end

    return true, "CHAIN_VERIFIED_AUTHENTIC", {
        evidenceId = evidence.evidence_id,
        evidenceType = evidence.type,
        rootHash = evidence.evidence_hash,
        currentChainHash = evidence.current_chain_hash,
        chainLength = #blocks,
        isContaminated = (tonumber(evidence.is_contaminated) == 1),
        contaminationSource = evidence.contamination_source,
        currentCustodian = evidence.current_custodian_id,
        currentFacility = evidence.current_facility,
        isSealed = (tonumber(evidence.is_sealed) == 1),
        docketId = evidence.docket_id,
        exhibitLabel = evidence.exhibit_label,
        blocks = blocks
    }
end

-- 15. Cryptographic Tamper Verification Routine (Legacy & Simple Validator)
function Nyx.Judiciary.VerifyEvidence(evidenceIdOrHash)
    if not evidenceIdOrHash then return false, "INVALID_INPUT" end

    local row = MySQL.single.await([[
        SELECT `evidence_id`, `docket_id`, `type`, `evidence_hash`, `collector_citizen_id`,
               `current_custodian_id`, `current_facility`, `current_chain_hash`, `chain_length`,
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
    local reconstructedRaw = nil
    if row.type == "casing" or row.type == "blood" or row.type == "fingerprint" then
        local serial = meta.weaponSerial or meta.sourceSerial or "UNKNOWN"
        local originCitId = meta.originCitizenId or meta.citizenId or "UNKNOWN"
        local coords = meta.coords or { x = 0.0, y = 0.0, z = 0.0 }
        local salt = meta.salt or ""
        reconstructedRaw = string.format("%s:%s:%.2f,%.2f,%.2f:%s",
            serial, originCitId, coords.x or 0.0, coords.y or 0.0, coords.z or 0.0, salt
        )
    elseif row.type == "swab" then
        local swabType = meta.swabType or "gsr"
        local targetCitId = meta.targetCitizenId or "UNKNOWN"
        local gsrFlag = meta.isGSRPositive and "POS" or "NEG"
        local coords = meta.coords or { x = 0.0, y = 0.0, z = 0.0 }
        local salt = meta.salt or ""
        reconstructedRaw = string.format("SWAB-%s:%s:%s:%.2f,%.2f,%.2f:%s",
            swabType, targetCitId, gsrFlag, coords.x or 0.0, coords.y or 0.0, coords.z or 0.0, salt
        )
    elseif row.type == "photo" then
        local camLoc = meta.cameraLocation or "UNKNOWN"
        local snap = meta.snapshotHash or ""
        local coords = meta.coords or { x = 0.0, y = 0.0, z = 0.0 }
        local salt = meta.salt or ""
        reconstructedRaw = string.format("PHOTO:%s:%s:%.2f,%.2f,%.2f:%s",
            camLoc, snap, coords.x or 0.0, coords.y or 0.0, coords.z or 0.0, salt
        )
    end

    local recomputedHash = reconstructedRaw and sha256(reconstructedRaw) or row.evidence_hash

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
            currentChainHash = row.current_chain_hash,
            chainLength = row.chain_length,
            contaminationSource = row.contamination_source,
            collector = row.collector_citizen_id,
            type = row.type,
            metadata = meta
        }
    end

    return true, "CHAIN_OF_CUSTODY_VALID", {
        evidenceId = row.evidence_id,
        evidenceHash = row.evidence_hash,
        currentChainHash = row.current_chain_hash,
        chainLength = row.chain_length,
        collector = row.collector_citizen_id,
        currentCustodian = row.current_custodian_id,
        currentFacility = row.current_facility,
        type = row.type,
        metadata = meta
    }
end

-- 16. Periodic Sweep for Natural Decay of Uncollected Crime Scene Clues
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
