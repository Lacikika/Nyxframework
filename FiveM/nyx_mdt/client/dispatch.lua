--[[
    Nyxframework: nyx_mdt
    File: client/dispatch.lua
    Description: Zero-polling emergency dispatch alerts, blip rendering,
                 native GPS waypoint routing (SetNewWaypoint), and judicial
                 warrant live suspect tracking blips.
]]

Nyx = Nyx or {}
Nyx.MDT = Nyx.MDT or {}
local activeCallBlip = nil
local activeTrackingBlips = {} -- [warrantId] = { pointBlip = ..., radiusBlip = ..., timer = ... }

-- Clean existing 911 call blip
local function clearCallBlip()
    if activeCallBlip and DoesBlipExist(activeCallBlip) then
        RemoveBlip(activeCallBlip)
        activeCallBlip = nil
    end
end

-- Clean specific warrant tracking blips
local function clearWarrantTracking(warrantId)
    local entry = activeTrackingBlips[warrantId]
    if entry then
        if entry.pointBlip and DoesBlipExist(entry.pointBlip) then
            RemoveBlip(entry.pointBlip)
        end
        if entry.radiusBlip and DoesBlipExist(entry.radiusBlip) then
            RemoveBlip(entry.radiusBlip)
        end
        activeTrackingBlips[warrantId] = nil
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

-- ----------------------------------------------------------------------------
-- Judicial Warrant Live Suspect Tracking Dispatch Integration
-- ----------------------------------------------------------------------------

-- New Warrant Alert Broadcast from Judiciary
RegisterNetEvent("nyx:mdt:client:newWarrantAlert", function(warrant)
    TriggerEvent("nyx:ui:notify", {
        type = "warning",
        title = string.format("MDT: ÚJ BÍRÓI ELFOGATÓPARANCS [%s]", string.upper(warrant.type or "WARRANT")),
        message = string.format("Célpont: %s | Bírói Aláírás Hitelesítve.", warrant.targetCitizenId),
        duration = 8000
    })

    PlaySoundFrontend(-1, "Event_Start_Text", "GTAO_FM_Events_Soundset", true)
end)

-- Live Suspect Cellular Triangulation Tracking Ping Received
RegisterNetEvent("nyx:mdt:client:warrantTrackingPing", function(ping)
    if not ping or not ping.warrantId or not ping.coords then return end

    local wid = ping.warrantId
    clearWarrantTracking(wid)

    local coords = ping.coords
    local radius = tonumber(ping.accuracyRadius) or 35.0

    -- 1. Create Uncertainty Radius Blip (Translucent Pulsing Circle)
    local radiusBlip = AddBlipForRadius(coords.x, coords.y, coords.z, radius)
    SetBlipColour(radiusBlip, 1) -- Red
    SetBlipAlpha(radiusBlip, 90)

    -- 2. Create Center Coordinate Marker Blip
    local pointBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(pointBlip, 458) -- Cellular tracking blip icon
    SetBlipColour(pointBlip, 1)   -- Red
    SetBlipScale(pointBlip, 0.85)
    SetBlipAsShortRange(pointBlip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(string.format("Körözött Személy Ping: %s (%s)",
        ping.targetName or ping.targetCitizenId, string.upper(ping.warrantType or "WIRETAP")))
    EndTextCommandSetBlipName(pointBlip)

    activeTrackingBlips[wid] = {
        pointBlip = pointBlip,
        radiusBlip = radiusBlip,
        targetCitizenId = ping.targetCitizenId,
        receivedAt = GetGameTimer()
    }

    PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
end)

-- Clear Active Suspect Tracking Blip (Warrant Executed or Rescinded)
RegisterNetEvent("nyx:mdt:client:clearTrackingBlip", function(data)
    local wid = type(data) == "table" and data.warrantId or data
    if wid then
        clearWarrantTracking(wid)
    end
end)

-- ----------------------------------------------------------------------------
-- Dispatch Warning Overlays & ANPR Radar Trapping Listeners
-- ----------------------------------------------------------------------------
local activeWarningBlips = {} -- [warningId] = blipHandle

local function clearWarningBlip(warningId)
    local blip = activeWarningBlips[warningId]
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
        activeWarningBlips[warningId] = nil
    end
end

-- New Dispatch Warning Overlay Received (Server Push)
RegisterNetEvent("nyx:mdt:client:dispatchWarning", function(warningData)
    if not warningData then return end

    local isCritical = (warningData.severity == "critical")
    if isCritical then
        PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
    else
        PlaySoundFrontend(-1, "Event_Message_Purple", "GTAO_FM_Events_Soundset", true)
    end

    TriggerEvent("nyx:ui:notify", {
        type = isCritical and "error" or "warning",
        title = warningData.title or "MDT RIASZTÁS",
        message = warningData.description or (warningData.location or "Helyszín ismeretlen"),
        duration = isCritical and 10000 or 7000
    })

    -- Create flashing radar alert blip if valid coordinates exist
    if warningData.coords and warningData.coords.x and warningData.id then
        clearWarningBlip(warningData.id)

        local blip = AddBlipForCoord(warningData.coords.x, warningData.coords.y, warningData.coords.z or 0.0)
        SetBlipSprite(blip, 184) -- Radar / camera hazard icon
        SetBlipColour(blip, isCritical and 1 or 6) -- Red or Orange
        SetBlipScale(blip, 1.15)
        SetBlipFlashes(blip, true)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName(string.format("Traffipax: %s", warningData.plate or "Jármű"))
        EndTextCommandSetBlipName(blip)

        activeWarningBlips[warningData.id] = blip

        -- Auto-remove blip after 45 seconds to keep minimap uncluttered
        SetTimeout(45000, function()
            clearWarningBlip(warningData.id)
        end)
    end
end)

-- Dispatch Warning Updated (e.g. Acknowledged)
RegisterNetEvent("nyx:mdt:client:updateWarning", function(warningData)
    if not warningData or not warningData.id then return end
    if activeWarningBlips[warningData.id] and DoesBlipExist(activeWarningBlips[warningData.id]) then
        SetBlipFlashes(activeWarningBlips[warningData.id], false)
        SetBlipColour(activeWarningBlips[warningData.id], 5) -- Yellow (acknowledged)
    end
end)

-- Dispatch Warning Cleared
RegisterNetEvent("nyx:mdt:client:clearWarning", function(warningId)
    clearWarningBlip(tonumber(warningId))
end)

-- Command: Check Active Statutory Speed Limit in Current Zone
RegisterCommand("speedlimit", function()
    local limits = GlobalState.speedLimits or {
        urban = 45.0,
        highway = 75.0,
        industrial = 35.0,
        school_residential = 25.0
    }

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local curMph = 0.0
    if veh ~= 0 then
        curMph = math.floor((GetEntitySpeed(veh) * 2.236936) + 0.5)
    end

    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = "TÖRVÉNYES SEBESSÉGHATÁROK",
        message = string.format("Városi: %d mph | Autópálya: %d mph | Ipari: %d mph | Lakóövezeti: %d mph%s",
            math.floor(limits.urban or 45),
            math.floor(limits.highway or 75),
            math.floor(limits.industrial or 35),
            math.floor(limits.school_residential or 25),
            veh ~= 0 and string.format(" (Jelenlegi sebesség: %d mph)", curMph) or ""),
        duration = 8000
    })
end, false)

-- Command: Review Active MDT Dispatch Warnings
RegisterCommand("mdtwarnings", function()
    if not exports['nyx_core'] or not exports['nyx_core'].TriggerRPCAwait then return end
    local res = exports['nyx_core']:TriggerRPCAwait("mdt:getDispatchWarnings")
    if res and res.success and res.warnings then
        local count = #res.warnings
        if count == 0 then
            TriggerEvent("nyx:ui:notify", {
                type = "info",
                title = "MDT RIASZTÁSOK",
                message = "Nincsenek aktív figyelmeztető riasztások az egység számára."
            })
        else
            for i = 1, math.min(3, count) do
                local w = res.warnings[i]
                TriggerEvent("nyx:ui:notify", {
                    type = (w.severity == "critical") and "error" or "warning",
                    title = string.format("[%d/%d] %s", i, count, w.title),
                    message = w.description,
                    duration = 6000
                })
            end
        end
    end
end, false)

-- Resource Cleanup
AddEventHandler("onResourceStop", function(resName)
    if resName == GetCurrentResourceName() then
        clearCallBlip()
        for wid, _ in pairs(activeTrackingBlips) do
            clearWarrantTracking(wid)
        end
        for warnId, _ in pairs(activeWarningBlips) do
            clearWarningBlip(warnId)
        end
    end
end)
