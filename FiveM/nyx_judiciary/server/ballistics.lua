--[[
    Nyxframework: nyx_judiciary
    File: server/ballistics.lua
    Description: Authoritative server-side forensic ballistics engine, rifling profile registration,
                 ejected shell casing telemetry tracking, NIBIN automated cross-referencing & case linking.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}
Nyx.Judiciary.Ballistics = Nyx.Judiciary.Ballistics or {}

-- 1. Ensure or generate weapon barrel rifling profile
function Nyx.Judiciary.Ballistics.GetOrCreateRiflingProfile(weaponSerial, weaponModel)
    weaponSerial = weaponSerial or "NYX-UNKNOWN"
    weaponModel = weaponModel or "weapon_pistol"

    local existing = MySQL.single.await([[
        SELECT `weapon_serial`, `weapon_model`, `caliber`, `rifling_twist`, `groove_count`,
               `breech_face_hash`, `firing_pin_hash`, `rifling_microstriation_hash`
        FROM `nyx_ballistics_rifling_profiles`
        WHERE `weapon_serial` = ?
    ]], { weaponSerial })

    if existing then
        return existing
    end

    local caliber = Nyx.Ballistics.GetCaliber(weaponModel)
    local salt = Nyx.Judiciary.GenerateSalt and Nyx.Judiciary.GenerateSalt(8) or "RIFLE_SALT_99"
    local breechSalt = Nyx.Judiciary.GenerateSalt and Nyx.Judiciary.GenerateSalt(8) or "BREECH_SALT_88"

    local riflingHash = Nyx.Ballistics.ComputeRiflingHash(weaponSerial, weaponModel, caliber, salt)
    local breechPinHash = Nyx.Ballistics.ComputeBreechPinHash(weaponSerial, "STANDARD_RECTANGULAR", "HEMISPHERICAL_PIN", breechSalt)
    local firingPinHash = Nyx.Ballistics.Sha256("PIN:" .. weaponSerial .. ":" .. breechSalt)

    MySQL.prepare.await([[
        INSERT INTO `nyx_ballistics_rifling_profiles`
            (`weapon_serial`, `weapon_model`, `caliber`, `rifling_twist`, `groove_count`,
             `breech_face_hash`, `firing_pin_hash`, `rifling_microstriation_hash`)
        VALUES (?, ?, ?, '1:10_RIGHT', 6, ?, ?, ?)
    ]], {
        weaponSerial,
        weaponModel,
        caliber,
        breechPinHash,
        firingPinHash,
        riflingHash
    })

    return {
        weapon_serial = weaponSerial,
        weapon_model = weaponModel,
        caliber = caliber,
        rifling_twist = "1:10_RIGHT",
        groove_count = 6,
        breech_face_hash = breechPinHash,
        firing_pin_hash = firingPinHash,
        rifling_microstriation_hash = riflingHash
    }
end

-- 2. Enhanced Ballistic Event Registration with Shell Casing Microstriation Ejection
function Nyx.Judiciary.Ballistics.RegisterDischargeEvent(src, weaponHash, coords, ejectionAngleDeg)
    local player = Nyx.GetPlayer(src)
    if not player then return nil end

    local weaponSerial = player:getMetadata("equippedWeaponSerial") or "NYX-UNKNOWN"
    local weaponModel = tostring(weaponHash)
    local profile = Nyx.Judiciary.Ballistics.GetOrCreateRiflingProfile(weaponSerial, weaponModel)

    ejectionAngleDeg = tonumber(ejectionAngleDeg) or 45.0
    local ejectSalt = Nyx.Judiciary.GenerateSalt and Nyx.Judiciary.GenerateSalt(8) or "EJECT_SALT_77"
    local casingEjectionHash = Nyx.Ballistics.ComputeCasingEjectionHash(weaponSerial, profile.breech_face_hash, ejectionAngleDeg, ejectSalt)

    -- Register transient crime scene evidence via main evidence engine
    local dropId, rootHash = Nyx.Judiciary.RegisterBallisticEvent(src, weaponHash, coords)

    -- Attach enhanced ballistics metadata to active evidence drop
    if dropId and Nyx.Judiciary.ActiveEvidence and Nyx.Judiciary.ActiveEvidence[dropId] then
        local active = Nyx.Judiciary.ActiveEvidence[dropId]
        active.metadata.casingEjectionHash = casingEjectionHash
        active.metadata.riflingHash = profile.rifling_microstriation_hash
        active.metadata.breechFaceHash = profile.breech_face_hash
        active.metadata.firingPinHash = profile.firing_pin_hash
        active.metadata.caliber = profile.caliber
        active.metadata.weaponSerial = weaponSerial
        active.metadata.ejectionAngle = ejectionAngleDeg
    end

    return dropId, rootHash, casingEjectionHash, profile.rifling_microstriation_hash
end

-- 3. Register Evidence Record in NIBIN Database & Automated Cross-Referencing
function Nyx.Judiciary.Ballistics.RegisterNIBINEntry(src, evidenceId, crimeSceneDocketId)
    local officer = Nyx.GetPlayer(src)
    if not officer then return false, "OFFICER_NOT_FOUND" end

    local evidence = MySQL.single.await([[
        SELECT `evidence_id`, `type`, `metadata` FROM `nyx_judiciary_evidence` WHERE `evidence_id` = ?
    ]], { evidenceId })

    if not evidence then
        return false, "EVIDENCE_NOT_FOUND"
    end

    local meta = {}
    if type(evidence.metadata) == "string" then
        local ok, parsed = pcall(json.decode, evidence.metadata)
        if ok and type(parsed) == "table" then meta = parsed end
    elseif type(evidence.metadata) == "table" then
        meta = evidence.metadata
    end

    local casingHash = meta.casingEjectionHash or "CASING_HASH_NONE"
    local riflingHash = meta.riflingHash or "RIFLING_HASH_NONE"
    local caliber = meta.caliber or "9mm"
    local weaponSerial = meta.weaponSerial or nil

    local entryId = "NIBIN-" .. (Nyx.Judiciary.GenerateUUID and Nyx.Judiciary.GenerateUUID() or tostring(os.time()))

    -- Perform automated scan against existing NIBIN entries for matches
    local existingEntries = MySQL.query.await([[
        SELECT `entry_id`, `evidence_id`, `weapon_serial`, `casing_ejection_hash`, `rifling_hash`, `caliber`, `match_status`
        FROM `nyx_nibin_database`
        WHERE `caliber` = ? AND `entry_id` != ?
    ]], { caliber, entryId })

    local bestMatchStatus = "UNMATCHED"
    local bestMatchedEntryId = nil
    local currentEntryObj = {
        weaponSerial = weaponSerial,
        casingEjectionHash = casingHash,
        riflingHash = riflingHash,
        caliber = caliber
    }

    for _, existing in ipairs(existingEntries or {}) do
        local targetObj = {
            weaponSerial = existing.weapon_serial,
            casingEjectionHash = existing.casing_ejection_hash,
            riflingHash = existing.rifling_hash,
            caliber = existing.caliber
        }

        local status, score = Nyx.Ballistics.EvaluateNIBINMatch(currentEntryObj, targetObj)
        if status == "CONFIRMED_MATCH" then
            bestMatchStatus = "CONFIRMED_MATCH"
            bestMatchedEntryId = existing.entry_id

            -- Update candidate entry as well
            MySQL.prepare.await([[
                UPDATE `nyx_nibin_database`
                SET `match_status` = 'CONFIRMED_MATCH', `matched_entry_id` = ?
                WHERE `entry_id` = ?
            ]], { entryId, existing.entry_id })
            break
        elseif status == "CANDIDATE_MATCH" and bestMatchStatus ~= "CONFIRMED_MATCH" then
            bestMatchStatus = "CANDIDATE_MATCH"
            bestMatchedEntryId = existing.entry_id
        end
    end

    -- Insert NIBIN Record
    local insertOk = MySQL.prepare.await([[
        INSERT INTO `nyx_nibin_database`
            (`entry_id`, `evidence_id`, `weapon_serial`, `casing_ejection_hash`, `rifling_hash`,
             `caliber`, `crime_scene_docket_id`, `registered_by_citizen_id`, `match_status`, `matched_entry_id`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        entryId,
        evidenceId,
        weaponSerial or nil,
        casingHash,
        riflingHash,
        caliber,
        crimeSceneDocketId or nil,
        officer.citizenId,
        bestMatchStatus,
        bestMatchedEntryId or nil
    })

    if not insertOk then
        return false, "DATABASE_ERROR"
    end

    -- Log NIBIN audit block in Chain of Custody
    Nyx.Judiciary.AppendCustodyBlock(
        evidenceId,
        "LAB_ANALYZED",
        officer.citizenId,
        nil,
        "nibin:national_registry",
        "NIBIN Correlation Analysis Complete. Status: " .. bestMatchStatus,
        { nibinEntryId = entryId, matchStatus = bestMatchStatus, matchedEntryId = bestMatchedEntryId }
    )

    return true, {
        entryId = entryId,
        evidenceId = evidenceId,
        matchStatus = bestMatchStatus,
        matchedEntryId = bestMatchedEntryId,
        casingEjectionHash = casingHash,
        riflingHash = riflingHash
    }
end

-- 4. Query NIBIN Correlation Records for MDT / Forensic UI
function Nyx.Judiciary.Ballistics.QueryNIBINRecords(filterCaliber, matchStatusOnly)
    local conditions = {}
    local params = {}

    if filterCaliber and filterCaliber ~= "all" and filterCaliber ~= "" then
        table.insert(conditions, "`caliber` = ?")
        table.insert(params, filterCaliber)
    end

    if matchStatusOnly and matchStatusOnly ~= "all" and matchStatusOnly ~= "" then
        table.insert(conditions, "`match_status` = ?")
        table.insert(params, matchStatusOnly)
    end

    local whereClause = ""
    if #conditions > 0 then
        whereClause = "WHERE " .. table.concat(conditions, " AND ")
    end

    local sql = string.format([[
        SELECT `entry_id`, `evidence_id`, `weapon_serial`, `casing_ejection_hash`, `rifling_hash`,
               `caliber`, `crime_scene_docket_id`, `registered_by_citizen_id`, `match_status`,
               `matched_entry_id`, `created_at`
        FROM `nyx_nibin_database`
        %s
        ORDER BY `created_at` DESC
        LIMIT 50
    ]], whereClause)

    return MySQL.query.await(sql, params) or {}
end
