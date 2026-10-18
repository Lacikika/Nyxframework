--[[
    Nyxframework: nyx_inventory
    File: shared/serial_grind.lua
    Description: Pure Lua 5.4 domain logic for illicit firearm serial number grinding,
                 abrasive tool profiles, weapon durability wear, forensic contamination,
                 and serial number obfuscation contracts.
]]

Nyx = Nyx or {}
Nyx.SerialGrind = Nyx.SerialGrind or {}

-- 1. Declarative Grinding Tool Profiles
Nyx.SerialGrind.Tools = {
    ['tool_angle_grinder'] = {
        name = 'tool_angle_grinder',
        label = 'High-Speed Cordless Angle Grinder',
        durationMs = 8000,
        durabilityWear = 6.0,
        requiresDisk = true,
        diskItem = 'grinding_disk',
        noiseRadius = 32.0,
        lacerationRisk = 0.14,
        lacerationDamage = 12,
        fingerprintRisk = 0.90,
        baseGrindQuality = 85
    }
}

-- 2. Pure Validation Helper: Can Weapon Be Grinded
function Nyx.SerialGrind.CanGrindWeapon(weaponItem, toolItem, diskItem)
    if not weaponItem or type(weaponItem) ~= 'table' then
        return false, "INVALID_WEAPON"
    end

    local itemDef = Nyx.Items and Nyx.Items.Get(weaponItem.item_id)
    if not itemDef or itemDef.type ~= 'weapon' then
        return false, "ITEM_NOT_A_WEAPON"
    end

    local meta = weaponItem.metadata or {}
    if meta.scratched == true then
        return false, "SERIAL_ALREADY_SCRATCHED"
    end

    if not toolItem or type(toolItem) ~= 'table' then
        return false, "MISSING_GRINDING_TOOL"
    end

    local toolProfile = Nyx.SerialGrind.Tools[toolItem.item_id]
    if not toolProfile then
        return false, "INVALID_TOOL_PROFILE"
    end

    local toolDur = (toolItem.metadata and tonumber(toolItem.metadata.durability)) or 100.0
    if toolDur < toolProfile.durabilityWear then
        return false, "TOOL_DURABILITY_DEPLETED"
    end

    if toolProfile.requiresDisk then
        if not diskItem or type(diskItem) ~= 'table' or diskItem.item_id ~= toolProfile.diskItem or (tonumber(diskItem.amount) or 0) < 1 then
            return false, "MISSING_GRINDING_DISK"
        end
    end

    return true
end

-- 3. Pure Mathematical Evaluator for Grinding Outcome
function Nyx.SerialGrind.CalculateGrindOutcome(weaponItem, toolItem, options)
    options = options or {}
    local toolProfile = Nyx.SerialGrind.Tools[toolItem and toolItem.item_id] or Nyx.SerialGrind.Tools['tool_angle_grinder']
    local meta = (weaponItem and weaponItem.metadata) or {}

    local seed = tonumber(options.seed) or os.time()
    local rng = function(min, max)
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        local ratio = (seed % 10000) / 10000.0
        return min + (max - min) * ratio
    end

    local currentDur = tonumber(meta.durability) or 100.0
    local wearCost = math.floor(rng(6.0, 12.0) * 10) / 10.0
    local remainingWeaponDur = math.max(0.0, currentDur - wearCost)

    -- Quality of the grind (higher means deeper/rougher, making acid-etch restoration more difficult)
    local qualityVariance = math.floor(rng(-10.0, 15.0))
    local grindQuality = math.min(100, math.max(40, toolProfile.baseGrindQuality + qualityVariance))

    -- Tool wear calculation
    local toolDur = (toolItem and toolItem.metadata and tonumber(toolItem.metadata.durability)) or 100.0
    local remainingToolDur = math.max(0.0, toolDur - toolProfile.durabilityWear)
    local isToolBroken = remainingToolDur <= 0.0

    -- Forensic contamination logic
    local hasGloves = options.hasGloves == true
    local fpRoll = rng(0.0, 1.0)
    local dnaRoll = rng(0.0, 1.0)

    local fingerprintLeft = false
    local dnaLeft = false
    local lacerationDmg = 0

    if not hasGloves then
        if fpRoll < toolProfile.fingerprintRisk then
            fingerprintLeft = true
        end
        if dnaRoll < toolProfile.lacerationRisk then
            dnaLeft = true
            lacerationDmg = toolProfile.lacerationDamage
        end
    end

    local originalSerial = tostring(meta.serialNumber or string.format("NYX-%06d", math.random(100000, 999999)))
    local toolSerial = (toolItem and toolItem.metadata and toolItem.metadata.toolSerial) or "GRD-UNKNOWN"
    local toolmarkStriations = (toolItem and toolItem.metadata and toolItem.metadata.striations) or "STR-GRD-DEFAULT"

    return {
        success = true,
        originalSerial = originalSerial,
        scratchedSerial = "[GROUND OFF]",
        grindQuality = grindQuality,
        weaponDurabilityLoss = wearCost,
        remainingWeaponDurability = remainingWeaponDur,
        toolWear = toolProfile.durabilityWear,
        remainingToolDurability = remainingToolDur,
        isToolBroken = isToolBroken,
        consumedDisk = toolProfile.requiresDisk,
        noiseRadius = toolProfile.noiseRadius,
        hasGloves = hasGloves,
        fingerprintLeft = fingerprintLeft,
        dnaLeft = dnaLeft,
        lacerationDamage = lacerationDmg,
        toolSerial = toolSerial,
        toolmarkStriations = toolmarkStriations
    }
end

-- 4. Serial Display Formatter (UI & Third-Eye Presentation)
function Nyx.SerialGrind.FormatSerialDisplay(metadata)
    if not metadata or type(metadata) ~= 'table' then
        return "UNKNOWN"
    end

    if metadata.scratched == true then
        if metadata.acidEtched == true then
            return string.format("[KÉMIAILAG ELŐHÍVVA: %s]", tostring(metadata.restoredSerial or "???"))
        else
            return "[SZÁM LECSISZOLVA / GROUND OFF]"
        end
    end

    return tostring(metadata.serialNumber or "NYX-UNKNOWN")
end

-- 5. Zero-Trust Payload Validator
function Nyx.SerialGrind.ValidatePayload(payload)
    if not payload or type(payload) ~= 'table' then
        return false, "PAYLOAD_MUST_BE_TABLE"
    end

    local weaponSlot = tonumber(payload.weaponSlot)
    if not weaponSlot or weaponSlot < 1 then
        return false, "INVALID_WEAPON_SLOT"
    end

    local toolSlot = tonumber(payload.toolSlot)
    if not toolSlot or toolSlot < 1 then
        return false, "INVALID_TOOL_SLOT"
    end

    if payload.diskSlot ~= nil then
        local diskSlot = tonumber(payload.diskSlot)
        if not diskSlot or diskSlot < 1 then
            return false, "INVALID_DISK_SLOT"
        end
    end

    return true
end
