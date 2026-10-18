--[[
    Nyxframework: nyx_treasury
    File: server/subpoena_audit.lua
    Description: Authoritative server engine for judicial subpoena forensic audits,
                 anomaly detection over double-entry ledger accounts,
                 and cryptographic evidence filing.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}
Nyx.SubpoenaAudit = Nyx.SubpoenaAudit or {}

local function generateUuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

-- 1. Authoritative Forensic Subpoena Audit Execution
function Nyx.Treasury.ExecuteSubpoenaAudit(src, warrantId, targetType, targetId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    targetType = targetType or "faction"
    if not targetId or type(targetId) ~= "string" or #targetId < 3 then
        return false, "INVALID_TARGET_ID"
    end

    -- 1. Query and Validate Judicial Subpoena Warrant
    local warrant = nil
    if tonumber(warrantId) then
        warrant = MySQL.single.await([[
            SELECT `warrant_id`, `type`, `subpoena_scope`, `target_entity_id`, `target_citizen_id`,
                   `judicial_signature`, `status`, `expires_at`
            FROM `nyx_judiciary_warrants`
            WHERE `warrant_id` = ?
        ]], { tonumber(warrantId) })
    else
        -- Search by petition or warrant ID string
        warrant = MySQL.single.await([[
            SELECT `warrant_id`, `type`, `subpoena_scope`, `target_entity_id`, `target_citizen_id`,
                   `judicial_signature`, `status`, `expires_at`
            FROM `nyx_judiciary_warrants`
            WHERE `target_entity_id` = ? OR `petition_id` = ?
            ORDER BY `warrant_id` DESC LIMIT 1
        ]], { targetId, warrantId })
    end

    if not warrant then
        -- Fallback: check if active subpoena exists in warrant petitions
        local petition = MySQL.single.await([[
            SELECT `petition_id`, `warrant_type` AS `type`, `subpoena_scope`, `target_entity_id`,
                   `target_citizen_id`, `judicial_signature`, `status`
            FROM `nyx_judiciary_warrant_petitions`
            WHERE `petition_id` = ? AND `status` = 'approved'
        ]], { warrantId })

        if petition then
            warrant = {
                warrant_id = petition.petition_id,
                type = petition.type,
                subpoena_scope = petition.subpoena_scope,
                target_entity_id = petition.target_entity_id,
                target_citizen_id = petition.target_citizen_id,
                judicial_signature = petition.judicial_signature,
                status = "active"
            }
        end
    end

    local okScope, scopeInfo = Nyx.SubpoenaAudit.ValidateSubpoenaScope(warrant, targetType, targetId)
    if not okScope then
        return false, scopeInfo
    end

    -- 2. Query Ledger Transactions for Target Account
    local targetAcc = (targetType == "faction") and ("faction:" .. targetId) or targetId
    local transactions = MySQL.query.await([[
        SELECT `entry_id`, `transaction_uuid`, `debit_account`, `credit_account`, `amount`,
               `tax_deducted`, `category`, `authorized_by`, `memo`, `created_at`,
               UNIX_TIMESTAMP(`created_at`) AS `created_at_unix`,
               HOUR(`created_at`) AS `hour_of_day`
        FROM `nyx_treasury_ledger`
        WHERE `debit_account` = ? OR `credit_account` = ?
        ORDER BY `created_at` DESC
        LIMIT 100
    ]], { targetAcc, targetAcc }) or {}

    -- 3. Query Commercial Register State if applicable
    local regData = nil
    if targetType == "register" then
        regData = MySQL.single.await([[
            SELECT * FROM `nyx_factions_commercial_registers` WHERE `register_id` = ?
        ]], { targetId })
    else
        -- Pick primary front register for faction if present
        regData = MySQL.single.await([[
            SELECT * FROM `nyx_factions_commercial_registers`
            WHERE `faction_id` = ?
            ORDER BY `total_washed` DESC LIMIT 1
        ]], { targetId })
    end

    local businessType = regData and regData.business_type or "retail"

    -- 4. Execute Pure Anomaly Analysis
    local audit = Nyx.SubpoenaAudit.AnalyzeLedgerAnomalies(transactions, regData, businessType)
    local auditUuid = generateUuid()

    local anomaliesJson = json.encode(audit.anomalies or {})

    -- 5. Optional Judiciary Evidence Filing
    local evidenceId = nil
    if exports['nyx_judiciary'] and exports['nyx_judiciary'].RegisterEvidence then
        local evidencePayload = {
            type = "financial",
            title = string.format("Subpoena Ledger Audit: %s", targetId),
            description = string.format("Forensic financial audit. Score: %.2f/100. Hash: %s", audit.anomalyScore, audit.reportHash),
            sha256 = audit.reportHash,
            collectedBy = player.citizenId,
            caseId = warrant and warrant.warrant_id or nil
        }
        local okEv, evRes = pcall(function()
            return exports['nyx_judiciary']:RegisterEvidence(evidencePayload)
        end)
        if okEv and evRes then
            evidenceId = tostring(evRes)
        end
    end

    -- 6. Insert Immutable Audit Log
    MySQL.prepare.await([[
        INSERT INTO `nyx_treasury_subpoena_audits`
        (`audit_uuid`, `subpoena_warrant_id`, `target_type`, `target_id`, `auditor_citizen_id`,
         `anomaly_score`, `suspicion_level`, `anomalies_detected`, `total_volume_audited`,
         `cash_ratio_pct`, `forensic_report_sha256`, `evidence_id`, `recommendation`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        auditUuid,
        tostring(warrant.warrant_id),
        targetType,
        targetId,
        player.citizenId,
        audit.anomalyScore,
        audit.suspicionLevel,
        anomaliesJson,
        audit.totalVolume,
        audit.cashRatioPct,
        audit.reportHash,
        evidenceId,
        audit.recommendation
    })

    return true, {
        auditUuid = auditUuid,
        warrantId = warrant.warrant_id,
        targetId = targetId,
        targetType = targetType,
        businessType = businessType,
        anomalyScore = audit.anomalyScore,
        suspicionLevel = audit.suspicionLevel,
        recommendation = audit.recommendation,
        totalVolume = audit.totalVolume,
        cashVolume = audit.cashVolume,
        cashRatioPct = audit.cashRatioPct,
        anomalies = audit.anomalies,
        reportHash = audit.reportHash,
        evidenceId = evidenceId,
        formattedSummary = Nyx.SubpoenaAudit.FormatAuditSummary(audit)
    }
end

-- 2. Query Subpoena Audit Report by UUID
function Nyx.Treasury.GetSubpoenaAuditReport(auditUuid)
    if not auditUuid then return false, "MISSING_AUDIT_UUID" end
    local row = MySQL.single.await([[
        SELECT * FROM `nyx_treasury_subpoena_audits` WHERE `audit_uuid` = ?
    ]], { auditUuid })

    if not row then return false, "AUDIT_NOT_FOUND" end

    local anomalies = {}
    if row.anomalies_detected and #row.anomalies_detected > 0 then
        local ok, parsed = pcall(json.decode, row.anomalies_detected)
        if ok and type(parsed) == "table" then anomalies = parsed end
    end

    return true, {
        auditUuid = row.audit_uuid,
        warrantId = row.subpoena_warrant_id,
        targetType = row.target_type,
        targetId = row.target_id,
        auditorCitizenId = row.auditor_citizen_id,
        anomalyScore = tonumber(row.anomaly_score) or 0.00,
        suspicionLevel = row.suspicion_level,
        anomalies = anomalies,
        totalVolume = tonumber(row.total_volume_audited) or 0.00,
        cashRatioPct = tonumber(row.cash_ratio_pct) or 0.00,
        reportHash = row.forensic_report_sha256,
        evidenceId = row.evidence_id,
        recommendation = row.recommendation,
        createdAt = row.created_at
    }
end

-- 3. Judicial Freeze of Commercial Registers / Accounts
function Nyx.Treasury.FreezeCommercialTarget(src, warrantId, targetType, targetId, reason)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    if targetType == "register" then
        if exports['nyx_factions'] and exports['nyx_factions'].FreezeRegister then
            return exports['nyx_factions']:FreezeRegister(targetId, player.citizenId, reason)
        end
    elseif targetType == "faction" then
        -- Freeze all commercial registers belonging to faction
        MySQL.prepare.await([[
            UPDATE `nyx_factions_commercial_registers`
            SET `is_frozen` = 1, `frozen_by` = ?, `freeze_reason` = ?
            WHERE `faction_id` = ?
        ]], { player.citizenId, reason or "Subpoena Asset Freeze", targetId })

        -- Freeze faction treasury vault if nyx_factions exports are available
        if exports['nyx_factions'] and exports['nyx_factions'].SetVaultFreeze then
            exports['nyx_factions']:SetVaultFreeze(player.citizenId, targetId, "vault:" .. targetId, true, reason)
        end

        return true
    end

    return false, "UNSUPPORTED_TARGET_TYPE"
end

-- 4. Register RPC Routes
CreateThread(function()
    while not exports['nyx_core'] or not exports['nyx_core'].RegisterRPC do
        Wait(50)
    end

    exports['nyx_core']:RegisterRPC("treasury:executeSubpoenaAudit", function(src, payload)
        if type(payload) ~= "table" then return false, "INVALID_PAYLOAD" end
        return Nyx.Treasury.ExecuteSubpoenaAudit(src, payload.warrantId, payload.targetType, payload.targetId)
    end)

    exports['nyx_core']:RegisterRPC("treasury:getSubpoenaAuditReport", function(src, auditUuid)
        return Nyx.Treasury.GetSubpoenaAuditReport(auditUuid)
    end)

    exports['nyx_core']:RegisterRPC("treasury:freezeCommercialTarget", function(src, payload)
        if type(payload) ~= "table" then return false, "INVALID_PAYLOAD" end
        return Nyx.Treasury.FreezeCommercialTarget(src, payload.warrantId, payload.targetType, payload.targetId, payload.reason)
    end)
end)
