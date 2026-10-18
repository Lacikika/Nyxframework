--[[
    Nyxframework: nyx_judiciary
    File: server/warrants.lua
    Description: Authoritative judicial warrant engine (arrest, search) with MDT broadcast
                 and automated expiration management.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}

-- 1. Issue a judicial warrant
function Nyx.Judiciary.IssueWarrant(issuingJudgeCitId, targetCitId, warrantType, causeSummary, targetEntityId, durationHours)
    if not targetCitId or not warrantType or not causeSummary then
        return false, "MISSING_REQUIRED_FIELDS"
    end

    if not Config.Warrants.AllowedTypes[warrantType] then
        return false, "INVALID_WARRANT_TYPE"
    end

    local hours = tonumber(durationHours) or Config.Warrants.DefaultExpirationHours or 72
    local maxHours = Config.Warrants.MaxExpirationHours or 336
    if hours > maxHours then hours = maxHours end

    local expireTime = os.date("%Y-%m-%d %H:%M:%S", os.time() + (hours * 3600))

    local warrantId = MySQL.insert.await([[
        INSERT INTO `nyx_judiciary_warrants`
            (`target_citizen_id`, `issuing_judge_id`, `type`, `target_entity_id`, `probable_cause_summary`, `status`, `expires_at`)
        VALUES (?, ?, ?, ?, ?, 'active', ?)
    ]], {
        targetCitId,
        issuingJudgeCitId,
        warrantType,
        targetEntityId or nil,
        causeSummary,
        expireTime
    })

    if not warrantId or warrantId == 0 then
        return false, "DATABASE_ERROR"
    end

    local warrantPayload = {
        warrantId = warrantId,
        targetCitizenId = targetCitId,
        issuingJudgeId = issuingJudgeCitId,
        type = warrantType,
        targetEntityId = targetEntityId,
        probableCauseSummary = causeSummary,
        status = "active",
        expiresAt = expireTime
    }

    -- Broadcast to Police & DOJ Mobile Data Terminals (MDT)
    TriggerClientEvent("nyx:judiciary:client:warrantIssued", -1, warrantPayload)

    if Config.Debug then
        print(string.format("^2[Nyx:Judiciary]^7 Warrant #%d issued for %s (%s, Expires: %s)^7", warrantId, targetCitId, warrantType, expireTime))
    end

    return true, warrantPayload
end

-- 2. Rescind an active warrant
function Nyx.Judiciary.RescindWarrant(warrantId, judgeCitId, reason)
    local affected = MySQL.update.await([[
        UPDATE `nyx_judiciary_warrants`
        SET `status` = 'rescinded'
        WHERE `warrant_id` = ? AND `status` = 'active'
    ]], { warrantId })

    if affected and affected > 0 then
        TriggerClientEvent("nyx:judiciary:client:warrantUpdated", -1, {
            warrantId = warrantId,
            status = "rescinded",
            rescindedBy = judgeCitId,
            reason = reason
        })
        return true
    end

    return false, "WARRANT_NOT_ACTIVE"
end

-- 3. Execute / fulfill a warrant upon arrest or search
function Nyx.Judiciary.ExecuteWarrant(warrantId, officerCitId)
    local affected = MySQL.update.await([[
        UPDATE `nyx_judiciary_warrants`
        SET `status` = 'executed'
        WHERE `warrant_id` = ? AND `status` = 'active'
    ]], { warrantId })

    if affected and affected > 0 then
        TriggerClientEvent("nyx:judiciary:client:warrantUpdated", -1, {
            warrantId = warrantId,
            status = "executed",
            executedBy = officerCitId
        })
        return true
    end

    return false, "WARRANT_NOT_ACTIVE"
end

-- 4. Query active warrants for a target citizen or overall
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

-- 5. Periodic sweep to transition timed-out warrants to expired
function Nyx.Judiciary.SweepExpiredWarrants()
    local affected = MySQL.update.await([[
        UPDATE `nyx_judiciary_warrants`
        SET `status` = 'expired'
        WHERE `status` = 'active' AND `expires_at` <= CURRENT_TIMESTAMP
    ]])

    if affected and affected > 0 and Config.Debug then
        print(string.format("^3[Nyx:Judiciary]^7 Swept %d expired judicial warrants^7", affected))
    end
end
