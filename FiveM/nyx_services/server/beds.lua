--[[
    Nyxframework: nyx_services
    File: server/beds.lua
    Description: Physical hospital bed server subsystem, clinical triage admission,
                 hemodynamic vital monitors, bed maintenance and soiling state machine,
                 automated IV infusion from hospital supply stashes, and database persistence.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.HospitalBeds = {}       -- [bedId] = bedState
Nyx.Services.OccupiedBedSources = {} -- [src] = bedId

-- Helper: Generate UUID for Bed Audit Log
local function generateBedAuditUUID()
    if exports['nyx_core'] and exports['nyx_core'].GenerateNonce then
        return exports['nyx_core']:GenerateNonce()
    end
    local template = "bed-xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format("%x", v)
    end)
end

-- Helper: Safe JSON Coords Parser
local function parseCoordsJson(jsonVal)
    if not jsonVal then return { x = 0.0, y = 0.0, z = 0.0, w = 0.0 } end
    if type(jsonVal) == "table" then return jsonVal end
    if type(jsonVal) == "string" then
        local ok, parsed = pcall(json.decode, jsonVal)
        if ok and type(parsed) == "table" then return parsed end
    end
    return { x = 0.0, y = 0.0, z = 0.0, w = 0.0 }
end

-- 1. Bootloader: Hydrate Hospital Beds from Database
function Nyx.Services.LoadHospitalBeds()
    local rows = MySQL.query.await("SELECT * FROM `nyx_services_hospital_beds`")
    if rows then
        for _, r in ipairs(rows) do
            local coords = parseCoordsJson(r.coords)
            local bedObj = {
                bed_id = r.bed_id,
                bed_uuid = r.bed_uuid,
                hospital_id = r.hospital_id,
                bed_label = r.bed_label,
                bed_type = r.bed_type or "general_ward",
                coords = coords,
                occupied_by_citizen_id = r.occupied_by_citizen_id,
                is_occupied = tonumber(r.is_occupied) or 0,
                bed_cleanliness = tonumber(r.bed_cleanliness) or 100.0,
                maintenance_status = r.maintenance_status or "clean",
                vital_monitor_active = tonumber(r.vital_monitor_active) or 1,
                iv_drip_active = tonumber(r.iv_drip_active) or 0,
                current_infusion_item = r.current_infusion_item,
                admission_timestamp = r.admission_timestamp,
                last_sanitized_at = r.last_sanitized_at,
                total_patients_treated = tonumber(r.total_patients_treated) or 0
            }

            -- Clear any orphaned player occupancy on boot
            if bedObj.is_occupied == 1 and not bedObj.occupied_by_citizen_id then
                bedObj.is_occupied = 0
                bedObj.maintenance_status = "clean"
            end

            Nyx.Services.HospitalBeds[r.bed_id] = bedObj
        end

        if Config.Debug then
            print(string.format("^2[Nyx:Services]^7 Loaded %d physical hospital beds from database.^7", #rows))
        end
    end
end

-- 2. Authoritative Database Persistence
function Nyx.Services.SaveBedRecord(bedId)
    local bed = Nyx.Services.HospitalBeds[bedId]
    if not bed then return end

    pcall(function()
        MySQL.prepare.await([[
            UPDATE `nyx_services_hospital_beds`
            SET `occupied_by_citizen_id` = ?,
                `is_occupied` = ?,
                `bed_cleanliness` = ?,
                `maintenance_status` = ?,
                `vital_monitor_active` = ?,
                `iv_drip_active` = ?,
                `current_infusion_item` = ?,
                `total_patients_treated` = ?
            WHERE `bed_id` = ?
        ]], {
            bed.occupied_by_citizen_id,
            bed.is_occupied,
            bed.bed_cleanliness,
            bed.maintenance_status,
            bed.vital_monitor_active,
            bed.iv_drip_active,
            bed.current_infusion_item,
            bed.total_patients_treated,
            bedId
        })
    end)
end

-- 3. Immutable Bed Audit Logger
function Nyx.Services.LogBedAudit(bedId, hospitalId, citizenId, action, itemConsumed, qty, telemetry, notes)
    local auditUuid = generateBedAuditUUID()
    local teleJson = telemetry and json.encode(telemetry) or nil

    pcall(function()
        MySQL.prepare([[
            INSERT INTO `nyx_services_hospital_bed_audits`
                (`audit_uuid`, `bed_id`, `hospital_id`, `citizen_id`, `action`,
                 `item_consumed`, `quantity`, `vital_telemetry`, `notes`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            auditUuid,
            bedId,
            hospitalId,
            citizenId,
            action,
            itemConsumed,
            qty or 0,
            teleJson,
            notes
        })
    end)
end

-- 4. Check Electrical Grid Status for a Hospital Bed
function Nyx.Services.IsBedPowered(bedId)
    local bed = Nyx.Services.HospitalBeds[bedId]
    if not bed then return true end

    local hosp = Nyx.Services.Hospitals[bed.hospital_id]
    if hosp and hosp.substationId and Nyx.Services.Substations and Nyx.Services.Substations[hosp.substationId] then
        return not Nyx.Services.Substations[hosp.substationId].isBlackout
    end

    if bed.coords and exports['nyx_services'] and exports['nyx_services'].IsCoordsPowered then
        return exports['nyx_services']:IsCoordsPowered(vector3(bed.coords.x, bed.coords.y, bed.coords.z))
    end

    return true
end

-- 5. Admit Patient to Hospital Bed
function Nyx.Services.AdmitPatientToBed(bedId, patientSrc)
    local pSrc = tonumber(patientSrc)
    if not pSrc then return false, "INVALID_PATIENT_SOURCE" end

    local bed = Nyx.Services.HospitalBeds[bedId]
    if not bed then return false, "BED_NOT_FOUND" end

    local player = Nyx.GetPlayer(pSrc)
    if not player or not player.citizenId then
        return false, "UNAUTHENTICATED_PATIENT"
    end

    -- Verify patient is not already admitted to another bed
    if Nyx.Services.OccupiedBedSources[pSrc] then
        return false, "ALREADY_ADMITTED_TO_BED"
    end

    local traumaState = Nyx.Services.GetPlayerTrauma(pSrc)
    local isPowered = Nyx.Services.IsBedPowered(bedId)

    -- Evaluate eligibility using shared domain rules
    local canAdmit, reason = Nyx.HospitalBeds.EvaluateBedEligibility(bed, traumaState, isPowered)
    if not canAdmit then
        return false, reason
    end

    -- Lock bed and transition status
    bed.is_occupied = 1
    bed.occupied_by_citizen_id = player.citizenId
    bed.maintenance_status = "occupied"
    bed.iv_drip_active = 1
    bed.current_infusion_item = "med_plasma"
    bed.admission_timestamp = os.time()

    Nyx.Services.OccupiedBedSources[pSrc] = bedId

    Nyx.Services.SaveBedRecord(bedId)

    local vitals = Nyx.HospitalBeds.EvaluateVitalsTelemetry(traumaState, bed, isPowered)
    Nyx.Services.LogBedAudit(bedId, bed.hospital_id, player.citizenId, 'ADMITTED', nil, 0, vitals, "Patient admitted to clinical bed")

    -- Notify admitted client
    TriggerClientEvent("nyx:services:client:bedAdmitted", pSrc, {
        bedId = bedId,
        hospitalId = bed.hospital_id,
        bedType = bed.bed_type,
        coords = bed.coords,
        vitals = vitals
    })

    -- Broadcast bed state update
    TriggerClientEvent("nyx:services:client:bedStatusUpdated", -1, {
        bedId = bedId,
        maintenanceStatus = bed.maintenance_status,
        isOccupied = true,
        occupiedBy = player.citizenId,
        cleanliness = bed.bed_cleanliness
    })

    print(string.format("^2[Nyx:Services] Patient %s admitted to bed '%s' (%s) at %s.^7",
        player.citizenId, bedId, bed.bed_type, bed.hospital_id))

    return true, {
        bedId = bedId,
        bedType = bed.bed_type,
        status = bed.maintenance_status,
        coords = bed.coords,
        vitals = vitals
    }
end

-- 6. Discharge Patient from Hospital Bed (Transitions Bed to Soiled)
function Nyx.Services.DischargePatientFromBed(bedId, dischargeReason)
    local bed = Nyx.Services.HospitalBeds[bedId]
    if not bed then return false, "BED_NOT_FOUND" end

    local citizenId = bed.occupied_by_citizen_id

    -- Locate player source if connected
    local patientSrc = nil
    for s, bId in pairs(Nyx.Services.OccupiedBedSources) do
        if bId == bedId then
            patientSrc = s
            break
        end
    end

    local typeDef = Nyx.HospitalBeds.BedTypes[bed.bed_type] or Nyx.HospitalBeds.BedTypes['general_ward']
    local soiledClean = typeDef.soiledCleanliness or 20.0

    -- Update bed properties
    bed.is_occupied = 0
    bed.occupied_by_citizen_id = nil
    bed.maintenance_status = "soiled"
    bed.bed_cleanliness = soiledClean
    bed.iv_drip_active = 0
    bed.current_infusion_item = nil
    bed.total_patients_treated = (bed.total_patients_treated or 0) + 1

    if patientSrc then
        Nyx.Services.OccupiedBedSources[patientSrc] = nil
        TriggerClientEvent("nyx:services:client:bedDischarged", patientSrc, {
            bedId = bedId,
            reason = dischargeReason or "NORMAL_DISCHARGE"
        })
    end

    Nyx.Services.SaveBedRecord(bedId)

    Nyx.Services.LogBedAudit(bedId, bed.hospital_id, citizenId, 'DISCHARGED', nil, 0, nil, dischargeReason or "Patient discharged from bed")
    Nyx.Services.LogBedAudit(bedId, bed.hospital_id, nil, 'SOILED', nil, 0, nil, string.format("Bed soiled post-discharge (cleanliness: %.1f%%)", soiledClean))

    -- Broadcast state update
    TriggerClientEvent("nyx:services:client:bedStatusUpdated", -1, {
        bedId = bedId,
        maintenanceStatus = bed.maintenance_status,
        isOccupied = false,
        occupiedBy = nil,
        cleanliness = bed.bed_cleanliness
    })

    print(string.format("^3[Nyx:Services] Bed '%s' discharged patient -> transitioned to SOILED (Cleanliness: %.1f%%).^7",
        bedId, soiledClean))

    return true, {
        bedId = bedId,
        status = bed.maintenance_status,
        cleanliness = bed.bed_cleanliness,
        totalTreated = bed.total_patients_treated
    }
end

-- 7. Sanitize Hospital Bed using Disinfectant Consumable
function Nyx.Services.SanitizeBed(src, bedId, itemKey)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local bed = Nyx.Services.HospitalBeds[bedId]
    if not bed then return false, "BED_NOT_FOUND" end

    if tonumber(bed.is_occupied) == 1 then
        return false, "CANNOT_SANITIZE_OCCUPIED_BED"
    end

    itemKey = itemKey or "item_disinfectant"
    local okPlan, planOrErr = Nyx.HospitalBeds.CalculateSanitizationRequirement(bed, itemKey)
    if not okPlan then
        return false, planOrErr
    end

    local plan = planOrErr
    local invId = "citizen:" .. player.citizenId

    -- Verify player has required sanitizing consumable
    local removed, _ = exports['nyx_inventory']:RemoveItem(invId, itemKey, 1)
    if not removed then
        -- Try fallback without prefix
        local invAlt = string.format("char:%s:main", player.citizenId)
        removed, _ = exports['nyx_inventory']:RemoveItem(invAlt, itemKey, 1)
        if not removed then
            return false, "INSUFFICIENT_SANITIZING_ITEMS"
        end
    end

    -- Apply sanitization
    bed.bed_cleanliness = plan.targetCleanliness
    bed.maintenance_status = "clean"
    bed.last_sanitized_at = os.time()

    Nyx.Services.SaveBedRecord(bedId)

    Nyx.Services.LogBedAudit(
        bedId, bed.hospital_id, player.citizenId, 'SANITIZED',
        itemKey, 1, nil, string.format("Bed sanitized by %s (Cleanliness: %.1f%%)", player.citizenId, bed.bed_cleanliness)
    )

    -- Broadcast state update
    TriggerClientEvent("nyx:services:client:bedStatusUpdated", -1, {
        bedId = bedId,
        maintenanceStatus = bed.maintenance_status,
        isOccupied = false,
        occupiedBy = nil,
        cleanliness = bed.bed_cleanliness
    })

    print(string.format("^2[Nyx:Services] Bed '%s' sanitized by %s using %s -> CLEAN (100.0%%).^7",
        bedId, player.citizenId, itemKey))

    return true, {
        bedId = bedId,
        cleanliness = bed.bed_cleanliness,
        status = bed.maintenance_status,
        itemUsed = itemKey
    }
end

-- 8. Administer Clinical Treatment to Patient on Bed
function Nyx.Services.AdministerBedTreatment(bedId, treatmentItem)
    local bed = Nyx.Services.HospitalBeds[bedId]
    if not bed then return false, "BED_NOT_FOUND" end

    if tonumber(bed.is_occupied) ~= 1 or not bed.occupied_by_citizen_id then
        return false, "BED_NOT_OCCUPIED"
    end

    local hosp = Nyx.Services.Hospitals[bed.hospital_id]
    if not hosp then return false, "HOSPITAL_NOT_FOUND" end

    local stashId = hosp.stashId or Nyx.HospitalSupplies.GetStashIdForHospital(bed.hospital_id)

    -- Check and consume from hospital stash
    local hasItem = exports['nyx_inventory'] and exports['nyx_inventory']:HasItem(stashId, treatmentItem, 1)
    if not hasItem then
        return false, "HOSPITAL_SUPPLY_DEPLETED"
    end

    exports['nyx_inventory']:RemoveItem(stashId, treatmentItem, 1)

    -- Find patient source
    local patientSrc = nil
    for s, bId in pairs(Nyx.Services.OccupiedBedSources) do
        if bId == bedId then
            patientSrc = s
            break
        end
    end

    if patientSrc then
        local state = Nyx.Services.GetPlayerTrauma(patientSrc)
        if state then
            if treatmentItem == "med_plasma" then
                state.bloodVolume = math.min(5000.0, state.bloodVolume + 500.0)
            elseif treatmentItem == "first_aid_pack" or treatmentItem == "med_firstaid" then
                for _, lData in pairs(state.limbs) do
                    lData.health = math.min(100, lData.health + 40)
                    lData.isFractured = false
                    if type(lData.wounds) == "table" then
                        for _, w in ipairs(lData.wounds) do w.bandaged = true end
                    end
                end
                state.painLevel = math.max(0, state.painLevel - 30)
            elseif treatmentItem == "med_surgical_pack" then
                for _, lData in pairs(state.limbs) do
                    lData.health = 100
                    lData.isFractured = false
                    lData.wounds = {}
                    lData.isBleeding = false
                end
                state.painLevel = 0
            end

            Nyx.Trauma.CalculateBleedRate(state)
            local _, _, isUnconscious = Nyx.Trauma.CalculateShockClass(state.bloodVolume)
            state.isUnconscious = isUnconscious

            TriggerClientEvent("nyx:services:client:traumaSync", patientSrc, {
                bloodVolume = state.bloodVolume,
                bleedingRate = state.bleedingRate,
                painLevel = state.painLevel,
                isUnconscious = state.isUnconscious,
                limbs = state.limbs
            })
            Nyx.Services.SavePlayerTrauma(patientSrc)
        end
    end

    Nyx.Services.LogBedAudit(
        bedId, bed.hospital_id, bed.occupied_by_citizen_id, 'CONSUMABLE_INFUSED',
        treatmentItem, 1, nil, string.format("Infused %s from stash %s", treatmentItem, stashId)
    )

    return true, {
        bedId = bedId,
        treatmentItem = treatmentItem,
        patientCitizenId = bed.occupied_by_citizen_id
    }
end

-- 9. Clinical Hemodynamic Recovery & Telemetry Loop (Every 2 Seconds)
CreateThread(function()
    while true do
        Wait(2000)

        for src, bedId in pairs(Nyx.Services.OccupiedBedSources) do
            local bed = Nyx.Services.HospitalBeds[bedId]
            if bed and tonumber(bed.is_occupied) == 1 then
                local hosp = Nyx.Services.Hospitals[bed.hospital_id]
                local isPowered = Nyx.Services.IsBedPowered(bedId)
                local supplyStatus = hosp and hosp.status or "optimal"

                local rates = Nyx.HospitalBeds.CalculateBedInfusionRate(bed.bed_type, supplyStatus, isPowered)

                local state = Nyx.Services.GetPlayerTrauma(src)
                if state then
                    -- Hemodynamic blood volume recovery
                    if state.bloodVolume < 5000.0 then
                        state.bloodVolume = math.min(5000.0, state.bloodVolume + rates.bloodMlPerTick)
                        state.bloodVolume = math.floor(state.bloodVolume * 10 + 0.5) / 10
                    end

                    -- Limb wound closure & fracture healing
                    if rates.woundHpPerTick > 0 and type(state.limbs) == "table" then
                        for _, lData in pairs(state.limbs) do
                            if lData.health < 100 then
                                lData.health = math.min(100, lData.health + math.floor(rates.woundHpPerTick))
                            end
                            -- In ICU or General Ward, fracture stabilizes gradually
                            if rates.woundHpPerTick >= 10.0 and lData.isFractured then
                                lData.isFractured = false
                            end
                        end
                    end

                    -- Pain relief
                    if state.painLevel and state.painLevel > 0 and rates.painPerTick > 0 then
                        state.painLevel = math.max(0, state.painLevel - math.floor(rates.painPerTick))
                    end

                    -- Check recovery from unconsciousness
                    Nyx.Trauma.CalculateBleedRate(state)
                    local _, _, isUnconscious = Nyx.Trauma.CalculateShockClass(state.bloodVolume)
                    if state.isUnconscious and not isUnconscious then
                        state.isUnconscious = false
                        TriggerClientEvent("nyx:services:client:unconsciousState", src, false)
                    end

                    -- Evaluate and dispatch vitals telemetry to patient
                    local vitals = Nyx.HospitalBeds.EvaluateVitalsTelemetry(state, bed, isPowered)
                    TriggerClientEvent("nyx:services:client:bedVitalsTick", src, {
                        bedId = bedId,
                        vitals = vitals,
                        rates = rates
                    })
                end
            end
        end
    end
end)

-- 10. Player Disconnect Listener: Cleanly Handle Bed Vacating
AddEventHandler("playerDropped", function()
    local src = source
    local bedId = Nyx.Services.OccupiedBedSources[src]
    if bedId then
        Nyx.Services.DischargePatientFromBed(bedId, "PATIENT_DISCONNECTED")
    end
end)

-- 11. Initial Startup Hydration
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end
    while not (exports['nyx_core'] and exports['nyx_core'].IsDatabaseReady and exports['nyx_core']:IsDatabaseReady()) do
        Wait(50)
    end
    Nyx.Services.LoadHospitalBeds()
end)

-- ============================================================================
-- RPC Bridge Registration
-- ============================================================================

CreateThread(function()
    while not exports['nyx_core'] or not exports['nyx_core'].RegisterRPC do
        Wait(50)
    end

    exports['nyx_core']:RegisterRPC("services:getHospitalBeds", function(src, hospitalId)
        local results = {}
        for _, bed in pairs(Nyx.Services.HospitalBeds) do
            if not hospitalId or bed.hospital_id == hospitalId then
                table.insert(results, Nyx.HospitalBeds.FormatBedSummary(bed))
            end
        end
        return results
    end)

    exports['nyx_core']:RegisterRPC("services:getBedDetails", function(src, bedId)
        local bed = Nyx.Services.HospitalBeds[bedId]
        if not bed then return nil, "BED_NOT_FOUND" end
        return Nyx.HospitalBeds.FormatBedSummary(bed)
    end)

    exports['nyx_core']:RegisterRPC("services:admitPatientToBed", function(src, bedId, targetSrc)
        local patientSrc = targetSrc or src
        return Nyx.Services.AdmitPatientToBed(bedId, patientSrc)
    end)

    exports['nyx_core']:RegisterRPC("services:dischargePatientFromBed", function(src, bedId)
        return Nyx.Services.DischargePatientFromBed(bedId, "VOLUNTARY_DISCHARGE")
    end)

    exports['nyx_core']:RegisterRPC("services:sanitizeBed", function(src, bedId, itemKey)
        return Nyx.Services.SanitizeBed(src, bedId, itemKey)
    end)

    exports['nyx_core']:RegisterRPC("services:administerBedTreatment", function(src, bedId, treatmentItem)
        return Nyx.Services.AdministerBedTreatment(bedId, treatmentItem)
    end)

    exports['nyx_core']:RegisterRPC("services:getBedTelemetry", function(src, bedId)
        local bed = Nyx.Services.HospitalBeds[bedId]
        if not bed then return nil, "BED_NOT_FOUND" end

        local patientSrc = nil
        for s, bId in pairs(Nyx.Services.OccupiedBedSources) do
            if bId == bedId then
                patientSrc = s
                break
            end
        end

        local isPowered = Nyx.Services.IsBedPowered(bedId)
        local state = patientSrc and Nyx.Services.GetPlayerTrauma(patientSrc) or nil
        return Nyx.HospitalBeds.EvaluateVitalsTelemetry(state, bed, isPowered)
    end)
end)
