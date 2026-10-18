--[[
    Nyxframework: nyx_services
    File: client/beds.lua
    Description: Physical hospital bed client subsystem, Third-Eye spatial interaction targets,
                 kinematic lying down animation loops, vital monitor telemetry HUD, and bed exit.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.CurrentBed = nil
Nyx.Services.CachedBeds = {}
Nyx.Services.ActiveVitals = nil

-- Animation Dictionary & Clip Constants
local BED_ANIM_DICT = "anim@gangops@morgue@table@"
local BED_ANIM_CLIP = "body_search"
local BED_FALLBACK_DICT = "amb@lo_res_idles@"
local BED_FALLBACK_CLIP = "lying_face_up_lo_res_base"

-- 1. Helper: Play Lying Down Animation
local function playBedLyingAnim(ped)
    RequestAnimDict(BED_ANIM_DICT)
    local timeout = 0
    while not HasAnimDictLoaded(BED_ANIM_DICT) and timeout < 30 do
        Wait(50)
        timeout = timeout + 1
    end

    if HasAnimDictLoaded(BED_ANIM_DICT) then
        TaskPlayAnim(ped, BED_ANIM_DICT, BED_ANIM_CLIP, 8.0, -8.0, -1, 1, 0, false, false, false)
    else
        RequestAnimDict(BED_FALLBACK_DICT)
        timeout = 0
        while not HasAnimDictLoaded(BED_FALLBACK_DICT) and timeout < 30 do
            Wait(50)
            timeout = timeout + 1
        end
        if HasAnimDictLoaded(BED_FALLBACK_DICT) then
            TaskPlayAnim(ped, BED_FALLBACK_DICT, BED_FALLBACK_CLIP, 8.0, -8.0, -1, 1, 0, false, false, false)
        end
    end
end

-- 2. Query Nearby Beds
function Nyx.Services.GetNearbyBeds(maxDist)
    maxDist = tonumber(maxDist) or 5.0
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)

    local nearby = {}
    for _, bed in pairs(Nyx.Services.CachedBeds) do
        if bed.coords then
            local dist = #(pCoords - vector3(bed.coords.x, bed.coords.y, bed.coords.z))
            if dist <= maxDist then
                table.insert(nearby, {
                    bed = bed,
                    distance = dist
                })
            end
        end
    end

    table.sort(nearby, function(a, b) return a.distance < b.distance end)
    return nearby
end

-- 3. Register Third-Eye Targets on Certified Hospital Beds
function Nyx.Services.RegisterBedInteractionTargets()
    if not exports['nyx_interact'] or not exports['nyx_interact'].AddTargetModel then
        return
    end

    local bedModels = {
        GetHashKey("v_med_bed1"),
        GetHashKey("v_med_bed2"),
        GetHashKey("prop_armychair_01")
    }

    exports['nyx_interact']:AddTargetModel(bedModels, {
        options = {
            {
                label = "Fekvés a Kórházi Ágyba / Triage Felvétel",
                icon = "fas fa-bed",
                canInteract = function(entity)
                    return Nyx.Services.CurrentBed == nil
                end,
                action = function(entity)
                    local nearby = Nyx.Services.GetNearbyBeds(3.0)
                    if #nearby > 0 then
                        local targetBed = nearby[1].bed
                        Nyx.Services.AdmitToBedClient(targetBed.bed_id or targetBed.bedId)
                    else
                        TriggerEvent("nyx:ui:notify", {
                            type = "error",
                            title = "KÓRHÁZI ÁGY",
                            message = "Nincs regisztrált klinikai ágy a közeledben."
                        })
                    end
                end
            },
            {
                label = "Ágy Fertőtlenítése & Tiszta Ágynemű",
                icon = "fas fa-pump-medical",
                canInteract = function(entity)
                    return Nyx.Services.CurrentBed == nil
                end,
                action = function(entity)
                    local nearby = Nyx.Services.GetNearbyBeds(3.0)
                    if #nearby > 0 then
                        local targetBed = nearby[1].bed
                        Nyx.Services.SanitizeBedClient(targetBed.bed_id or targetBed.bedId)
                    end
                end
            },
            {
                label = "Vitális Paraméterek & Telemetria",
                icon = "fas fa-heartbeat",
                action = function(entity)
                    local nearby = Nyx.Services.GetNearbyBeds(3.0)
                    if #nearby > 0 then
                        local targetBed = nearby[1].bed
                        Nyx.Services.ViewBedTelemetryClient(targetBed.bed_id or targetBed.bedId)
                    end
                end
            }
        },
        distance = 2.5
    })
end

-- 4. Admit to Bed Action
function Nyx.Services.AdmitToBedClient(bedId)
    if not bedId then return end

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("services:admitPatientToBed", function(success, result)
            if success and result then
                TriggerEvent("nyx:ui:notify", {
                    type = "success",
                    title = "KLINIKAI FELVÉTEL",
                    message = "Sikeresen felvéve a kórházi ágyba. Az infúzió és a vitális monitorozás aktív."
                })
            else
                local err = type(result) == "string" and result or "FELVÉTEL_SIKERTELEN"
                TriggerEvent("nyx:ui:notify", {
                    type = "error",
                    title = "FELVÉTELI HIBA",
                    message = string.format("Nem sikerült befeküdni az ágyba: %s", err)
                })
            end
        end, bedId)
    end
end

-- 5. Discharge from Bed Action
function Nyx.Services.DischargeCurrentBedClient()
    if not Nyx.Services.CurrentBed then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "KÓRHÁZI ÁGY",
            message = "Nem fekszel egyetlen kórházi ágyban sem."
        })
        return
    end

    local bedId = Nyx.Services.CurrentBed
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("services:dischargePatientFromBed", function(success, result)
            if success then
                TriggerEvent("nyx:ui:notify", {
                    type = "info",
                    title = "TÁVOZÁS",
                    message = "Sikeresen kijelentkeztél a kórházi ágyból. Az ágy fertőtlenítésre vár."
                })
            end
        end, bedId)
    end
end

-- 6. Sanitize Bed Action
function Nyx.Services.SanitizeBedClient(bedId, itemKey)
    itemKey = itemKey or "item_disinfectant"
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("services:sanitizeBed", function(success, result)
            if success then
                TriggerEvent("nyx:ui:notify", {
                    type = "success",
                    title = "FERTŐTLENÍTVE",
                    message = "A kórházi ágy fertőtlenítve és tiszta ágyneművel ellátva (100.0%)."
                })
            else
                local err = type(result) == "string" and result or "FERTŐTLENÍTÉSI_HIBA"
                TriggerEvent("nyx:ui:notify", {
                    type = "error",
                    title = "FERTŐTLENÍTÉSI HIBA",
                    message = string.format("Nem sikerült fertőtleníteni: %s", err)
                })
            end
        end, bedId, itemKey)
    end
end

-- 7. View Bed Telemetry Action
function Nyx.Services.ViewBedTelemetryClient(bedId)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("services:getBedTelemetry", function(telemetry)
            if telemetry then
                local ekgTag = telemetry.monitorOperational and telemetry.cardiacRhythm or "OFFLINE (Nincs áram)"
                TriggerEvent("nyx:ui:notify", {
                    type = telemetry.shockClass >= 3 and "error" or "info",
                    title = "VITÁLIS MONITOR",
                    message = string.format("Pulzus: %d BPM | Vérnyomás: %d/%d mmHg | SpO2: %d%% | EKG: %s | Vér: %d mL",
                        telemetry.heartRateBpm, telemetry.bloodPressureSystolic,
                        telemetry.bloodPressureDiastolic, telemetry.oxygenSaturationSpO2,
                        ekgTag, math.floor(telemetry.bloodVolume))
                })
            end
        end, bedId)
    end
end

-- 8. Network Event Listeners
RegisterNetEvent("nyx:services:client:bedAdmitted", function(data)
    if not data then return end

    Nyx.Services.CurrentBed = data.bedId
    local ped = PlayerPedId()

    if data.coords then
        local c = data.coords
        SetEntityCoords(ped, c.x, c.y, c.z + 0.35, false, false, false, true)
        SetEntityHeading(ped, c.w or 0.0)
    end

    FreezeEntityPosition(ped, true)
    playBedLyingAnim(ped)
end)

RegisterNetEvent("nyx:services:client:bedDischarged", function(data)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    Nyx.Services.CurrentBed = nil
    Nyx.Services.ActiveVitals = nil
end)

RegisterNetEvent("nyx:services:client:bedStatusUpdated", function(payload)
    if not payload or not payload.bedId then return end
    if Nyx.Services.CachedBeds[payload.bedId] then
        local b = Nyx.Services.CachedBeds[payload.bedId]
        b.maintenance_status = payload.maintenanceStatus
        b.is_occupied = payload.isOccupied and 1 or 0
        b.occupied_by_citizen_id = payload.occupiedBy
        b.bed_cleanliness = payload.cleanliness
    end
end)

RegisterNetEvent("nyx:services:client:bedVitalsTick", function(data)
    if not data or not data.vitals then return end
    Nyx.Services.ActiveVitals = data.vitals

    -- If player is lying down and somehow animation broke, re-apply
    if Nyx.Services.CurrentBed then
        local ped = PlayerPedId()
        if not IsEntityPlayingAnim(ped, BED_ANIM_DICT, BED_ANIM_CLIP, 3) and not IsEntityPlayingAnim(ped, BED_FALLBACK_DICT, BED_FALLBACK_CLIP, 3) then
            playBedLyingAnim(ped)
        end
    end
end)

-- 9. Initial Bed Registry Fetch & Interaction Initialization
CreateThread(function()
    Wait(2000)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("services:getHospitalBeds", function(beds)
            if beds and type(beds) == "table" then
                for _, b in ipairs(beds) do
                    local bId = b.bedId or b.bed_id
                    Nyx.Services.CachedBeds[bId] = b
                end
            end
        end, nil)
    end

    Nyx.Services.RegisterBedInteractionTargets()
end)

-- 10. Registered Player Commands
RegisterCommand("hospitalbeds", function()
    local nearby = Nyx.Services.GetNearbyBeds(15.0)
    if #nearby == 0 then
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = "KÓRHÁZI ÁGYAK",
            message = "Nincs klinikai ágy a közeledben (15m)."
        })
        return
    end

    print("^2=== KÖZELI KÓRHÁZI ÁGYAK ===^7")
    for _, item in ipairs(nearby) do
        local b = item.bed
        local statusText = (tonumber(b.is_occupied) == 1) and "FOGLALT" or (b.status or "TISZTA")
        print(string.format("• [%s] %s | Típus: %s | Tisztaság: %.1f%% | Táv: %.1fm | Állapot: %s",
            b.bedId or b.bed_id, b.label or "Kórházi Ágy", b.bedType or "general",
            tonumber(b.cleanliness) or 100.0, item.distance, statusText))
    end
end, false)

RegisterCommand("dischargebed", function()
    Nyx.Services.DischargeCurrentBedClient()
end, false)
