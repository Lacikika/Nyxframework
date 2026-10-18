--[[
    Nyxframework: nyx_services & nyx_properties
    File: shared/sabotage.lua
    Description: Pure Lua 5.4 domain logic for substation physical sabotage,
                 transformer arc hazards, localized blackout sectors,
                 commercial warehouse lock failures, and alarm breach mechanics.
]]

Nyx = Nyx or {}
Nyx.Sabotage = Nyx.Sabotage or {}

-- 1. Declarative Tool Profiles for Substation Transformer Sabotage
Nyx.Sabotage.ToolProfiles = {
    ['wire_cutters'] = {
        name = 'wire_cutters',
        label = 'Insulated Wire Cutters',
        baseSuccessRate = 0.75,
        shockChance = 0.15,
        shockDamage = 25,
        durabilityLoss = 20.0,
        alarmTripChance = 0.35,
        cooldownSeconds = 600,
        actionDurationMs = 10000,
        noiseRadius = 25.0,
        consumedOnUse = false
    },
    ['thermite_charge'] = {
        name = 'thermite_charge',
        label = 'Thermite Incendiary Charge',
        baseSuccessRate = 0.95,
        shockChance = 0.05,
        shockDamage = 35,
        durabilityLoss = 0.0,
        alarmTripChance = 0.90,
        cooldownSeconds = 600,
        actionDurationMs = 6000,
        noiseRadius = 75.0,
        consumedOnUse = true
    },
    ['tool_repairkit'] = {
        name = 'tool_repairkit',
        label = 'Mechanical Toolkit (Tampering)',
        baseSuccessRate = 0.50,
        shockChance = 0.35,
        shockDamage = 40,
        durabilityLoss = 30.0,
        alarmTripChance = 0.65,
        cooldownSeconds = 600,
        actionDurationMs = 14000,
        noiseRadius = 35.0,
        consumedOnUse = false
    }
}

--- Lookup a sabotage tool profile
function Nyx.Sabotage.GetToolProfile(toolName)
    if not toolName or type(toolName) ~= "string" then return nil end
    return Nyx.Sabotage.ToolProfiles[toolName]
end

--- Calculate the physical outcome of a substation sabotage attempt.
--- Pure Lua 5.4 function with deterministic overrides for unit testing.
function Nyx.Sabotage.CalculateSabotageOutcome(toolName, options)
    options = options or {}
    local profile = Nyx.Sabotage.GetToolProfile(toolName)
    if not profile then
        return false, "UNSUPPORTED_SABOTAGE_TOOL"
    end

    local successRate = profile.baseSuccessRate
    if options.isElectrician then
        successRate = math.min(0.99, successRate + 0.15)
    end

    local shockChance = profile.shockChance
    local shockDamage = profile.shockDamage
    if options.hasRubberGloves then
        -- High-voltage rubber gloves protect against direct electrocution
        shockChance = 0.00
        shockDamage = 0
    end

    local alarmChance = profile.alarmTripChance
    if options.isElectrician then
        alarmChance = math.max(0.10, alarmChance - 0.20)
    end

    -- Deterministic test injection or math.random roll
    local rSuccess = options.rollSuccess or math.random()
    local rShock = options.rollShock or math.random()
    local rAlarm = options.rollAlarm or math.random()

    local isSuccess = (options.forceSuccess == true) or (rSuccess <= successRate)
    local isShock = (shockChance > 0) and (rShock <= shockChance)
    local isAlarm = (rAlarm <= alarmChance)

    local durabilityDeduction = profile.durabilityLoss or 0.0
    local isConsumed = profile.consumedOnUse or false

    return true, {
        tool = toolName,
        success = isSuccess,
        shockInflicted = isShock,
        shockDamage = isShock and shockDamage or 0,
        alarmTriggered = isAlarm,
        durabilityLoss = durabilityDeduction,
        consumed = isConsumed,
        noiseRadius = profile.noiseRadius,
        cooldownSeconds = profile.cooldownSeconds
    }
end

--- Authoritative evaluation of a property's electronic doorlock during grid outages.
--- Commercial and Industrial properties utilize fail-safe magnetic locks (maglocks)
--- that release and fail-open when electrical power is severed.
--- Residential properties utilize mechanical lock cylinders that remain physically engaged.
--- Properties equipped with backup generators retain lock state regardless of grid power.
function Nyx.Sabotage.EvaluateDoorlockState(propertyType, isLocked, isPowered, hasBackupGen)
    isLocked = (isLocked == true or isLocked == 1)
    isPowered = (isPowered == true or isPowered == 1 or isPowered == nil)
    hasBackupGen = (hasBackupGen == true or hasBackupGen == 1)
    propertyType = propertyType or 'residential'

    if isPowered then
        return isLocked, "ONLINE", false
    end

    -- Power is offline
    if hasBackupGen then
        return isLocked, "BACKUP_POWER", false
    end

    -- Commercial and industrial fail-safe magnetic locks release on complete loss of power
    if propertyType == 'commercial' or propertyType == 'industrial' then
        return false, "BLACKOUT_BREACHED", true
    end

    -- Residential properties rely on physical deadbolts
    return isLocked, "MECHANICAL_LOCKED", false
end

--- Authoritative evaluation of a commercial logistics warehouse magnetic lock.
--- Warehouses without auxiliary generators unlock during sector blackouts.
function Nyx.Sabotage.EvaluateWarehouseLockState(isLocked, isPowered, hasBackupGen)
    return Nyx.Sabotage.EvaluateDoorlockState('industrial', isLocked, isPowered, hasBackupGen)
end

--- Evaluate electronic security alarm status and police dispatch trigger eligibility.
--- When electrical power is severed and backup generator is absent:
--- Local sirens and primary security transmitters fail offline, disabling automated audible alarms.
function Nyx.Sabotage.EvaluateAlarmStatus(hasAlarm, isPowered, hasBackupGen, isDoorBreached)
    hasAlarm = (hasAlarm == true or hasAlarm == 1 or hasAlarm == nil)
    isPowered = (isPowered == true or isPowered == 1 or isPowered == nil)
    hasBackupGen = (hasBackupGen == true or hasBackupGen == 1)
    isDoorBreached = (isDoorBreached == true)

    if not hasAlarm then
        return "none", false
    end

    if isPowered then
        if isDoorBreached then
            return "tripped", true
        end
        return "armed", false
    end

    -- Grid power is offline
    if hasBackupGen then
        if isDoorBreached then
            return "tripped_backup", true
        end
        return "armed_backup", false
    end

    -- No power and no generator: security alarm system is dead / silenced
    if isDoorBreached then
        return "offline_breached", false
    end
    return "offline", false
end

--- Zero-trust validator for substation sabotage payloads.
function Nyx.Sabotage.ValidateSabotagePayload(payload)
    if type(payload) ~= "table" then
        return false, "INVALID_PAYLOAD_STRUCTURE"
    end

    local subId = payload.substationId
    if not subId or type(subId) ~= "string" or #subId < 3 or #subId > 64 then
        return false, "INVALID_SUBSTATION_ID"
    end

    local tool = payload.tool
    if not tool or type(tool) ~= "string" or not Nyx.Sabotage.ToolProfiles[tool] then
        return false, "INVALID_SABOTAGE_TOOL"
    end

    return true, nil
end

--- Format doorlock state badge for UI / HUD
function Nyx.Sabotage.FormatLockStateBadge(status)
    if status == "ONLINE" then
        return { text = "MÁGNESZÁR AKTÍV", color = "green", icon = "fa-shield-halved" }
    elseif status == "BACKUP_POWER" then
        return { text = "TARTALÉK ÁRAM", color = "blue", icon = "fa-battery-half" }
    elseif status == "BLACKOUT_BREACHED" then
        return { text = "ÁRAMKIMARADÁS - NYITVA", color = "red", icon = "fa-lock-open" }
    elseif status == "MECHANICAL_LOCKED" then
        return { text = "MECHANIKUS ZÁR", color = "yellow", icon = "fa-key" }
    end
    return { text = "ISMERETLEN", color = "gray", icon = "fa-question" }
end

--- Format security alarm badge for UI / HUD
function Nyx.Sabotage.FormatAlarmBadge(status)
    if status == "armed" or status == "armed_backup" then
        return { text = "ÉLESÍTVE", color = "green", icon = "fa-bell" }
    elseif status == "tripped" or status == "tripped_backup" then
        return { text = "RIASZTÁS!", color = "red", icon = "fa-triangle-exclamation" }
    elseif status == "offline" or status == "offline_breached" then
        return { text = "NINCS ÁRAM", color = "darkred", icon = "fa-bell-slash" }
    end
    return { text = "NINCS", color = "gray", icon = "fa-shield" }
end

--- Format sabotage state badge
function Nyx.Sabotage.FormatSabotageBadge(isSabotaged, cooldownSec)
    if isSabotaged then
        return { text = "SZABOTÁLT TRANSZFORMÁTOR", color = "red", icon = "fa-bolt-lightning" }
    elseif cooldownSec and cooldownSec > 0 then
        return { text = string.format("VÉDELMI ZÁRLAT (%ds)", math.floor(cooldownSec)), color = "yellow", icon = "fa-clock" }
    end
    return { text = "ÜZEMKÉSZ", color = "green", icon = "fa-check" }
end
