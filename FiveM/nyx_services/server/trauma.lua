--[[
    Nyxframework: nyx_services
    File: server/trauma.lua
    Description: Anatomical trauma server subsystem, in-memory state tracking,
                 zero-trust field treatment execution, hemodynamics loop, and database persistence.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.TraumaStates = {}

-- 1. Helper: Generate UUID for Medical Treatment Audit Log
local function generateTreatmentUUID()
    local template = "med-xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format("%x", v)
    end)
end

-- 2. Fetch or Initialize Player Trauma State in Memory
function Nyx.Services.GetPlayerTrauma(src)
    local sourceNum = tonumber(src)
    if not sourceNum then return nil end

    if Nyx.Services.TraumaStates[sourceNum] then
        return Nyx.Services.TraumaStates[sourceNum]
    end

    local player = Nyx.GetPlayer(sourceNum)
    if not player or not player.citizenId then
        return nil
    end

    return Nyx.Services.LoadPlayerTrauma(sourceNum, player.citizenId)
end

-- 3. Database Hydration & State Persistence
function Nyx.Services.LoadPlayerTrauma(src, citizenId)
    local sourceNum = tonumber(src)
    if not citizenId then return nil end

    local row = MySQL.single.await([[
        SELECT `citizen_id`, `blood_volume_ml`, `bleeding_rate`, `pain_level`, `wounds_json`, `is_unconscious`
        FROM `nyx_medical_trauma`
        WHERE `citizen_id` = ?
    ]], { citizenId })

    local state
    if row then
        local wounds = {}
        if type(row.wounds_json) == "string" then
            local ok, parsed = pcall(json.decode, row.wounds_json)
            if ok and type(parsed) == "table" then
                wounds = parsed
            end
        elseif type(row.wounds_json) == "table" then
            wounds = row.wounds_json
        end

        state = {
            citizenId = citizenId,
            bloodVolume = tonumber(row.blood_volume_ml) or 5000,
            maxBloodVolume = 5000,
            bleedingRate = tonumber(row.bleeding_rate) or 0.0,
            painLevel = tonumber(row.pain_level) or 0,
            isUnconscious = (tonumber(row.is_unconscious) == 1),
            limbs = wounds.limbs or {
                ['head'] = Nyx.Trauma.CreateDefaultLimbState(),
                ['torso'] = Nyx.Trauma.CreateDefaultLimbState(),
                ['left_arm'] = Nyx.Trauma.CreateDefaultLimbState(),
                ['right_arm'] = Nyx.Trauma.CreateDefaultLimbState(),
                ['left_leg'] = Nyx.Trauma.CreateDefaultLimbState(),
                ['right_leg'] = Nyx.Trauma.CreateDefaultLimbState()
            }
        }
    else
        state = Nyx.Trauma.CreateInitialTraumaState()
        state.citizenId = citizenId

        MySQL.prepare.await([[
            INSERT INTO `nyx_medical_trauma`
                (`citizen_id`, `blood_volume_ml`, `bleeding_rate`, `pain_level`, `wounds_json`, `is_unconscious`)
            VALUES (?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE `citizen_id` = VALUES(`citizen_id`)
        ]], {
            citizenId,
            state.bloodVolume,
            state.bleedingRate,
            state.painLevel,
            json.encode({ limbs = state.limbs }),
            state.isUnconscious and 1 or 0
        })
    end

    Nyx.Trauma.CalculateBleedRate(state)
    Nyx.Services.TraumaStates[sourceNum] = state
    return state
end

function Nyx.Services.SavePlayerTrauma(src)
    local sourceNum = tonumber(src)
    local state = Nyx.Services.TraumaStates[sourceNum]
    if not state or not state.citizenId then return end

    pcall(function()
        MySQL.prepare.await([[
            UPDATE `nyx_medical_trauma`
            SET `blood_volume_ml` = ?,
                `bleeding_rate` = ?,
                `pain_level` = ?,
                `wounds_json` = ?,
                `is_unconscious` = ?
            WHERE `citizen_id` = ?
        ]], {
            math.floor(state.bloodVolume + 0.5),
            state.bleedingRate,
            state.painLevel,
            json.encode({ limbs = state.limbs }),
            state.isUnconscious and 1 or 0,
            state.citizenId
        })
    end)
end

-- 4. Apply In-Engine Limb Damage
function Nyx.Services.AddLimbDamage(src, limb, woundType, severity)
    local state = Nyx.Services.GetPlayerTrauma(src)
    if not state then return false, "TRAUMA_STATE_NOT_FOUND" end

    local ok, res = Nyx.Trauma.AddWound(state, limb, woundType, severity)
    if not ok then return false, res end

    -- Trigger client sync
    TriggerClientEvent("nyx:services:client:traumaSync", src, {
        bloodVolume = state.bloodVolume,
        bleedingRate = state.bleedingRate,
        painLevel = state.painLevel,
        isUnconscious = state.isUnconscious,
        limbs = state.limbs
    })

    Nyx.Services.SavePlayerTrauma(src)
    return true, res
end

-- 5. Field Stabilization & Medical Item Execution
function Nyx.Services.ApplyMedicalTreatment(medicSrc, patientSrc, targetLimb, treatmentItem)
    local mSrc = tonumber(medicSrc)
    local pSrc = tonumber(patientSrc) or mSrc
    local limb = tostring(targetLimb or "")
    local item = tostring(treatmentItem or "")

    local medicPlayer = Nyx.GetPlayer(mSrc)
    if not medicPlayer then return false, "UNAUTHENTICATED_MEDIC" end

    local patientPlayer = Nyx.GetPlayer(pSrc)
    if not patientPlayer then return false, "PATIENT_NOT_FOUND" end

    -- Distance check if treating another citizen
    if mSrc ~= pSrc then
        local medicPed = GetPlayerPed(mSrc)
        local patientPed = GetPlayerPed(pSrc)
        if medicPed and patientPed and medicPed ~= 0 and patientPed ~= 0 then
            local mCoords = GetEntityCoords(medicPed)
            local pCoords = GetEntityCoords(patientPed)
            local dist = #(vector3(mCoords.x, mCoords.y, mCoords.z) - vector3(pCoords.x, pCoords.y, pCoords.z))
            if dist > 4.0 then
                return false, "PATIENT_OUT_OF_RANGE"
            end
        end
    end

    local patientState = Nyx.Services.GetPlayerTrauma(pSrc)
    if not patientState then return false, "PATIENT_TRAUMA_STATE_NOT_FOUND" end

    -- Zero-trust pre-validation
    local canTreat, reason = Nyx.Trauma.CanTreatLimb(patientState, limb, item)
    if not canTreat then
        return false, reason
    end

    -- Verify and consume physical medical item from medic inventory
    local invId = "citizen:" .. medicPlayer.citizenId
    local removed, remErr = exports['nyx_inventory']:RemoveItem(invId, item, 1)
    if not removed then
        return false, "INSUFFICIENT_MEDICAL_ITEMS"
    end

    local bloodBefore = math.floor(patientState.bloodVolume + 0.5)

    -- Apply treatment effect
    local ok, treatRes = Nyx.Trauma.ApplyTreatment(patientState, limb, item)
    if not ok then
        -- Refund item if treatment execution failed
        exports['nyx_inventory']:AddItem(invId, item, 1)
        return false, treatRes
    end

    local bloodAfter = math.floor(patientState.bloodVolume + 0.5)
    local treatmentUUID = generateTreatmentUUID()

    -- Audit log to database
    MySQL.prepare.await([[
        INSERT INTO `nyx_medical_treatments_log`
            (`treatment_uuid`, `patient_citizen_id`, `medic_citizen_id`, `item_used`, `target_limb`, `treatment_type`, `blood_volume_before`, `blood_volume_after`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        treatmentUUID,
        patientPlayer.citizenId,
        medicPlayer.citizenId,
        item,
        limb,
        treatRes.treatmentType or "field_stabilization",
        bloodBefore,
        bloodAfter
    })

    -- Sync to patient client
    TriggerClientEvent("nyx:services:client:traumaSync", pSrc, {
        bloodVolume = patientState.bloodVolume,
        bleedingRate = patientState.bleedingRate,
        painLevel = patientState.painLevel,
        isUnconscious = patientState.isUnconscious,
        limbs = patientState.limbs
    })

    Nyx.Services.SavePlayerTrauma(pSrc)

    return true, {
        treatmentUUID = treatmentUUID,
        patientCitizenId = patientPlayer.citizenId,
        limb = limb,
        item = item,
        treatmentType = treatRes.treatmentType,
        remainingBleedRate = patientState.bleedingRate,
        bloodVolume = patientState.bloodVolume,
        shockClass = treatRes.shockClass
    }
end

-- 6. Triage & Anatomical Diagnosis
function Nyx.Services.DiagnosePatient(examinerSrc, patientSrc)
    local eSrc = tonumber(examinerSrc)
    local pSrc = tonumber(patientSrc) or eSrc

    local patientState = Nyx.Services.GetPlayerTrauma(pSrc)
    if not patientState then return false, "PATIENT_TRAUMA_STATE_NOT_FOUND" end

    local diag = Nyx.Trauma.FormatTraumaDiagnosis(patientState)
    return true, diag
end

-- 7. Complete Revival & Trauma State Reset
function Nyx.Services.ResetTraumaState(src)
    local sourceNum = tonumber(src)
    local state = Nyx.Services.GetPlayerTrauma(sourceNum)
    if not state then return end

    local freshState = Nyx.Trauma.CreateInitialTraumaState()
    freshState.citizenId = state.citizenId
    Nyx.Services.TraumaStates[sourceNum] = freshState

    TriggerClientEvent("nyx:services:client:traumaSync", sourceNum, {
        bloodVolume = freshState.bloodVolume,
        bleedingRate = freshState.bleedingRate,
        painLevel = freshState.painLevel,
        isUnconscious = freshState.isUnconscious,
        limbs = freshState.limbs
    })

    Nyx.Services.SavePlayerTrauma(sourceNum)
end

-- 8. Hemodynamic Background Simulation Loop
CreateThread(function()
    while true do
        Wait(1000) -- 1.0 second per hemodynamic tick
        for src, state in pairs(Nyx.Services.TraumaStates) do
            if state and state.bleedingRate and state.bleedingRate > 0 then
                local prevUnconscious = state.isUnconscious
                local vol, rate, isUnconscious = Nyx.Trauma.SimulateBloodTick(state, 1.0)

                -- Check if unconsciousness changed
                if isUnconscious ~= prevUnconscious then
                    TriggerClientEvent("nyx:services:client:unconsciousState", src, isUnconscious)
                end

                -- Sync to client periodically
                TriggerClientEvent("nyx:services:client:hemodynamicTick", src, {
                    bloodVolume = vol,
                    bleedingRate = rate,
                    isUnconscious = isUnconscious
                })
            end
        end
    end
end)

-- 9. Auto-Save Debounce Loop
CreateThread(function()
    while true do
        Wait(30000) -- Save trauma states every 30 seconds
        for src, _ in pairs(Nyx.Services.TraumaStates) do
            Nyx.Services.SavePlayerTrauma(src)
        end
    end
end)

-- 10. Player Connect / Disconnect Handlers
AddEventHandler("playerDropped", function()
    local src = source
    if Nyx.Services.TraumaStates[src] then
        Nyx.Services.SavePlayerTrauma(src)
        Nyx.Services.TraumaStates[src] = nil
    end
end)
