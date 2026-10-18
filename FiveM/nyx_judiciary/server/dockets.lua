--[[
    Nyxframework: nyx_judiciary
    File: server/dockets.lua
    Description: Formal court docket management, case filing lifecycle, and evidence linkage.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}

-- Generate standard docket identifier (DOC-YYYY-XXXX)
local function generateDocketId()
    local year = os.date("%Y")
    local randNum = math.random(1000, 9999)
    return string.format("DOC-%s-%04d", year, randNum)
end

-- Allowed case classifications
local VALID_CASE_TYPES = {
    ['civil'] = true,
    ['criminal_misdemeanor'] = true,
    ['criminal_felony'] = true,
    ['constitutional'] = true
}

-- 1. File a new court docket
function Nyx.Judiciary.CreateDocket(plaintiffCitId, defendantCitId, title, caseType, brief, presidingJudgeId)
    if not plaintiffCitId or not defendantCitId or not title then
        return false, "MISSING_REQUIRED_FIELDS"
    end

    if not VALID_CASE_TYPES[caseType] then
        return false, "INVALID_CASE_TYPE"
    end

    local docketId = generateDocketId()

    local success = MySQL.prepare.await([[
        INSERT INTO `nyx_judiciary_dockets`
            (`docket_id`, `title`, `plaintiff_citizen_id`, `defendant_citizen_id`, `presiding_judge_id`, `case_type`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, 'filed')
    ]], {
        docketId,
        title,
        plaintiffCitId,
        defendantCitId,
        presidingJudgeId or nil,
        caseType
    })

    if not success then
        return false, "DATABASE_ERROR"
    end

    if Config.Debug then
        print(string.format("^2[Nyx:Judiciary]^7 Created docket %s: %s (Type: %s)^7", docketId, title, caseType))
    end

    return true, docketId
end

-- 2. Link collected evidence item to a docket
function Nyx.Judiciary.LinkEvidence(docketId, evidenceId, authorizedCitId)
    if not docketId or not evidenceId then
        return false, "INVALID_INPUT"
    end

    local docket = MySQL.single.await("SELECT `status` FROM `nyx_judiciary_dockets` WHERE `docket_id` = ?", { docketId })
    if not docket then
        return false, "DOCKET_NOT_FOUND"
    end

    if docket.status == 'concluded' or docket.status == 'dismissed' then
        return false, "DOCKET_ALREADY_CLOSED"
    end

    local evidence = MySQL.single.await("SELECT `evidence_id`, `is_contaminated` FROM `nyx_judiciary_evidence` WHERE `evidence_id` = ?", { evidenceId })
    if not evidence then
        return false, "EVIDENCE_NOT_FOUND"
    end

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_evidence`
        SET `docket_id` = ?
        WHERE `evidence_id` = ?
    ]], { docketId, evidenceId })

    return true, {
        docketId = docketId,
        evidenceId = evidenceId,
        isContaminated = (tonumber(evidence.is_contaminated) == 1)
    }
end

-- 3. Schedule Docket for Trial & Trigger Jury Summons
function Nyx.Judiciary.ScheduleDocket(docketId, scheduledTimestamp, presidingJudgeId)
    local docket = MySQL.single.await([[
        SELECT `docket_id`, `case_type`, `status` FROM `nyx_judiciary_dockets` WHERE `docket_id` = ?
    ]], { docketId })

    if not docket then
        return false, "DOCKET_NOT_FOUND"
    end

    local targetTime = scheduledTimestamp and os.date("%Y-%m-%d %H:%M:%S", scheduledTimestamp) or os.date("%Y-%m-%d %H:%M:%S", os.time() + 1800)

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_dockets`
        SET `status` = 'scheduled',
            `scheduled_for` = ?,
            `presiding_judge_id` = ?
        WHERE `docket_id` = ?
    ]], { targetTime, presidingJudgeId or nil, docketId })

    -- For felony criminal cases, automatically initiate the civic jury selection pipeline
    if docket.case_type == 'criminal_felony' then
        local juryOk, juryRes = Nyx.Judiciary.SummonJury(docketId, Config.Jury.DefaultRequiredCount or 5)
        if not juryOk then
            print(string.format("^3[Nyx:Judiciary]^7 Notice: Docket %s scheduled, but jury summons returned: %s^7", docketId, tostring(juryRes)))
        end
    end

    return true, { docketId = docketId, scheduledFor = targetTime }
end

-- 4. Transition status of a docket
function Nyx.Judiciary.SetDocketStatus(docketId, newStatus)
    local allowed = {
        ['filed'] = true,
        ['scheduled'] = true,
        ['deliberation'] = true,
        ['concluded'] = true,
        ['dismissed'] = true
    }
    if not allowed[newStatus] then
        return false, "INVALID_STATUS"
    end

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_dockets`
        SET `status` = ?
        WHERE `docket_id` = ?
    ]], { newStatus, docketId })

    return true
end

-- 5. Query complete docket with evidence and jury lists
function Nyx.Judiciary.GetDocket(docketId)
    local docket = MySQL.single.await([[
        SELECT * FROM `nyx_judiciary_dockets` WHERE `docket_id` = ?
    ]], { docketId })

    if not docket then return nil end

    local evidence = MySQL.query.await([[
        SELECT `evidence_id`, `type`, `evidence_hash`, `collector_citizen_id`,
               `is_contaminated`, `contamination_source`, `metadata`, `created_at`
        FROM `nyx_judiciary_evidence`
        WHERE `docket_id` = ?
    ]], { docketId })

    local jurors = MySQL.query.await([[
        SELECT `jury_id`, `citizen_id`, `selection_status`, `assigned_at`
        FROM `nyx_judiciary_juries`
        WHERE `docket_id` = ?
    ]], { docketId })

    return {
        docket = docket,
        evidence = evidence or {},
        jurors = jurors or {}
    }
end

-- 6. Query all active or scheduled dockets
function Nyx.Judiciary.GetActiveDockets()
    local dockets = MySQL.query.await([[
        SELECT * FROM `nyx_judiciary_dockets`
        WHERE `status` IN ('filed', 'scheduled', 'deliberation')
        ORDER BY `created_at` DESC
    ]])
    return dockets or {}
end
