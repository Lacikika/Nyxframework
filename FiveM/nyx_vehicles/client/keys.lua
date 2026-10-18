--[[
    Nyxframework: nyx_vehicles
    File: client/keys.lua
    Description: Key fob interactions, remote lock/unlock toggles, animations,
                 and visual indicator feedback.
]]

-- Utility: Request and play key fob anim
local function playFobAnimation()
    local ped = PlayerPedId()
    local dict = "anim@mp_player_intmenu@key_fob@"
    RequestAnimDict(dict)
    local timeout = 20
    while not HasAnimDictLoaded(dict) and timeout > 0 do
        Wait(50)
        timeout = timeout - 1
    end

    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, "fob_click", 8.0, -8.0, 1000, 49, 0, false, false, false)
    end
end

-- 1. Keybind Command: Remote Lock/Unlock (Keybind: U, 0.00 ms idle)
RegisterCommand('nyx_toggle_vehicle_lock', function()
    local ped = PlayerPedId()
    local targetVeh = nil

    if IsPedInAnyVehicle(ped, false) then
        targetVeh = GetVehiclePedIsIn(ped, false)
    else
        local pCoords = GetEntityCoords(ped)
        local closeVeh = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, Config.Access.KeyFobRange or 8.0, 0, 71)
        if DoesEntityExist(closeVeh) then
            targetVeh = closeVeh
        end
    end

    if targetVeh and DoesEntityExist(targetVeh) then
        local netId = NetworkGetNetworkIdFromEntity(targetVeh)
        playFobAnimation()

        if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
            exports['nyx_core']:TriggerRPCAwait("vehicles:toggleLock", netId)
        end
    end
end, false)

RegisterKeyMapping('nyx_toggle_vehicle_lock', 'Toggle Vehicle Lock', 'keyboard', 'U')

-- 2. Visual & Audio Lock State Feedback
RegisterNetEvent("nyx:vehicles:client:lockToggled", function(data)
    local veh = NetworkGetEntityFromNetworkId(data.netId)
    if DoesEntityExist(veh) then
        -- Play audible beep and blink vehicle hazard lights
        PlaySoundFromEntity(-1, "Remote_Control_Fob", veh, "PI_Menu_Sounds", true, 0)

        SetVehicleLights(veh, 2)
        SetVehicleIndicatorLights(veh, 0, true)
        SetVehicleIndicatorLights(veh, 1, true)
        Wait(150)
        SetVehicleLights(veh, 0)
        SetVehicleIndicatorLights(veh, 0, false)
        SetVehicleIndicatorLights(veh, 1, false)
        Wait(150)
        SetVehicleLights(veh, 2)
        SetVehicleIndicatorLights(veh, 0, true)
        SetVehicleIndicatorLights(veh, 1, true)
        Wait(150)
        SetVehicleLights(veh, 0)
        SetVehicleIndicatorLights(veh, 0, false)
        SetVehicleIndicatorLights(veh, 1, false)

        TriggerEvent("nyx:ui:notify", {
            type = data.isLocked and "warning" or "success",
            title = "VEHICLE LOCK",
            message = string.format("Vehicle [%s] %s.",
                GetVehicleNumberPlateText(veh), data.isLocked and "LOCKED" or "UNLOCKED")
        })
    end
end)
