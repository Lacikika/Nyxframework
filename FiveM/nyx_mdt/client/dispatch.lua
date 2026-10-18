--[[
    Nyxframework: nyx_mdt
    File: client/dispatch.lua
    Description: Zero-polling emergency dispatch alerts, blip rendering,
                 and native GPS waypoint routing (SetNewWaypoint).
]]

Nyx = Nyx or {}
Nyx.MDT = Nyx.MDT or {}
local activeCallBlip = nil

-- Clean existing blip
local function clearCallBlip()
    if activeCallBlip and DoesBlipExist(activeCallBlip) then
        RemoveBlip(activeCallBlip)
        activeCallBlip = nil
    end
end

-- New 911 Call Received (Server Push)
RegisterNetEvent("nyx:mdt:client:newCall", function(callData)
    TriggerEvent("nyx:ui:notify", {
        type = "warning",
        title = string.format("911 HÍVÁS [%s]", callData.code),
        message = string.format("%s @ %s", callData.title, callData.location),
        duration = 6000
    })

    PlaySoundFrontend(-1, "Event_Message_Purple", "GTAO_FM_Events_Soundset", true)
end)

-- Officer Responding to Call: Route GPS
RegisterNetEvent("nyx:mdt:client:respondCall", function(callId)
    if not exports['nyx_core'] or not exports['nyx_core'].TriggerRPCAwait then return end

    local res = exports['nyx_core']:TriggerRPCAwait("mdt:respondCall", callId)
    if res and res.success and res.coords then
        clearCallBlip()

        activeCallBlip = AddBlipForCoord(res.coords.x, res.coords.y, res.coords.z)
        SetBlipSprite(activeCallBlip, 161) -- Police badge / alert sprite
        SetBlipColour(activeCallBlip, 1)   -- Red
        SetBlipScale(activeCallBlip, 1.1)
        SetBlipRoute(activeCallBlip, true)
        SetBlipRouteColour(activeCallBlip, 1)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName("911 Segélyhívás: #" .. tostring(callId))
        EndTextCommandSetBlipName(activeCallBlip)

        SetNewWaypoint(res.coords.x, res.coords.y)

        TriggerEvent("nyx:ui:notify", {
            type = "success",
            title = "ÚTVONAL BEÁLLÍTVA",
            message = "A GPS útvonal rögzítésre került a helyszínre."
        })
    end
end)

-- Call Closed
RegisterNetEvent("nyx:mdt:client:closeCall", function(callId)
    clearCallBlip()
end)

AddEventHandler("onResourceStop", function(resName)
    if resName == GetCurrentResourceName() then
        clearCallBlip()
    end
end)
