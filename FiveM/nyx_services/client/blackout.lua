--[[
    Nyxframework: nyx_services
    File: client/blackout.lua
    Description: Localized blackout renderer, artificial street lighting controller,
                 spark/explosion audiovisual cues, and disabled terminal interception.
]]

local ActiveBlackouts = {}
local isInBlackoutZone = false

-- Synchronize initial blackout state on spawn
CreateThread(function()
    Wait(2000)
    TriggerServerEvent("nyx:services:server:requestGridSync")
end)

RegisterNetEvent("nyx:services:client:initialGridSync", function(blackoutList)
    ActiveBlackouts = {}
    for _, b in ipairs(blackoutList or {}) do
        ActiveBlackouts[b.substationId] = {
            substationId = b.substationId,
            coords = vector3(b.coords.x, b.coords.y, b.coords.z),
            radius = b.radius,
            reason = b.reason or "system_failure"
        }
    end
end)

-- Play localized electrical sparks and explosion sounds at failing transformer
local function playTransformerFailureEffects(coords)
    if not coords then return end
    local pCoords = GetEntityCoords(PlayerPedId())
    local dist = #(pCoords - coords)

    if dist < 450.0 then
        -- Play sound effect
        PlaySoundFromCoord(-1, "DISTANT_EXPLOSION", coords.x, coords.y, coords.z, "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", false, 0, false)

        -- Spawn electrical spark particles
        RequestNamedPtfxAsset("core")
        local timeout = 0
        while not HasNamedPtfxAssetLoaded("core") and timeout < 20 do
            Wait(50)
            timeout = timeout + 1
        end

        if HasNamedPtfxAssetLoaded("core") then
            UseParticleFxAssetNextCall("core")
            StartParticleFxNonLoopedAtCoord("sparks", coords.x, coords.y, coords.z + 2.0,
                0.0, 0.0, 0.0, 2.5, false, false, false
            )
        end
    end
end

-- Real-time Blackout state change broadcaster
RegisterNetEvent("nyx:services:client:blackoutChanged", function(data)
    if data.isBlackout then
        ActiveBlackouts[data.substationId] = {
            substationId = data.substationId,
            coords = vector3(data.coords.x, data.coords.y, data.coords.z),
            radius = data.radius,
            reason = data.reason or "system_failure"
        }

        if data.transformerCoords then
            local tVec = vector3(data.transformerCoords.x, data.transformerCoords.y, data.transformerCoords.z)
            playTransformerFailureEffects(tVec)
        end

        local reasonLabels = {
            ['fuel_exhaustion'] = "Fuel Reserves Exhausted",
            ['mechanical_breakdown'] = "Turbine Structural Failure",
            ['overload_trip'] = "Grid Overload - Breaker Tripped",
            ['sabotage'] = "Physical Sabotage / Breached Generator",
            ['admin_simulation'] = "Municipal Power Outage Drill"
        }
        local reasonText = reasonLabels[data.reason] or (data.reason or "Power Grid Outage")

        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "POWER GRID OUTAGE",
            message = string.format("Regional substation '%s' failed! Cause: %s",
                data.label or data.substationId, reasonText)
        })
    else
        ActiveBlackouts[data.substationId] = nil

        TriggerEvent("nyx:ui:notify", {
            type = "success",
            title = "POWER RESTORED",
            message = string.format("Regional substation '%s' re-energized and online.",
                data.label or data.substationId)
        })
    end
end)

-- 1. Blackout Spatial Boundary Evaluation (Tick rate: 1000ms idle)
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local pCoords = GetEntityCoords(ped)
            local insideAny = false

            for _, b in pairs(ActiveBlackouts) do
                local dist = #(pCoords - b.coords)
                if dist <= b.radius then
                    insideAny = true
                    break
                end
            end

            if insideAny and not isInBlackoutZone then
                isInBlackoutZone = true
                -- Cut ambient world lights & streetlights (keep vehicle headlights operational)
                SetArtificialLightsState(true)
                SetArtificialLightsStateAffectsVehicles(false)
            elseif not insideAny and isInBlackoutZone then
                isInBlackoutZone = false
                SetArtificialLightsState(false)
            end
        end

        Wait(1000)
    end
end)

-- 2. ATM Proximity Interception in Blackout Zones (Tick rate: 1000ms, 0ms near ATM in blackout)
local ATM_MODELS = {
    `prop_atm_01`, `prop_atm_02`, `prop_atm_03`, `prop_fleeca_atm`
}

local lastAtmAlertTime = 0

CreateThread(function()
    while true do
        Wait(1000)
        if isInBlackoutZone then
            local ped = PlayerPedId()
            if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                local pCoords = GetEntityCoords(ped)
                local now = GetGameTimer()

                if (now - lastAtmAlertTime) > 10000 then
                    for _, model in ipairs(ATM_MODELS) do
                        local obj = GetClosestObjectOfType(pCoords.x, pCoords.y, pCoords.z, 2.0, model, false, false, false)
                        if DoesEntityExist(obj) and #(pCoords - GetEntityCoords(obj)) <= 1.8 then
                            lastAtmAlertTime = now
                            TriggerEvent("nyx:ui:notify", {
                                type = "warning",
                                title = "ATM OFFLINE",
                                message = "Regional electrical grid outage: Terminal power disabled."
                            })
                            break
                        end
                    end
                end
            end
        end
    end
end)

-- Public getters & spatial queries
function IsPlayerInBlackout()
    return isInBlackoutZone
end

function IsCoordsPowered(coords)
    if not coords then return true, nil end
    local targetVec = vector3(coords.x, coords.y, coords.z)

    for subId, b in pairs(ActiveBlackouts) do
        local dist = #(targetVec - b.coords)
        if dist <= b.radius then
            return false, subId
        end
    end

    return true, nil
end

function GetActiveBlackouts()
    return ActiveBlackouts
end
