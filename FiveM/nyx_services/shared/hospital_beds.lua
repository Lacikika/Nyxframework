--[[
    Nyxframework: nyx_services
    File: shared/hospital_beds.lua
    Description: Pure Lua 5.4 specifications, bed classification taxonomy,
                 hemodynamic vital monitors, bed maintenance and soiling state machine,
                 and clinical infusion rate calculations.
]]

Nyx = Nyx or {}
Nyx.HospitalBeds = Nyx.HospitalBeds or {}

-- 1. Bed Classification Taxonomy
Nyx.HospitalBeds.BedTypes = {
    ['icu_trauma'] = {
        key = 'icu_trauma',
        label = "Intenzív Terápiás Trauma Ágy",
        description = "Fejlett hemodinamikai monitorozás, automata plazma infúzió és sebészeti beavatkozási képesség.",
        powerRequirementKw = 15.0,
        bloodInfusionRate = 60.0,  -- mL per recovery tick
        woundHealingRate = 25.0,   -- HP restored per tick
        painReliefRate = 20.0,     -- Pain reduced per tick
        canPerformSurgery = true,
        monitorActive = true,
        soiledCleanliness = 15.0,
        requiredProp = "v_med_bed1"
    },
    ['general_ward'] = {
        key = 'general_ward',
        label = "Általános Osztályos Kórházi Ágy",
        description = "Alapvető vitális monitorozás, fiziológiás infúzió és standard poszt-operatív stabilizáció.",
        powerRequirementKw = 5.0,
        bloodInfusionRate = 30.0,
        woundHealingRate = 15.0,
        painReliefRate = 10.0,
        canPerformSurgery = false,
        monitorActive = true,
        soiledCleanliness = 25.0,
        requiredProp = "v_med_bed2"
    },
    ['emergency_cot'] = {
        key = 'emergency_cot',
        label = "Sürgősségi Területi Tábori Ágy",
        description = "Mechanikus tábori fekhely passzív pihenésre és vérzés elállítása utáni lábadozásra áramellátás nélkül.",
        powerRequirementKw = 0.0,
        bloodInfusionRate = 12.0,
        woundHealingRate = 6.0,
        painReliefRate = 5.0,
        canPerformSurgery = false,
        monitorActive = false,
        soiledCleanliness = 30.0,
        requiredProp = "prop_armychair_01"
    }
}

-- 2. Maintenance Status Taxonomy
Nyx.HospitalBeds.MaintenanceStates = {
    ['clean'] = {
        label = "TISZTA / FELVÉTELRE KÉSZ",
        badge = "badge-success",
        color = "#10B981",
        canAdmit = true
    },
    ['occupied'] = {
        label = "FOGLALT / PÁCIENS ELLÁTÁS ALATT",
        badge = "badge-info",
        color = "#3B82F6",
        canAdmit = false
    },
    ['soiled'] = {
        label = "SZENNYSZINTŰ / FERTŐTLENÍTÉSRE VÁR",
        badge = "badge-warning",
        color = "#F59E0B",
        canAdmit = false
    },
    ['sanitizing'] = {
        label = "FERTŐTLENÍTÉS FOLYAMATBAN",
        badge = "badge-primary",
        color = "#8B5CF6",
        canAdmit = false
    },
    ['offline_power'] = {
        label = "HÁLÓZATI ÁRAMKIMARADÁS (OFFLINE)",
        badge = "badge-danger",
        color = "#EF4444",
        canAdmit = false
    }
}

-- 3. Sanitization Consumables
Nyx.HospitalBeds.SanitizingItems = {
    ['item_disinfectant'] = {
        label = "Orvosi Fertőtlenítőszer",
        cleanlinessRestored = 100.0,
        durationSeconds = 6
    },
    ['clean_linens'] = {
        label = "Steril Kórházi Ágyneműkészlet",
        cleanlinessRestored = 100.0,
        durationSeconds = 8
    },
    ['bleach'] = {
        label = "Klóros Ipari Tisztítószer",
        cleanlinessRestored = 85.0,
        durationSeconds = 10
    }
}

-- 4. Clinical Infusion Items
Nyx.HospitalBeds.InfusionItems = {
    ['med_plasma'] = {
        label = "Steril Plazma Egység",
        bloodRecoveryMl = 500,
        priority = 1
    },
    ['first_aid_pack'] = {
        label = "Trauma Elsősegély Csomag",
        healsFractures = true,
        healsWounds = true,
        priority = 2
    },
    ['med_firstaid'] = {
        label = "Kórházi Elsősegély Csomag",
        healsFractures = true,
        healsWounds = true,
        priority = 2
    },
    ['med_surgical_pack'] = {
        label = "Steril Sebészeti Csomag",
        requiredForIcu = true,
        curesDeepTrauma = true,
        priority = 3
    },
    ['saline_bag'] = {
        label = "Fiziológiás Sóoldat Infúzió",
        bloodRecoveryMl = 250,
        priority = 4
    }
}

-- 5. Calculate Effective Infusion Rates
--- @param bedType string 'icu_trauma', 'general_ward', 'emergency_cot'
--- @param supplyStatus string 'optimal', 'degraded', 'critical_shortage'
--- @param isPowered boolean Whether electrical grid is online
--- @return table Rate metrics { bloodMlPerTick, woundHpPerTick, painPerTick, isPowered, powerPenalty }
function Nyx.HospitalBeds.CalculateBedInfusionRate(bedType, supplyStatus, isPowered)
    local def = Nyx.HospitalBeds.BedTypes[bedType] or Nyx.HospitalBeds.BedTypes['general_ward']
    supplyStatus = supplyStatus or "optimal"
    if isPowered == nil then isPowered = true end

    local powerPenalty = 1.0
    if def.powerRequirementKw > 0 and not isPowered then
        powerPenalty = 0.25 -- Emergency backup battery only delivers 25% efficiency
    end

    local supplyMultiplier = 1.0
    if supplyStatus == "critical_shortage" then
        supplyMultiplier = 0.40 -- 60% penalty under critical shortage
    elseif supplyStatus == "degraded" then
        supplyMultiplier = 0.75 -- 25% penalty under degraded stock
    end

    local compositeMult = powerPenalty * supplyMultiplier

    local bloodRate = math.floor((def.bloodInfusionRate * compositeMult) * 10 + 0.5) / 10
    local woundRate = math.floor((def.woundHealingRate * compositeMult) * 10 + 0.5) / 10
    local painRate = math.floor((def.painReliefRate * compositeMult) * 10 + 0.5) / 10

    return {
        bloodMlPerTick = bloodRate,
        woundHpPerTick = woundRate,
        painPerTick = painRate,
        isPowered = isPowered,
        powerPenalty = powerPenalty,
        supplyMultiplier = supplyMultiplier,
        compositeMultiplier = compositeMult
    }
end

-- 6. Evaluate Bed Admission Eligibility
--- @param bed table Hospital bed record
--- @param citizenTraumaState table|nil Citizen trauma state
--- @param isPowered boolean Whether regional substation is energized
--- @return boolean canAdmit, string reasonCode
function Nyx.HospitalBeds.EvaluateBedEligibility(bed, citizenTraumaState, isPowered)
    if not bed or type(bed) ~= "table" then
        return false, "INVALID_BED_RECORD"
    end

    local def = Nyx.HospitalBeds.BedTypes[bed.bed_type] or Nyx.HospitalBeds.BedTypes['general_ward']

    if tonumber(bed.is_occupied) == 1 or bed.occupied_by_citizen_id then
        return false, "BED_ALREADY_OCCUPIED"
    end

    if bed.maintenance_status == "soiled" or (tonumber(bed.bed_cleanliness) or 100.0) < 50.0 then
        return false, "BED_SOILED_REQUIRES_SANITIZATION"
    end

    if bed.maintenance_status == "sanitizing" then
        return false, "BED_CURRENTLY_SANITIZING"
    end

    if def.powerRequirementKw > 0 and isPowered == false then
        return false, "BED_OFFLINE_POWER_BLACKOUT"
    end

    return true, "ELIGIBLE_FOR_ADMISSION"
end

-- 7. Calculate Sanitization Requirements
--- @param bed table Hospital bed record
--- @param itemKey string Sanitizing consumable key
--- @return boolean isValid, table|string sanitizationPlanOrError
function Nyx.HospitalBeds.CalculateSanitizationRequirement(bed, itemKey)
    if not bed or type(bed) ~= "table" then
        return false, "INVALID_BED_RECORD"
    end

    local cleanItem = Nyx.HospitalBeds.SanitizingItems[itemKey]
    if not cleanItem then
        return false, "INVALID_SANITIZING_ITEM"
    end

    local currentCleanliness = tonumber(bed.bed_cleanliness) or 100.0
    if currentCleanliness >= 98.0 and bed.maintenance_status == "clean" then
        return false, "BED_ALREADY_SANITIZED"
    end

    local targetCleanliness = math.min(100.0, math.max(currentCleanliness, cleanItem.cleanlinessRestored))

    return true, {
        item = itemKey,
        itemLabel = cleanItem.label,
        durationSeconds = cleanItem.durationSeconds,
        currentCleanliness = currentCleanliness,
        targetCleanliness = targetCleanliness,
        newStatus = "clean"
    }
end

-- 8. Evaluate Real-Time Vitals Telemetry
--- Computes realistic clinical vitals based on patient hemodynamic blood volume, trauma shock, and bed status.
--- @param citizenTraumaState table
--- @param bed table
--- @param isPowered boolean
--- @return table Vitals telemetry { bpm, systolic, diastolic, spo2, rhythm, ekgState, shockClass }
function Nyx.HospitalBeds.EvaluateVitalsTelemetry(citizenTraumaState, bed, isPowered)
    citizenTraumaState = citizenTraumaState or {}
    local bloodVol = tonumber(citizenTraumaState.bloodVolume) or 5000.0
    local pain = tonumber(citizenTraumaState.painLevel) or 0
    local isUnconscious = citizenTraumaState.isUnconscious == true

    if isPowered == nil then isPowered = true end
    local def = bed and (Nyx.HospitalBeds.BedTypes[bed.bed_type] or Nyx.HospitalBeds.BedTypes['general_ward']) or Nyx.HospitalBeds.BedTypes['general_ward']

    -- Base physiological curves
    local bloodRatio = math.max(0.0, math.min(1.0, bloodVol / 5000.0))

    local bpm = 72
    local systolic = 120
    local diastolic = 80
    local spo2 = 99
    local rhythm = "Sinus Rhythm"
    local ekgState = "normal"
    local shockClass = 1

    if bloodRatio >= 0.85 then
        -- Stable / Mild
        shockClass = 1
        bpm = math.floor(72 + (pain * 0.2))
        systolic = 120
        diastolic = 80
        spo2 = 98 + math.random(0, 1)
        rhythm = "Normal Sinus Rhythm"
        ekgState = "stable"
    elseif bloodRatio >= 0.70 then
        -- Class II Moderate Shock: Tachycardia compensatory reflex
        shockClass = 2
        bpm = math.floor(105 + (pain * 0.15))
        systolic = 105
        diastolic = 70
        spo2 = 94
        rhythm = "Sinus Tachycardia"
        ekgState = "warning"
    elseif bloodRatio >= 0.50 then
        -- Class III Severe Shock: Pronounced hypotension
        shockClass = 3
        bpm = math.floor(135 + (pain * 0.1))
        systolic = 85
        diastolic = 55
        spo2 = 88
        rhythm = "Severe Tachycardia / Arrhythmia"
        ekgState = "critical"
    elseif bloodRatio > 0.10 then
        -- Class IV Critical Shock: Impending cardiovascular collapse
        shockClass = 4
        bpm = 155
        systolic = 60
        diastolic = 40
        spo2 = 74
        rhythm = "Ventricular Tachycardia"
        ekgState = "lethal"
    else
        -- Asystole / Cardiac Arrest
        shockClass = 4
        bpm = 0
        systolic = 0
        diastolic = 0
        spo2 = 0
        rhythm = "Asystole (Flatline)"
        ekgState = "flatline"
    end

    -- If monitor is disabled or power is offline, telemetry display shows offline
    local monitorOperational = (def.monitorActive and isPowered)
    if not monitorOperational then
        ekgState = "offline"
    end

    return {
        bloodVolume = bloodVol,
        heartRateBpm = bpm,
        bloodPressureSystolic = systolic,
        bloodPressureDiastolic = diastolic,
        oxygenSaturationSpO2 = spo2,
        cardiacRhythm = rhythm,
        ekgState = ekgState,
        shockClass = shockClass,
        isUnconscious = isUnconscious,
        monitorOperational = monitorOperational
    }
end

-- 9. Format Bed UI Status Summary
--- @param bed table
--- @return table formattedSummary
function Nyx.HospitalBeds.FormatBedSummary(bed)
    if not bed then return {} end
    local typeDef = Nyx.HospitalBeds.BedTypes[bed.bed_type] or Nyx.HospitalBeds.BedTypes['general_ward']
    local statusDef = Nyx.HospitalBeds.MaintenanceStates[bed.maintenance_status] or Nyx.HospitalBeds.MaintenanceStates['clean']

    local cleanliness = tonumber(bed.bed_cleanliness) or 100.0
    local isOccupied = tonumber(bed.is_occupied) == 1

    return {
        bedId = bed.bed_id,
        bedUuid = bed.bed_uuid,
        hospitalId = bed.hospital_id,
        label = bed.bed_label or "Hospital Bed",
        bedType = bed.bed_type,
        typeLabel = typeDef.label,
        typeDescription = typeDef.description,
        isOccupied = isOccupied,
        occupiedBy = bed.occupied_by_citizen_id,
        cleanliness = cleanliness,
        status = bed.maintenance_status,
        statusLabel = statusDef.label,
        statusBadge = statusDef.badge,
        statusColor = statusDef.color,
        ivActive = tonumber(bed.iv_drip_active) == 1,
        vitalMonitorActive = tonumber(bed.vital_monitor_active) == 1,
        canAdmit = (statusDef.canAdmit and cleanliness >= 50.0 and not isOccupied)
    }
end
