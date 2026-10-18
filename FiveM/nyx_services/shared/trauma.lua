--[[
    Nyxframework: nyx_services
    File: shared/trauma.lua
    Description: Deterministic pure Lua 5.4 anatomical trauma engine, bone-to-limb mapping,
                 hemodynamic blood volume simulation, shock classification, and field stabilization.
]]

Nyx = Nyx or {}
Nyx.Trauma = Nyx.Trauma or {}

-- 1. Anatomical Definitions & Whitelists
Nyx.Trauma.ValidLimbs = {
    ['head'] = true,
    ['torso'] = true,
    ['left_arm'] = true,
    ['right_arm'] = true,
    ['left_leg'] = true,
    ['right_leg'] = true
}

Nyx.Trauma.ExtremityLimbs = {
    ['left_arm'] = true,
    ['right_arm'] = true,
    ['left_leg'] = true,
    ['right_leg'] = true
}

Nyx.Trauma.LimbLabels = {
    ['head'] = "Koponya és Nyak",
    ['torso'] = "Mellkas és Törzs",
    ['left_arm'] = "Bal Kar",
    ['right_arm'] = "Jobb Kar",
    ['left_leg'] = "Bal Láb",
    ['right_leg'] = "Jobb Láb"
}

Nyx.Trauma.WoundTypes = {
    ['laceration'] = true,
    ['ballistic'] = true,
    ['arterial_bleed'] = true,
    ['fracture'] = true,
    ['blunt'] = true,
    ['burn'] = true
}

Nyx.Trauma.BaseBleedRates = {
    ['laceration'] = 1.50,       -- mL/s
    ['ballistic'] = 6.00,        -- mL/s
    ['arterial_bleed'] = 25.00,  -- mL/s
    ['blunt'] = 0.50,            -- mL/s
    ['burn'] = 1.00,             -- mL/s
    ['fracture'] = 0.00          -- mL/s
}

-- 2. GTA Ped Bone ID to Anatomical Limb Mapping
Nyx.Trauma.BoneToLimbMap = {
    -- Head / Neck
    [31086] = "head",      -- SKEL_Head
    [39317] = "head",      -- SKEL_Neck_1

    -- Torso / Spine / Pelvis
    [24818] = "torso",     -- SKEL_Spine3
    [24817] = "torso",     -- SKEL_Spine2
    [24816] = "torso",     -- SKEL_Spine1
    [11816] = "torso",     -- SKEL_Pelvis

    -- Left Arm
    [18905] = "left_arm",  -- SKEL_L_Hand
    [22711] = "left_arm",  -- SKEL_L_Forearm
    [45509] = "left_arm",  -- SKEL_L_UpperArm
    [64729] = "left_arm",  -- SKEL_L_Clavicle

    -- Right Arm
    [57005] = "right_arm", -- SKEL_R_Hand
    [2992] = "right_arm",  -- SKEL_R_Forearm
    [40269] = "right_arm", -- SKEL_R_UpperArm
    [10706] = "right_arm", -- SKEL_R_Clavicle

    -- Left Leg
    [63931] = "left_leg",  -- SKEL_L_Calf
    [58271] = "left_leg",  -- SKEL_L_Thigh
    [14201] = "left_leg",  -- SKEL_L_Foot

    -- Right Leg
    [36864] = "right_leg", -- SKEL_R_Calf
    [51826] = "right_leg", -- SKEL_R_Thigh
    [52335] = "right_leg"  -- SKEL_R_Foot
}

function Nyx.Trauma.GetLimbFromBone(boneId)
    local b = tonumber(boneId)
    if b and Nyx.Trauma.BoneToLimbMap[b] then
        return Nyx.Trauma.BoneToLimbMap[b]
    end
    return "torso"
end

-- 3. Initial State Factory
function Nyx.Trauma.CreateDefaultLimbState()
    return {
        health = 100,
        wounds = {},
        isBleeding = false,
        isFractured = false,
        hasTourniquet = false
    }
end

function Nyx.Trauma.CreateInitialTraumaState()
    return {
        bloodVolume = 5000,
        maxBloodVolume = 5000,
        bleedingRate = 0.0,
        painLevel = 0,
        isUnconscious = false,
        limbs = {
            ['head'] = Nyx.Trauma.CreateDefaultLimbState(),
            ['torso'] = Nyx.Trauma.CreateDefaultLimbState(),
            ['left_arm'] = Nyx.Trauma.CreateDefaultLimbState(),
            ['right_arm'] = Nyx.Trauma.CreateDefaultLimbState(),
            ['left_leg'] = Nyx.Trauma.CreateDefaultLimbState(),
            ['right_leg'] = Nyx.Trauma.CreateDefaultLimbState()
        }
    }
end

-- 4. Hemodynamics & Bleed Rate Calculation
function Nyx.Trauma.CalculateBleedRate(state)
    if type(state) ~= "table" or type(state.limbs) ~= "table" then
        return 0.0
    end

    local totalBleed = 0.0
    for limbKey, limbData in pairs(state.limbs) do
        local isExtremity = Nyx.Trauma.ExtremityLimbs[limbKey] == true
        local hasTourniquet = (limbData.hasTourniquet == true)

        -- Tourniquet completely occludes blood flow on extremity limbs
        if not (isExtremity and hasTourniquet) then
            local limbHasActiveBleed = false
            if type(limbData.wounds) == "table" then
                for _, wound in ipairs(limbData.wounds) do
                    if not wound.bandaged then
                        local wType = wound.type or "laceration"
                        local base = Nyx.Trauma.BaseBleedRates[wType] or 1.0
                        local sev = tonumber(wound.severity) or 1.0
                        local bleed = base * sev
                        totalBleed = totalBleed + bleed
                        if bleed > 0 then
                            limbHasActiveBleed = true
                        end
                    end
                end
            end
            limbData.isBleeding = limbHasActiveBleed
        else
            limbData.isBleeding = false
        end
    end

    totalBleed = math.floor(totalBleed * 100 + 0.5) / 100
    state.bleedingRate = totalBleed
    return totalBleed
end

-- 5. Hypovolemic Shock Classification
function Nyx.Trauma.CalculateShockClass(bloodVolume)
    local vol = tonumber(bloodVolume) or 5000
    vol = math.max(0, math.min(5000, vol))

    if vol >= 4250 then
        return 1, "Class I (Mild / Stable)", false, {
            visionImpaired = false,
            stumbleChance = 0.0,
            speedMultiplier = 1.0,
            description = "Normális keringés, stabil vitális paraméterek."
        }
    elseif vol >= 3500 then
        return 2, "Class II (Moderate Shock)", false, {
            visionImpaired = true,
            stumbleChance = 0.05,
            speedMultiplier = 0.90,
            description = "Enyhe vérnyomásesés, tachicardia, látótér-zavarok."
        }
    elseif vol >= 3000 then
        return 3, "Class III (Severe Shock)", false, {
            visionImpaired = true,
            stumbleChance = 0.25,
            speedMultiplier = 0.70,
            description = "Súlyos hipovolémia, szédülés, csőlátás és ájulásveszély."
        }
    else
        return 4, "Class IV (Critical / Lethal Shock)", true, {
            visionImpaired = true,
            stumbleChance = 1.0,
            speedMultiplier = 0.0,
            description = "Kritikus vérveszteség, azonnali eszméletvesztés és sokk."
        }
    end
end

-- 6. Dynamic Blood Volume Simulation Tick
function Nyx.Trauma.SimulateBloodTick(state, deltaSeconds)
    if type(state) ~= "table" then return 5000, 0.0, false end

    local dt = math.max(0.05, tonumber(deltaSeconds) or 1.0)
    local bleedRate = Nyx.Trauma.CalculateBleedRate(state)

    if bleedRate > 0 then
        local lostBlood = bleedRate * dt
        local currentVol = tonumber(state.bloodVolume) or 5000
        state.bloodVolume = math.max(0.0, math.min(5000.0, currentVol - lostBlood))
        state.bloodVolume = math.floor(state.bloodVolume * 10 + 0.5) / 10
    end

    local classNum, _, isUnconscious = Nyx.Trauma.CalculateShockClass(state.bloodVolume)
    state.isUnconscious = isUnconscious

    return state.bloodVolume, state.bleedingRate, state.isUnconscious
end

-- 7. Wound Ingestion & Application
function Nyx.Trauma.AddWound(state, limb, woundType, severity)
    if type(state) ~= "table" or type(state.limbs) ~= "table" then
        return false, "INVALID_TRAUMA_STATE"
    end

    if not Nyx.Trauma.ValidLimbs[limb] then
        return false, "INVALID_LIMB"
    end

    if not Nyx.Trauma.WoundTypes[woundType] then
        return false, "INVALID_WOUND_TYPE"
    end

    local limbData = state.limbs[limb]
    if not limbData then
        limbData = Nyx.Trauma.CreateDefaultLimbState()
        state.limbs[limb] = limbData
    end

    local sev = math.max(0.1, math.min(5.0, tonumber(severity) or 1.0))
    local wound = {
        id = #limbData.wounds + 1,
        type = woundType,
        severity = sev,
        bandaged = false,
        createdAt = os.time()
    }
    table.insert(limbData.wounds, wound)

    -- Specific physiological impacts per wound type
    if woundType == "fracture" then
        limbData.isFractured = true
        limbData.health = math.max(0, limbData.health - math.floor(35 * sev))
        state.painLevel = math.min(100, (state.painLevel or 0) + math.floor(25 * sev))
    elseif woundType == "arterial_bleed" then
        limbData.isBleeding = true
        limbData.health = math.max(0, limbData.health - math.floor(40 * sev))
        state.painLevel = math.min(100, (state.painLevel or 0) + math.floor(30 * sev))
    elseif woundType == "ballistic" then
        limbData.isBleeding = true
        limbData.health = math.max(0, limbData.health - math.floor(30 * sev))
        state.painLevel = math.min(100, (state.painLevel or 0) + math.floor(20 * sev))
    elseif woundType == "laceration" then
        limbData.isBleeding = true
        limbData.health = math.max(0, limbData.health - math.floor(15 * sev))
        state.painLevel = math.min(100, (state.painLevel or 0) + math.floor(10 * sev))
    elseif woundType == "burn" then
        limbData.health = math.max(0, limbData.health - math.floor(20 * sev))
        state.painLevel = math.min(100, (state.painLevel or 0) + math.floor(20 * sev))
    elseif woundType == "blunt" then
        limbData.health = math.max(0, limbData.health - math.floor(10 * sev))
        state.painLevel = math.min(100, (state.painLevel or 0) + math.floor(5 * sev))
    end

    Nyx.Trauma.CalculateBleedRate(state)
    return true, wound
end

-- 8. Zero-Trust Treatment Validation
function Nyx.Trauma.CanTreatLimb(state, limb, item)
    if type(state) ~= "table" or type(state.limbs) ~= "table" then
        return false, "INVALID_TRAUMA_STATE"
    end

    if not Nyx.Trauma.ValidLimbs[limb] then
        return false, "INVALID_LIMB"
    end

    local limbData = state.limbs[limb]
    if not limbData then
        return false, "LIMB_DATA_MISSING"
    end

    local itm = tostring(item or "")
    if itm == "tourniquet" then
        if not Nyx.Trauma.ExtremityLimbs[limb] then
            return false, "CANNOT_APPLY_TOURNIQUET_TO_CORE"
        end
        return true, "OK"
    elseif itm == "splint" then
        if not Nyx.Trauma.ExtremityLimbs[limb] then
            return false, "CANNOT_APPLY_SPLINT_TO_CORE"
        end
        if not limbData.isFractured then
            return false, "LIMB_NOT_FRACTURED"
        end
        return true, "OK"
    elseif itm == "bandage_sterile" or itm == "med_bandage" then
        return true, "OK"
    elseif itm == "first_aid_pack" or itm == "med_firstaid" then
        return true, "OK"
    elseif itm == "morphine_ampoule" then
        return true, "OK"
    else
        return false, "UNSUPPORTED_MEDICAL_ITEM"
    end
end

-- 9. Field Stabilization Execution
function Nyx.Trauma.ApplyTreatment(state, limb, item)
    local canTreat, reason = Nyx.Trauma.CanTreatLimb(state, limb, item)
    if not canTreat then
        return false, reason
    end

    local limbData = state.limbs[limb]
    local itm = tostring(item or "")
    local res = {
        limb = limb,
        item = itm,
        timestamp = os.time()
    }

    if itm == "tourniquet" then
        limbData.hasTourniquet = true
        limbData.isBleeding = false
        res.tourniquetApplied = true
        res.treatmentType = "arterial_occlusion"
    elseif itm == "splint" then
        limbData.isFractured = false
        limbData.health = math.min(100, limbData.health + 15)
        state.painLevel = math.max(0, (state.painLevel or 0) - 15)
        res.fractureStabilized = true
        res.treatmentType = "fracture_stabilization"
    elseif itm == "bandage_sterile" or itm == "med_bandage" then
        local healedWounds = 0
        if type(limbData.wounds) == "table" then
            for _, w in ipairs(limbData.wounds) do
                if not w.bandaged then
                    w.bandaged = true
                    healedWounds = healedWounds + 1
                end
            end
        end
        limbData.health = math.min(100, limbData.health + 25)
        state.painLevel = math.max(0, (state.painLevel or 0) - 10)
        res.healedWoundsCount = healedWounds
        res.limbHealthRestored = 25
        res.treatmentType = "pressure_bandaging"
    elseif itm == "first_aid_pack" or itm == "med_firstaid" then
        -- Comprehensive surgical trauma kit: cures fractures and bandaging
        limbData.isFractured = false
        local healedWounds = 0
        if type(limbData.wounds) == "table" then
            for _, w in ipairs(limbData.wounds) do
                if not w.bandaged then
                    w.bandaged = true
                    healedWounds = healedWounds + 1
                end
            end
        end
        limbData.health = math.min(100, limbData.health + 60)
        state.painLevel = math.max(0, (state.painLevel or 0) - 30)
        res.healedWoundsCount = healedWounds
        res.limbHealthRestored = 60
        res.fractureStabilized = true
        res.treatmentType = "advanced_trauma_care"
    elseif itm == "morphine_ampoule" then
        state.painLevel = 0
        res.painRelieved = true
        res.treatmentType = "analgesia"
    end

    Nyx.Trauma.CalculateBleedRate(state)
    local classNum, classLabel, isUnconscious = Nyx.Trauma.CalculateShockClass(state.bloodVolume)
    state.isUnconscious = isUnconscious
    res.currentBleedingRate = state.bleedingRate
    res.currentBloodVolume = state.bloodVolume
    res.shockClass = classLabel

    return true, res
end

-- 10. Diagnosis Formatter for EMS Triage
function Nyx.Trauma.FormatTraumaDiagnosis(state)
    if type(state) ~= "table" then return nil end

    local classNum, classLabel, isUnconscious, meta = Nyx.Trauma.CalculateShockClass(state.bloodVolume)
    local diagnosis = {
        bloodVolume = state.bloodVolume or 5000,
        maxBloodVolume = state.maxBloodVolume or 5000,
        bleedingRate = state.bleedingRate or 0.0,
        painLevel = state.painLevel or 0,
        isUnconscious = isUnconscious,
        shockClass = classNum,
        shockLabel = classLabel,
        shockDescription = meta.description,
        limbs = {}
    }

    if type(state.limbs) == "table" then
        for limbKey, limbData in pairs(state.limbs) do
            diagnosis.limbs[limbKey] = {
                label = Nyx.Trauma.LimbLabels[limbKey] or limbKey,
                health = limbData.health or 100,
                isBleeding = limbData.isBleeding or false,
                isFractured = limbData.isFractured or false,
                hasTourniquet = limbData.hasTourniquet or false,
                woundsCount = type(limbData.wounds) == "table" and #limbData.wounds or 0
            }
        end
    end

    return diagnosis
end
