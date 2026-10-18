--[[
    Nyxframework: nyx_judiciary
    File: server/warrants.lua
    Description: Authoritative judicial warrant engine (arrest, search, subpoena, wiretap)
                 with probable cause petitioning, cryptographic judicial signing,
                 live MDT dispatch tracking, and financial subpoena disclosure.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}

-- ----------------------------------------------------------------------------
-- 1. Petition Formal Probable Cause Warrant (Officer -> Judicial Council)
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.PetitionWarrant(petitionerCitId, targetCitId, warrantType, causeSummary, targetEntityId, subpoenaScope, durationHours)
    local rawData = {
        petitionerCitizenId = petitionerCitId,
        targetCitizenId = targetCitId,
        warrantType = warrantType,
        probableCauseSummary = causeSummary,
        targetEntityId = targetEntityId,
        subpoenaScope = subpoenaScope,
        requestedDurationHours = durationHours
    }

    local okVal, cleanData = Nyx.Warrants.ValidatePetition(rawData)
    if not okVal then
        return false, cleanData
    end

    local petitionId = string.format("pet-%s-%d", string.sub(petitionerCitId, 1, 8), os.time())

    local inserted = MySQL.insert.await([[
        INSERT INTO `nyx_judiciary_warrant_petitions`
            (`petition_id`, `petitioner_citizen_id`, `target_citizen_id`, `warrant_type`, `subpoena_scope`, `target_entity_id`, `probable_cause_summary`, `requested_duration_hours`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending_review')
    ]], {
        petitionId,
        cleanData.petitionerCitizenId,
        cleanData.targetCitizenId,
        cleanData.warrantType,
        cleanData.subpoenaScope,
        cleanData.targetEntityId,
        cleanData.probableCauseSummary,
        cleanData.requestedDurationHours
    })

    if not inserted then
        return false, "DATABASE_INSERT_FAILED"
    end

    local petitionPayload = {
        petitionId = petitionId,
        petitionerCitizenId = cleanData.petitionerCitizenId,
        targetCitizenId = cleanData.targetCitizenId,
        warrantType = cleanData.warrantType,
        subpoenaScope = cleanData.subpoenaScope,
        targetEntityId = cleanData.targetEntityId,
        probableCauseSummary = cleanData.probableCauseSummary,
        requestedDurationHours = cleanData.requestedDurationHours,
        status = "pending_review",
        createdAt = os.date("%Y-%m-%d %H:%M:%S")
    }

    -- Notify judges and judicial council
    TriggerClientEvent("nyx:judiciary:client:petitionSubmitted", -1, petitionPayload)

    if Config.Debug then
        print(string.format("^2[Nyx:Judiciary]^7 Warrant Petition #%s submitted by %s for %s (%s)^7",
            petitionId, petitionerCitId, targetCitId, warrantType))
    end

    return true, petitionPayload
end

-- ----------------------------------------------------------------------------
-- 2. Judicial Council Review & Cryptographic Signing (Judge -> Warrant)
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.ReviewPetition(petitionId, judgeCitId, decision, reviewNotes)
    if not petitionId or not judgeCitId or not decision then
        return false, "MISSING_REQUIRED_FIELDS"
    end

    if decision ~= "approved" and decision ~= "rejected" then
        return false, "INVALID_REVIEW_DECISION"
    end

    local petition = MySQL.single.await([[
        SELECT * FROM `nyx_judiciary_warrant_petitions`
        WHERE `petition_id` = ? AND `status` = 'pending_review'
    ]], { petitionId })

    if not petition then
        return false, "PETITION_NOT_PENDING"
    end

    local notes = reviewNotes or (decision == "approved" and "Probable cause established." or "Insufficient probable cause.")

    if decision == "rejected" then
        MySQL.update.await([[
            UPDATE `nyx_judiciary_warrant_petitions`
            SET `status` = 'rejected',
                `reviewed_by_judge_id` = ?,
                `review_notes` = ?,
                `reviewed_at` = CURRENT_TIMESTAMP
            WHERE `petition_id` = ?
        ]], { judgeCitId, notes, petitionId })

        TriggerClientEvent("nyx:judiciary:client:petitionRejected", -1, {
            petitionId = petitionId,
            petitionerCitizenId = petition.petitioner_citizen_id,
            targetCitizenId = petition.target_citizen_id,
            reason = notes
        })

        return true, {
            petitionId = petitionId,
            status = "rejected",
            reviewedBy = judgeCitId,
            notes = notes
        }
    end

    -- Decision == "approved"
    local nowEpoch = os.time()
    local signature = Nyx.Warrants.GenerateJudicialSignature(
        petitionId,
        judgeCitId,
        petition.target_citizen_id,
        petition.warrant_type,
        nowEpoch,
        "NYX_JUDICIAL_SEAL"
    )

    MySQL.update.await([[
        UPDATE `nyx_judiciary_warrant_petitions`
        SET `status` = 'approved',
            `reviewed_by_judge_id` = ?,
            `review_notes` = ?,
            `reviewed_at` = CURRENT_TIMESTAMP,
            `judicial_signature` = ?
        WHERE `petition_id` = ?
    ]], { judgeCitId, notes, signature, petitionId })

    -- Calculate warrant expiration
    local hours = tonumber(petition.requested_duration_hours) or 72
    local expireTime = os.date("%Y-%m-%d %H:%M:%S", nowEpoch + (hours * 3600))

    -- Wiretaps and Arrest warrants activate live tracking pings
    local isTrackingActive = (petition.warrant_type == "wiretap" or petition.warrant_type == "arrest") and 1 or 0

    local warrantId = MySQL.insert.await([[
        INSERT INTO `nyx_judiciary_warrants`
            (`target_citizen_id`, `issuing_judge_id`, `type`, `target_entity_id`, `petition_id`, `subpoena_scope`, `probable_cause_summary`, `judicial_signature`, `status`, `tracking_active`, `expires_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)
    ]], {
        petition.target_citizen_id,
        judgeCitId,
        petition.warrant_type,
        petition.target_entity_id or nil,
        petitionId,
        petition.subpoena_scope or nil,
        petition.probable_cause_summary,
        signature,
        isTrackingActive,
        expireTime
    })

    local warrantPayload = {
        warrantId = warrantId,
        petitionId = petitionId,
        targetCitizenId = petition.target_citizen_id,
        issuingJudgeId = judgeCitId,
        type = petition.warrant_type,
        subpoenaScope = petition.subpoena_scope,
        targetEntityId = petition.target_entity_id,
        probableCauseSummary = petition.probable_cause_summary,
        judicialSignature = signature,
        trackingActive = (isTrackingActive == 1),
        status = "active",
        expiresAt = expireTime
    }

    -- Broadcast to Police & DOJ Mobile Data Terminals (MDT)
    TriggerClientEvent("nyx:judiciary:client:warrantIssued", -1, warrantPayload)
    TriggerClientEvent("nyx:mdt:client:newWarrantAlert", -1, warrantPayload)

    if Config.Debug then
        print(string.format("^2[Nyx:Judiciary]^7 Warrant #%d APPROVED & SIGNED by %s for %s (%s, Sig: %s...)^7",
            warrantId, judgeCitId, petition.target_citizen_id, petition.warrant_type, string.sub(signature, 1, 16)))
    end

    return true, warrantPayload
end

-- ----------------------------------------------------------------------------
-- 3. Direct Issue (Fallback / Admin / Emergency Judicial Action)
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.IssueWarrant(issuingJudgeCitId, targetCitId, warrantType, causeSummary, targetEntityId, durationHours, petitionId, subpoenaScope)
    if not targetCitId or not warrantType or not causeSummary then
        return false, "MISSING_REQUIRED_FIELDS"
    end

    if not Config.Warrants.AllowedTypes[warrantType] then
        return false, "INVALID_WARRANT_TYPE"
    end

    local hours = tonumber(durationHours) or Config.Warrants.DefaultExpirationHours or 72
    local maxHours = Config.Warrants.MaxExpirationHours or 336
    if hours > maxHours then hours = maxHours end

    local nowEpoch = os.time()
    local expireTime = os.date("%Y-%m-%d %H:%M:%S", nowEpoch + (hours * 3600))
    local pId = petitionId or string.format("direct-%d", nowEpoch)

    local signature = Nyx.Warrants.GenerateJudicialSignature(
        pId,
        issuingJudgeCitId,
        targetCitId,
        warrantType,
        nowEpoch,
        "NYX_JUDICIAL_SEAL"
    )

    local isTrackingActive = (warrantType == "wiretap" or warrantType == "arrest") and 1 or 0

    local warrantId = MySQL.insert.await([[
        INSERT INTO `nyx_judiciary_warrants`
            (`target_citizen_id`, `issuing_judge_id`, `type`, `target_entity_id`, `petition_id`, `subpoena_scope`, `probable_cause_summary`, `judicial_signature`, `status`, `tracking_active`, `expires_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)
    ]], {
        targetCitId,
        issuingJudgeCitId,
        warrantType,
        targetEntityId or nil,
        pId,
        subpoenaScope or nil,
        causeSummary,
        signature,
        isTrackingActive,
        expireTime
    })

    if not warrantId or warrantId == 0 then
        return false, "DATABASE_ERROR"
    end

    local warrantPayload = {
        warrantId = warrantId,
        petitionId = pId,
        targetCitizenId = targetCitId,
        issuingJudgeId = issuingJudgeCitId,
        type = warrantType,
        subpoenaScope = subpoenaScope,
        targetEntityId = targetEntityId,
        probableCauseSummary = causeSummary,
        judicialSignature = signature,
        trackingActive = (isTrackingActive == 1),
        status = "active",
        expiresAt = expireTime
    }

    -- Broadcast to Police & DOJ Mobile Data Terminals (MDT)
    TriggerClientEvent("nyx:judiciary:client:warrantIssued", -1, warrantPayload)
    TriggerClientEvent("nyx:mdt:client:newWarrantAlert", -1, warrantPayload)

    if Config.Debug then
        print(string.format("^2[Nyx:Judiciary]^7 Warrant #%d issued for %s (%s, Expires: %s)^7",
            warrantId, targetCitId, warrantType, expireTime))
    end

    return true, warrantPayload
end

-- ----------------------------------------------------------------------------
-- 4. Subpoena Financial Records Disclosure Gatekeeper
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.GetSubpoenaFinancials(targetCitId, requestingOfficerCitId)
    if not targetCitId then
        return false, "MISSING_TARGET_CITIZEN_ID"
    end

    -- Verify active legal authorization (subpoena)
    local activeWarrants = Nyx.Judiciary.GetActiveWarrants(targetCitId)
    local okAccess, authWarrant = Nyx.Warrants.EvaluateWarrantAccess(activeWarrants, "financial_records")

    if not okAccess then
        return false, "SUBPOENA_REQUIRED_LEGAL_AUTHORIZATION_MISSING"
    end

    -- Legal authorization verified: query confidential accounts
    local charRow = MySQL.single.await([[
        SELECT `char_id`, `citizen_id`, `first_name`, `last_name`, `money`
        FROM `nyx_characters`
        WHERE `citizen_id` = ?
    ]], { targetCitId })

    if not charRow then
        return false, "CITIZEN_NOT_FOUND"
    end

    local moneyData = {}
    if charRow.money then
        local okJson, parsed = pcall(json.decode, charRow.money)
        if okJson and type(parsed) == "table" then moneyData = parsed end
    end

    -- Query transaction history from double-entry treasury ledger
    local citAccount = "citizen:" .. targetCitId
    local charAccount = "char:" .. targetCitId .. ":bank"
    local ledgerRows = MySQL.query.await([[
        SELECT `tx_uuid`, `category`, `debit_account`, `credit_account`, `amount`, `memo`, `created_at`
        FROM `nyx_treasury_ledger`
        WHERE `debit_account` IN (?, ?) OR `credit_account` IN (?, ?)
        ORDER BY `created_at` DESC
        LIMIT 25
    ]], { citAccount, charAccount, citAccount, charAccount }) or {}

    -- Query real estate assets
    local properties = MySQL.query.await([[
        SELECT `property_id`, `property_code`, `label`, `type`, `land_area_sqm`, `maintenance_condition`
        FROM `nyx_properties`
        WHERE `owner_citizen_id` = ?
    ]], { targetCitId }) or {}

    -- Query corporate equity shares from nyx_factions_members
    local shares = MySQL.query.await([[
        SELECT m.`faction_id`, f.`legal_name`, m.`role_title`, m.`equity_shares`
        FROM `nyx_factions_members` m
        JOIN `nyx_factions` f ON m.`faction_id` = f.`faction_id`
        WHERE m.`citizen_id` = ? AND m.`equity_shares` > 0.00
    ]], { targetCitId }) or {}

    return true, {
        targetCitizenId = targetCitId,
        warrantId = authWarrant.warrant_id,
        judicialSignature = authWarrant.judicial_signature,
        accountBalance = {
            cash = tonumber(moneyData.cash) or 0.00,
            bank = tonumber(moneyData.bank) or 0.00
        },
        transactions = ledgerRows,
        properties = properties,
        corporateShares = shares,
        subpoenaScope = authWarrant.subpoena_scope or "financial"
    }
end

-- ----------------------------------------------------------------------------
-- 5. Query Pending Petitions
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.GetPendingPetitions()
    local rows = MySQL.query.await([[
        SELECT * FROM `nyx_judiciary_warrant_petitions`
        WHERE `status` = 'pending_review'
        ORDER BY `created_at` ASC
    ]])
    return rows or {}
end

-- ----------------------------------------------------------------------------
-- 6. Query Active Tracking Warrants
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.GetActiveTrackingWarrants()
    local rows = MySQL.query.await([[
        SELECT * FROM `nyx_judiciary_warrants`
        WHERE `status` = 'active' AND `tracking_active` = 1 AND `expires_at` > CURRENT_TIMESTAMP
    ]])
    return rows or {}
end

-- ----------------------------------------------------------------------------
-- 7. Record Tracking Ping to Audit Logs
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.RecordTrackingPing(warrantId, targetCitId, coords, accuracyRadius, sourceType)
    local srcType = sourceType or "cellular_triangulation"
    local radius = tonumber(accuracyRadius) or 35.00

    MySQL.insert([[
        INSERT INTO `nyx_judiciary_tracking_logs`
            (`warrant_id`, `target_citizen_id`, `coords`, `accuracy_radius`, `source_type`)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        warrantId,
        targetCitId,
        json.encode(coords),
        radius,
        srcType
    })

    MySQL.prepare([[
        UPDATE `nyx_judiciary_warrants`
        SET `last_ping_at` = CURRENT_TIMESTAMP
        WHERE `warrant_id` = ?
    ]], { warrantId })
end

-- ----------------------------------------------------------------------------
-- 8. Rescind an Active Warrant
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.RescindWarrant(warrantId, judgeCitId, reason)
    local warrant = MySQL.single.await([[
        SELECT * FROM `nyx_judiciary_warrants` WHERE `warrant_id` = ? AND `status` = 'active'
    ]], { warrantId })

    if not warrant then
        return false, "WARRANT_NOT_ACTIVE"
    end

    local affected = MySQL.update.await([[
        UPDATE `nyx_judiciary_warrants`
        SET `status` = 'rescinded', `tracking_active` = 0
        WHERE `warrant_id` = ? AND `status` = 'active'
    ]], { warrantId })

    if affected and affected > 0 then
        TriggerClientEvent("nyx:judiciary:client:warrantUpdated", -1, {
            warrantId = warrantId,
            status = "rescinded",
            rescindedBy = judgeCitId,
            reason = reason
        })

        -- Remove active dispatch tracking blip
        TriggerClientEvent("nyx:mdt:client:clearTrackingBlip", -1, {
            warrantId = warrantId,
            targetCitizenId = warrant.target_citizen_id
        })

        return true
    end

    return false, "WARRANT_NOT_ACTIVE"
end

-- ----------------------------------------------------------------------------
-- 9. Execute / Fulfill a Warrant Upon Arrest or Search
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.ExecuteWarrant(warrantId, officerCitId)
    local warrant = MySQL.single.await([[
        SELECT * FROM `nyx_judiciary_warrants` WHERE `warrant_id` = ? AND `status` = 'active'
    ]], { warrantId })

    if not warrant then
        return false, "WARRANT_NOT_ACTIVE"
    end

    local affected = MySQL.update.await([[
        UPDATE `nyx_judiciary_warrants`
        SET `status` = 'executed', `tracking_active` = 0
        WHERE `warrant_id` = ? AND `status` = 'active'
    ]], { warrantId })

    if affected and affected > 0 then
        TriggerClientEvent("nyx:judiciary:client:warrantUpdated", -1, {
            warrantId = warrantId,
            status = "executed",
            executedBy = officerCitId
        })

        -- Remove active dispatch tracking blip
        TriggerClientEvent("nyx:mdt:client:clearTrackingBlip", -1, {
            warrantId = warrantId,
            targetCitizenId = warrant.target_citizen_id
        })

        return true
    end

    return false, "WARRANT_NOT_ACTIVE"
end

-- ----------------------------------------------------------------------------
-- 10. Query Active Warrants
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.GetActiveWarrants(targetCitId)
    local query = [[
        SELECT * FROM `nyx_judiciary_warrants`
        WHERE `status` = 'active' AND `expires_at` > CURRENT_TIMESTAMP
    ]]
    local params = {}

    if targetCitId then
        query = query .. " AND `target_citizen_id` = ?"
        table.insert(params, targetCitId)
    end

    query = query .. " ORDER BY `created_at` DESC"

    local rows = MySQL.query.await(query, params)
    return rows or {}
end

-- ----------------------------------------------------------------------------
-- 11. Sweep Expired Warrants & Clear Tracking
-- ----------------------------------------------------------------------------
function Nyx.Judiciary.SweepExpiredWarrants()
    local expiredWarrants = MySQL.query.await([[
        SELECT `warrant_id`, `target_citizen_id` FROM `nyx_judiciary_warrants`
        WHERE `status` = 'active' AND `expires_at` <= CURRENT_TIMESTAMP
    ]])

    if expiredWarrants and #expiredWarrants > 0 then
        local affected = MySQL.update.await([[
            UPDATE `nyx_judiciary_warrants`
            SET `status` = 'expired', `tracking_active` = 0
            WHERE `status` = 'active' AND `expires_at` <= CURRENT_TIMESTAMP
        ]])

        for _, w in ipairs(expiredWarrants) do
            TriggerClientEvent("nyx:mdt:client:clearTrackingBlip", -1, {
                warrantId = w.warrant_id,
                targetCitizenId = w.target_citizen_id
            })
        end

        if affected and affected > 0 and Config.Debug then
            print(string.format("^3[Nyx:Judiciary]^7 Swept %d expired judicial warrants^7", affected))
        end
    end
end
