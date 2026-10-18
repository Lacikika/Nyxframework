--[[
    Nyxframework: nyx_services
    File: client/blackout.lua
    Description: Localized blackout renderer, artificial street lighting controller,
                 and disabled ATM terminal interception.
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
            coords = vector3(b.coords.x, b.coords.y, b.coords.z),
            radius = b.radius
        }
    end
end)

-- Real-time Blackout state change broadcaster
RegisterNetEvent("nyx:services:client:blackoutChanged", function(data)
    if data.isBlackout then
        ActiveBlackouts[data.substationId] = {
            coords = vector3(data.coords.x, data.coords.y, data.coords.z),
            radius = data.radius
        }
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "POWER GRID OUTAGE",
            message = "A regional electrical substation has suffered a catastrophic failure!"
        })
    else
        ActiveBlackouts[data.substationId] = nil
        TriggerEvent("nyx:ui:notify", {
            type = "success",
            title = "POWER RESTORED",
            message = "Regional electrical substation has been refueled and energized."
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

-- Public getter
function IsPlayerInBlackout()
    return isInBlackoutZone
end
