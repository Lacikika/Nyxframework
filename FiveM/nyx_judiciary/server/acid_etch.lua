--[[
    Nyxframework: nyx_judiciary
    File: server/acid_etch.lua
    Description: Authoritative forensic chemical acid-etching engine, ballistic
                 cold-case correlation, chain-of-custody audit logging,
                 and cryptographic metallurgical report generation.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}
Nyx.AcidEtch = Nyx.AcidEtch or {}

-- 1. Helper: Find item by itemId in container
local function findItemByItemId(container, itemId)
    if not container or not container.items then return nil, nil end
    for slot, item in pairs(container.items) do
        if item and item.item_id == itemId then
            return item, slot
        end
    end
    return nil, nil
end

-- 2. Proximity Check for Certified Forensics Laboratory or Evidence Locker
function Nyx.AcidEtch.IsNearCertifiedLab(coords)
    if not coords then return true, "lab_davis_forensics", "Davis Regional Forensic Crime Laboratory" end
    local lockers = (Config.Forensics and Config.Forensics.Lockers) or {}
    local maxDist = (Nyx.AcidEtch.Config and Nyx.AcidEtch.Config.MaxLabDistance) or 4.0

    for id, locker in pairs(lockers) do
        if locker.coords then
            local dist = #(coords - locker.coords)
            if dist <= maxDist then
                return true, id, locker.name or id
            end
        end
    end

    -- Davis Crime Lab anchor default fallback
    local davisLabCoords = vector3(362.4, -1585.1, 29.2)
    if #(coords - davisLabCoords) <= 15.0 then
        return true, "lab_davis_forensics", "Davis Regional Forensic Crime Laboratory"
    end

    return false, nil, nil
end

-- 3. Query Ballistic Casings Matching Original Serial
function Nyx.AcidEtch.FindBallisticsMatches(originalSerial)
    if not originalSerial or originalSerial == "UNKNOWN" then
        return {}
    end

    local searchPattern = string.format("%%%s%%", originalSerial)
    local query = [[
        SELECT `evidence_id`, `type`, `evidence_hash`, `docket_id`, `metadata`, `created_at`
        FROM `nyx_judiciary_evidence`
        WHERE `type` IN ('casing', 'ballistics')
          AND `metadata` LIKE ?
        ORDER BY `created_at` DESC
        LIMIT 20
    ]]

    local rows = MySQL.Sync.fetchAll(query, { searchPattern }) or {}
    local matches = {}

    for _, row in ipairs(rows) do
        local meta = {}
        if type(row.metadata) == "string" then
            local ok, parsed = pcall(json.decode, row.metadata)
            if ok and type(parsed) == "table" then meta = parsed end
        elseif type(row.metadata) == "table" then
            meta = row.metadata
        end

        if meta.weaponSerial == originalSerial then
            matches[#matches + 1] = {
                evidenceId = row.evidence_id,
                type = row.type,
                hash = row.evidence_hash,
                docketId = row.docket_id,
                createdAt = row.created_at
            }
        end
    end

    return matches
end

-- 4. Authoritative Acid-Etch Execution
function Nyx.AcidEtch.ExecuteEtch(src, weaponSlot, kitSlot, invId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then
        return false, "UNAUTHORIZED"
    end

    local jobName = (player.job and player.job.name) or "unemployed"
    if not Nyx.AcidEtch.Config.AuthorizedJobs[jobName] and not (player.hasPermission and player:hasPermission("admin")) then
        return false, "UNAUTHORIZED_JOB"
    end

    -- Check Proximity to Certified Forensics Laboratory
    local ped = GetPlayerPed(tostring(src))
    local playerCoords = (ped and DoesEntityExist(ped)) and GetEntityCoords(ped) or nil
    local isNear, facilityId, facilityName = Nyx.AcidEtch.IsNearCertifiedLab(playerCoords)
    if not isNear then
        -- Allow mobile field testing if player is carrying a certified forensic kit
        local pInvId = string.format("char:%s:main", player.citizenId)
        local hasFieldKit = exports['nyx_inventory']:HasItem(pInvId, 'forensic_kit', 1)
        if not hasFieldKit then
            return false, "LAB_WORKBENCH_REQUIRED"
        end
        facilityId = "mobile_field_kit"
        facilityName = "Mobile CSI Forensic Field Unit"
    end

    invId = invId or string.format("char:%s:main", player.citizenId)
    local container = exports['nyx_inventory']:GetInventory(invId)
    if not container then
        return false, "CONTAINER_NOT_FOUND"
    end

    local weaponItem = container:getItem(weaponSlot)
    if not weaponItem then
        return false, "WEAPON_NOT_FOUND"
    end

    local kitItem = nil
    if kitSlot then
        kitItem = container:getItem(kitSlot)
    else
        kitItem, kitSlot = findItemByItemId(container, Nyx.AcidEtch.Config.RequiredKitItem)
    end

    local canEtch, err = Nyx.AcidEtch.CanEtchWeapon(weaponItem, kitItem, jobName)
    if not canEtch then
        return false, err
    end

    -- Pure Mathematical Chemical Etch Calculation
    local outcome = Nyx.AcidEtch.CalculateEtchOutcome(weaponItem, {
        seed = os.time() + src
    })

    -- Deduct Reagent Use
    kitItem.metadata = kitItem.metadata or {}
    local usesRemaining = (tonumber(kitItem.metadata.usesRemaining) or 5) - 1
    if usesRemaining <= 0 then
        container:removeItem(kitSlot)
    else
        kitItem.metadata.usesRemaining = usesRemaining
        container:setItem(kitSlot, kitItem)
    end

    -- Mutate Weapon Item Metadata
    weaponItem.metadata = weaponItem.metadata or {}
    weaponItem.metadata.acidEtched = true
    weaponItem.metadata.restoredSerial = outcome.restoredSerial
    weaponItem.metadata.restorationStatus = outcome.outcome
    weaponItem.metadata.etchedAt = os.time()
    weaponItem.metadata.etchedBy = player.citizenId
    weaponItem.metadata.facilityId = facilityId
    container:setItem(weaponSlot, weaponItem)
    container:save()

    -- Search for Cold-Case Ballistic Casings Matching Original Serial
    local ballisticMatches = Nyx.AcidEtch.FindBallisticsMatches(outcome.originalSerial)
    local hitIds = {}
    for _, hit in ipairs(ballisticMatches) do
        hitIds[#hitIds + 1] = hit.evidenceId
    end

    -- Generate Certified Forensic Metallurgical Report
    local reportData = {
        timestamp = os.time(),
        technicianCitizenId = player.citizenId,
        facilityName = facilityName,
        originalSerial = outcome.originalSerial,
        restoredSerial = outcome.restoredSerial,
        outcome = outcome.outcome,
        statusLabel = outcome.statusLabel,
        reagent = outcome.reagent,
        ballisticsHitCount = #hitIds,
        ballisticsEvidenceIds = hitIds
    }
    local labReport = Nyx.AcidEtch.FormatLabReport(reportData)
    local reportHash = Nyx.Judiciary.Sha256(labReport)
    local auditUuid = Nyx.Judiciary.GenerateUUID()
    local weaponUuid = weaponItem.item_uuid or Nyx.Judiciary.GenerateUUID()

    -- Update nyx_inventory_ground_weapons table
    MySQL.Async.execute([[
        UPDATE `nyx_inventory_ground_weapons`
        SET `restored_serial` = ?,
            `restoration_status` = ?,
            `etched_by_citizen_id` = ?,
            `etched_at` = NOW(),
            `lab_notes` = ?
        WHERE `weapon_uuid` = ? OR `original_serial` = ?
    ]], {
        outcome.restoredSerial,
        outcome.outcome,
        player.citizenId,
        outcome.statusLabel,
        weaponUuid,
        outcome.originalSerial
    })

    -- Insert Audit Record in nyx_judiciary_acid_etch_audits
    MySQL.Async.execute([[
        INSERT INTO `nyx_judiciary_acid_etch_audits`
            (`audit_uuid`, `weapon_uuid`, `weapon_item`, `technician_citizen_id`, `facility_id`, `original_serial`, `restored_serial`, `outcome`, `ballistics_hit_count`, `ballistics_evidence_ids`, `report_hash`, `lab_notes`)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        auditUuid,
        weaponUuid,
        weaponItem.item_id,
        player.citizenId,
        facilityId,
        outcome.originalSerial,
        outcome.restoredSerial,
        outcome.outcome,
        #hitIds,
        json.encode(hitIds),
        reportHash,
        labReport
    })

    return true, outcome, labReport, ballisticMatches
end

-- 5. RPC Endpoint: judiciary:acidEtchWeapon
exports['nyx_core']:RegisterRPC("judiciary:acidEtchWeapon", function(src, payload)
    local valid, err = Nyx.AcidEtch.ValidatePayload(payload)
    if not valid then
        return nil, err
    end

    local ok, outcome, labReport, matches = Nyx.AcidEtch.ExecuteEtch(src, payload.weaponSlot, payload.kitSlot, payload.invId)
    if not ok then
        return nil, outcome
    end

    return {
        success = true,
        outcome = outcome,
        report = labReport,
        matches = matches
    }
end)

-- 6. RPC Endpoint: judiciary:getAcidEtchHistory
exports['nyx_core']:RegisterRPC("judiciary:getAcidEtchHistory", function(src, filter)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then
        return nil, "UNAUTHORIZED"
    end

    local query = "SELECT * FROM `nyx_judiciary_acid_etch_audits` ORDER BY `created_at` DESC LIMIT 50"
    local params = {}

    if filter and filter.weaponUuid then
        query = "SELECT * FROM `nyx_judiciary_acid_etch_audits` WHERE `weapon_uuid` = ? ORDER BY `created_at` DESC LIMIT 20"
        params = { filter.weaponUuid }
    elseif filter and filter.serial then
        query = "SELECT * FROM `nyx_judiciary_acid_etch_audits` WHERE `original_serial` = ? OR `restored_serial` LIKE ? ORDER BY `created_at` DESC LIMIT 20"
        params = { filter.serial, "%" .. filter.serial .. "%" }
    end

    local rows = MySQL.Sync.fetchAll(query, params) or {}
    return {
        success = true,
        audits = rows
    }
end)
