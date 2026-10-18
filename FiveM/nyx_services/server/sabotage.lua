--[[
    Nyxframework: nyx_services
    File: server/sabotage.lua
    Description: Authoritative physical substation sabotage subsystem,
                 transformer arc flashes, police dispatch alerts,
                 cooldown enforcement, and immutable incident auditing.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}

-- Standardized Bridge to nyx_core
Nyx.GetPlayer = Nyx.GetPlayer or function(src)
    if exports['nyx_core'] and exports['nyx_core'].GetPlayer then
        return exports['nyx_core']:GetPlayer(src)
    end
    return nil
end

--- Generate standard random UUID
local function generateUuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

--- Authoritative Substation Sabotage Handler
function Nyx.Services.SabotageSubstation(src, substationId, toolName)
    local player = Nyx.GetPlayer(src)
    if not player then
        return false, "UNAUTHENTICATED"
    end

    local valid, valErr = Nyx.Sabotage.ValidateSabotagePayload({
        substationId = substationId,
        tool = toolName
    })
    if not valid then
        return false, valErr
    end

    local s = Nyx.Services.Substations[substationId]
    if not s then
        return false, "SUBSTATION_NOT_FOUND"
    end

    -- 1. Proximity Verification (Zero-Trust Server Check)
    local ped = GetPlayerPed(tostring(src))
    local pCoords = GetEntityCoords(ped)
    local targetVec = s.transformerCoords or s.coords
    local dist = #(pCoords - targetVec)
    if dist > 6.0 then
        return false, "TOO_FAR_FROM_TRANSFORMER"
    end

    -- 2. State & Cooldown Check
    if s.isSabotaged then
        return false, "SUBSTATION_ALREADY_SABOTAGED"
    end

    local now = os.time()
    if s.sabotageCooldownUntil and type(s.sabotageCooldownUntil) == "number" and now < s.sabotageCooldownUntil then
        return false, "SABOTAGE_COOLDOWN_ACTIVE"
    end

    -- 3. Inventory Tool Verification
    local invId = "citizen:" .. player.citizenId
    local hasTool = false
    if exports['nyx_inventory'] and exports['nyx_inventory'].HasItem then
        hasTool = exports['nyx_inventory']:HasItem(invId, toolName, 1)
    else
        hasTool = true
    end

    if not hasTool then
        return false, "MISSING_SABOTAGE_TOOL"
    end

    -- 4. Check Protective Rubber/Nitrile Gloves
    local hasGloves = false
    if exports['nyx_inventory'] and exports['nyx_inventory'].HasItem then
        hasGloves = exports['nyx_inventory']:HasItem(invId, "nitrile_gloves", 1) or
                    exports['nyx_inventory']:HasItem(invId, "latex_gloves", 1)
    end

    -- 5. Calculate Physical Sabotage Outcome
    local ok, outcome = Nyx.Sabotage.CalculateSabotageOutcome(toolName, {
        hasRubberGloves = hasGloves
    })
    if not ok then
        return false, outcome
    end

    -- 6. Deduct or Wear Down Tool
    if outcome.consumed then
        if exports['nyx_inventory'] and exports['nyx_inventory'].RemoveItem then
            exports['nyx_inventory']:RemoveItem(invId, toolName, 1)
        end
    end

    -- 7. High-Voltage Shock Injury Execution
    if outcome.shockInflicted and outcome.shockDamage > 0 then
        if exports['nyx_services'] and exports['nyx_services'].AddLimbDamage then
            pcall(exports['nyx_services'].AddLimbDamage, exports['nyx_services'], src, "right_arm", "burn", outcome.shockDamage)
        end
        local currentHealth = GetEntityHealth(ped)
        if currentHealth > 100 then
            SetEntityHealth(ped, math.max(105, currentHealth - outcome.shockDamage))
        end
    end

    -- 8. Electronic Alarm Trip & Police Dispatch Notification
    if outcome.alarmTriggered then
        if exports['nyx_mdt'] and exports['nyx_mdt'].CreateCall then
            exports['nyx_mdt']:CreateCall(
                "10-90",
                "Hálózati Transzformátor Szabotázs",
                string.format("Kiemelt prioritású hálózati riasztás: Fizikai behatolás és transzformátor zárlat észlelve! (%s)", s.label),
                "Automata Hálózati Figyelőrendszer",
                { x = targetVec.x, y = targetVec.y, z = targetVec.z },
                s.connectedDistricts or s.label,
                "high"
            )
        end
    end

    -- 9. Successful Sabotage State Application
    local sabotageUuid = generateUuid()
    if outcome.success then
        s.isSabotaged = true
        s.breakerTripped = true
        s.failureReason = "sabotage"
        s.conditionHealth = math.max(0.00, s.conditionHealth - 45.00)
        s.lastSabotagedAt = now
        s.sabotageCooldownUntil = now + (outcome.cooldownSeconds or 600)

        -- Evaluate state and trigger blackout cascade across sector
        if Nyx.Services.EvaluateSubstationState then
            Nyx.Services.EvaluateSubstationState(s, true)
        end

        -- Persist to database
        MySQL.prepare.await([[
            UPDATE `nyx_services_substations`
            SET `is_sabotaged` = 1,
                `last_sabotaged_at` = CURRENT_TIMESTAMP,
                `sabotage_cooldown_until` = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND),
                `condition_health` = ?,
                `breaker_tripped` = 1,
                `is_blackout` = 1,
                `failure_reason` = 'sabotage'
            WHERE `substation_id` = ?
        ]], { outcome.cooldownSeconds or 600, s.conditionHealth, substationId })

        -- Broadcast audiovisual shockwave and sparks to clients
        TriggerClientEvent("nyx:services:client:transformerSabotaged", -1, {
            substationId = substationId,
            coords = { x = targetVec.x, y = targetVec.y, z = targetVec.z },
            label = s.label
        })

        if Config.Debug then
            print(string.format("^1[Nyx:Services] SUBSTATION SABOTAGED: '%s' by citizen '%s' using '%s'!^7",
                substationId, player.citizenId, toolName))
        end
    end

    -- 10. Commit Immutable Sabotage Audit Log
    MySQL.prepare.await([[
        INSERT INTO `nyx_services_substation_sabotage_logs`
            (`sabotage_uuid`, `substation_id`, `saboteur_citizen_id`, `tool_used`, `success`,
             `alarm_triggered`, `shock_injury_inflicted`, `police_alerted`, `coords`, `notes`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        sabotageUuid,
        substationId,
        player.citizenId,
        toolName,
        outcome.success and 1 or 0,
        outcome.alarmTriggered and 1 or 0,
        outcome.shockInflicted and 1 or 0,
        outcome.alarmTriggered and 1 or 0,
        json.encode({ x = targetVec.x, y = targetVec.y, z = targetVec.z }),
        outcome.success and "Transformer severed & breached" or "Failed sabotage attempt"
    })

    return true, {
        success = outcome.success,
        shockInflicted = outcome.shockInflicted,
        shockDamage = outcome.shockDamage,
        alarmTriggered = outcome.alarmTriggered,
        substationId = substationId,
        isBlackout = s.isBlackout,
        conditionHealth = s.conditionHealth,
        sabotageUuid = sabotageUuid
    }
end

--- Query Substation Sabotage Details
function Nyx.Services.GetSabotageStatus(substationId)
    local s = Nyx.Services.Substations[substationId]
    if not s then return nil end

    local now = os.time()
    local remCooldown = 0
    if s.sabotageCooldownUntil and type(s.sabotageCooldownUntil) == "number" and now < s.sabotageCooldownUntil then
        remCooldown = s.sabotageCooldownUntil - now
    end

    return {
        substationId = s.id,
        label = s.label,
        isSabotaged = s.isSabotaged or false,
        isBlackout = s.isBlackout or false,
        breakerTripped = s.breakerTripped or false,
        failureReason = s.failureReason,
        conditionHealth = s.conditionHealth,
        cooldownRemainingSeconds = remCooldown,
        transformerCoords = { x = s.transformerCoords.x, y = s.transformerCoords.y, z = s.transformerCoords.z }
    }
end

--- Query Recent Sabotage Logs for Substation or All
function Nyx.Services.GetSabotageLogs(substationId, limit)
    limit = tonumber(limit) or 10
    local rows = nil
    if substationId then
        rows = MySQL.query.await([[
            SELECT * FROM `nyx_services_substation_sabotage_logs`
            WHERE `substation_id` = ?
            ORDER BY `created_at` DESC LIMIT ?
        ]], { substationId, limit })
    else
        rows = MySQL.query.await([[
            SELECT * FROM `nyx_services_substation_sabotage_logs`
            ORDER BY `created_at` DESC LIMIT ?
        ]], { limit })
    end
    return rows or {}
end

-- ============================================================================
-- RPC Registration
-- ============================================================================

if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
    exports['nyx_core']:RegisterRPC("services:sabotageSubstation", function(src, payload)
        local player = Nyx.GetPlayer(src)
        if not player then return { success = false, error = "UNAUTHORIZED" } end

        if type(payload) ~= "table" then
            return { success = false, error = "INVALID_PAYLOAD" }
        end

        local ok, res = Nyx.Services.SabotageSubstation(src, payload.substationId, payload.tool)
        if not ok then
            return { success = false, error = res }
        end

        return { success = true, result = res }
    end)

    exports['nyx_core']:RegisterRPC("services:getSabotageStatus", function(src, substationId)
        local status = Nyx.Services.GetSabotageStatus(substationId)
        if not status then
            return { success = false, error = "SUBSTATION_NOT_FOUND" }
        end
        return { success = true, status = status }
    end)

    exports['nyx_core']:RegisterRPC("services:getSabotageLogs", function(src, substationId)
        local logs = Nyx.Services.GetSabotageLogs(substationId, 20)
        return { success = true, logs = logs }
    end)
end
