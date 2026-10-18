--[[
    Nyxframework: nyx_vehicles
    File: client/keys.lua
    Description: Key fob interactions, physical ignition key checks, corporate RFID detection,
                 lockpicking mechanics, hotwiring, and alarm feedback.
]]

local isLockpicking = false
local isHotwiring = false
local lastIgnitionCheck = 0
local cachedAuthorized = {} -- [veh] = boolean

-- Utility: Request and play animation dictionary safely
local function playAnim(ped, dict, anim, duration, flag)
    RequestAnimDict(dict)
    local timeout = 20
    while not HasAnimDictLoaded(dict) and timeout > 0 do
        Wait(50)
        timeout = timeout - 1
    end

    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, duration or 1500, flag or 49, 0, false, false, false)
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
        local closeVeh = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, Config.Access and Config.Access.KeyFobRange or 8.0, 0, 71)
        if DoesEntityExist(closeVeh) then
            targetVeh = closeVeh
        end
    end

    if targetVeh and DoesEntityExist(targetVeh) then
        local netId = NetworkGetNetworkIdFromEntity(targetVeh)
        playAnim(ped, "anim@mp_player_intmenu@key_fob@", "fob_click", 1000, 49)

        if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
            exports['nyx_core']:TriggerRPCAwait("vehicles:toggleLock", netId)
        end
    end
end, false)

RegisterKeyMapping('nyx_toggle_vehicle_lock', 'Toggle Vehicle Lock', 'keyboard', 'U')

-- 2. Visual & Audio Lock State Feedback
RegisterNetEvent("nyx:vehicles:client:lockToggled", function(data)
    if not data or not data.netId then return end
    local veh = NetworkGetEntityFromNetworkId(data.netId)
    if DoesEntityExist(veh) then
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

-- 3. Vehicle Alarm Event Listener
RegisterNetEvent("nyx:vehicles:client:alarmTriggered", function(data)
    if not data or not data.netId then return end
    local veh = NetworkGetEntityFromNetworkId(data.netId)
    if DoesEntityExist(veh) then
        SetVehicleAlarm(veh, true)
        StartVehicleAlarm(veh)
        SetVehicleAlarmTimeLeft(veh, 20000) -- 20 seconds alarm

        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "SECURITY ALARM",
            message = string.format("Vehicle alarm triggered on [%s]!", data.plate or "VEHICLE")
        })
    end
end)

-- 4. Ignition Key Enforcement Thread (0.00 ms idle, checks on vehicle driver entry)
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            local isDriver = (GetPedInVehicleSeat(veh, -1) == ped)

            if isDriver and DoesEntityExist(veh) then
                local now = GetGameTimer()
                if cachedAuthorized[veh] == nil or (now - lastIgnitionCheck > 10000) then
                    lastIgnitionCheck = now
                    local netId = NetworkGetNetworkIdFromEntity(veh)

                    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
                        local res = exports['nyx_core']:TriggerRPCAwait("vehicles:checkIgnition", netId)
                        if res and res.success and res.data and res.data.authorized then
                            cachedAuthorized[veh] = true
                        else
                            cachedAuthorized[veh] = false
                        end
                    else
                        cachedAuthorized[veh] = true
                    end
                end

                if cachedAuthorized[veh] == false then
                    SetVehicleEngineOn(veh, false, true, true)
                    SetVehicleUndriveable(veh, true)
                else
                    SetVehicleUndriveable(veh, false)
                end
            end
            Wait(300)
        else
            cachedAuthorized = {}
            Wait(1000)
        end
    end
end)

-- 5. Lockpicking Interaction Command (/lockpick, /lockpickvehicle)
RegisterCommand('lockpickvehicle', function(source, args)
    if isLockpicking then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        TriggerEvent("nyx:ui:notify", { type = "error", title = "LOCKPICK", message = "Cannot pick door locks from inside." })
        return
    end

    local pCoords = GetEntityCoords(ped)
    local closeVeh = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 2.5, 0, 71)
    if not DoesEntityExist(closeVeh) then
        TriggerEvent("nyx:ui:notify", { type = "warning", title = "LOCKPICK", message = "No vehicle nearby to lockpick." })
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(closeVeh)
    local useGloves = (args[1] == "gloves" or args[1] == "true")

    isLockpicking = true
    TriggerEvent("nyx:ui:notify", { type = "info", title = "LOCKPICK", message = "Bypassing vehicle tumbler locks..." })

    playAnim(ped, "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", "machinic_loop_mechandplayer", 4500, 49)
    Wait(4500)
    ClearPedTasks(ped)
    isLockpicking = false

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("vehicles:attemptLockpick", netId, useGloves)
        if res and res.success and res.data then
            local d = res.data
            if d.unlocked then
                TriggerEvent("nyx:ui:notify", { type = "success", title = "LOCKPICK SUCCESS", message = "Vehicle lock bypassed!" })
            else
                TriggerEvent("nyx:ui:notify", { type = "error", title = "LOCKPICK FAILED", message = "Failed to pick tumbler pins." })
            end

            if d.toolBroken then
                TriggerEvent("nyx:ui:notify", { type = "warning", title = "TOOL BROKEN", message = "Your lockpick snapped inside the cylinder!" })
            end

            if d.alarmTriggered then
                TriggerEvent("nyx:ui:notify", { type = "error", title = "ALARM TRIPPED", message = "Security siren alerted!" })
            end
        else
            local err = (res and res.error) or "Lockpick attempt aborted."
            TriggerEvent("nyx:ui:notify", { type = "error", title = "LOCKPICK", message = err })
        end
    end
end, false)

RegisterCommand('lockpick', function(source, args)
    ExecuteCommand('lockpickvehicle ' .. (args[1] or ""))
end, false)

-- 6. Hotwiring Interaction Command (/hotwire)
RegisterCommand('hotwire', function(source, args)
    if isHotwiring then return end
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        TriggerEvent("nyx:ui:notify", { type = "warning", title = "HOTWIRE", message = "You must be inside a vehicle to hotwire ignition." })
        return
    end

    local veh = GetVehiclePedIsIn(ped, false)
    if GetPedInVehicleSeat(veh, -1) ~= ped then
        TriggerEvent("nyx:ui:notify", { type = "error", title = "HOTWIRE", message = "You must be in the driver seat." })
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    local useGloves = (args[1] == "gloves" or args[1] == "true")

    isHotwiring = true
    TriggerEvent("nyx:ui:notify", { type = "info", title = "HOTWIRE", message = "Stripping ignition column wiring harness..." })

    playAnim(ped, "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", "machinic_loop_mechandplayer", 5000, 49)
    Wait(5000)
    ClearPedTasks(ped)
    isHotwiring = false

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("vehicles:attemptHotwire", netId, useGloves)
        if res and res.success and res.data then
            local d = res.data
            if d.hotwired then
                cachedAuthorized[veh] = true
                SetVehicleUndriveable(veh, false)
                SetVehicleEngineOn(veh, true, true, false)
                TriggerEvent("nyx:ui:notify", { type = "success", title = "HOTWIRE SUCCESS", message = "Engine ignition sparked to life!" })
            else
                TriggerEvent("nyx:ui:notify", { type = "error", title = "HOTWIRE FAILED", message = "Wiring crossed; starter failed." })
            end

            if d.alarmTriggered then
                TriggerEvent("nyx:ui:notify", { type = "error", title = "SECURITY ALERT", message = "Vehicle alarm triggered!" })
            end
        else
            local err = (res and res.error) or "Hotwire attempt aborted."
            TriggerEvent("nyx:ui:notify", { type = "error", title = "HOTWIRE", message = err })
        end
    end
end, false)

-- Hotwire quick-key mapping [H] while in driver seat
RegisterKeyMapping('hotwire', 'Hotwire Vehicle Ignition', 'keyboard', 'H')
