--[[
    Nyxframework: nyx_vehicles
    File: client/speedometer.lua
    Description: Real-time vehicle speed telemetry, zone speed limit resolution,
                 and automated ANPR / traffic radar sensor reporting.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}

local lastRadarReportTimes = {} -- [radarZoneId] = gameTimer
local REPORT_COOLDOWN_MS = 25000 -- 25s cooldown between radar trap reports for same vehicle

-- Approximate detection of current traffic zone type from player coordinates
function Nyx.Vehicles.GetCurrentZoneType(coords)
    local x, y = coords.x, coords.y

    -- Docks / Elysian Island / Port
    if y < -1800.0 and x > -500.0 and x < 1500.0 then
        return "industrial"
    end

    -- Major Highway Interstates (Del Perro Fwy, Senora Fwy, Olympic Fwy, Palomino Fwy)
    -- Fast bounding heuristic or road checks
    if y > 1500.0 or (y < -300.0 and y > -1400.0 and (x < -1000.0 or x > 800.0)) then
        return "highway"
    end

    -- Suburban / Calming (Rockford Hills, Vinewood Hills, Mirror Park)
    if (y > 150.0 and y < 1100.0 and x < -300.0 and x > -1400.0) or (x > 800.0 and y > -800.0 and y < 50.0) then
        return "school_residential"
    end

    -- Default to Urban Surface Streets
    return "urban"
end

-- Resolve active statutory speed limit for current vehicle location
function Nyx.Vehicles.GetActiveSpeedLimit(coords)
    local zType = Nyx.Vehicles.GetCurrentZoneType(coords)
    local limits = GlobalState.speedLimits or {
        urban = 45.0,
        highway = 75.0,
        industrial = 35.0,
        school_residential = 25.0
    }
    local limit = tonumber(limits[zType]) or 45.0
    return limit, zType
end

-- Background Telemetry & Radar Sensor Loop
CreateThread(function()
    while true do
        local sleep = 500
        local ped = PlayerPedId()

        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if GetPedInVehicleSeat(veh, -1) == ped then
                sleep = 250 -- Check every 250ms when driving
                local pCoords = GetEntityCoords(veh)
                local speedMph = (GetEntitySpeed(veh) * 2.236936)

                -- Check against active traffic radar zones
                local radarZones = GlobalState.radarZones
                if not radarZones and exports['nyx_mdt'] and exports['nyx_mdt'].GetRadarZones then
                    radarZones = exports['nyx_mdt']:GetRadarZones()
                end

                if radarZones and speedMph > 25.0 then
                    local now = GetGameTimer()
                    for zoneId, z in pairs(radarZones) do
                        local zCoords = z.coords or { x = 0.0, y = 0.0, z = 0.0 }
                        local rad = tonumber(z.radius) or 120.0
                        local dx = pCoords.x - zCoords.x
                        local dy = pCoords.y - zCoords.y
                        local dist = math.sqrt((dx * dx) + (dy * dy))

                        if dist <= rad then
                            local lastReport = lastRadarReportTimes[zoneId] or 0
                            if (now - lastReport) >= REPORT_COOLDOWN_MS then
                                local zType = z.zoneType or "urban"
                                local speedLimit = Nyx.Vehicles.GetActiveSpeedLimit(pCoords)
                                
                                -- Only report if exceeding buffer tolerance
                                if speedMph > (speedLimit + 5.0) then
                                    lastRadarReportTimes[zoneId] = now
                                    local plate = GetVehicleNumberPlateText(veh) or "UNKNOWN"
                                    local modelHash = GetEntityModel(veh)
                                    local modelName = GetDisplayNameFromVehicleModel(modelHash)

                                    TriggerServerEvent("nyx:mdt:server:reportRadarDetection", {
                                        plate = string.gsub(plate, "^%s*(.-)%s*$", "%1"),
                                        model = modelName,
                                        speedMph = math.floor(speedMph * 10) / 10,
                                        coords = { x = pCoords.x, y = pCoords.y, z = pCoords.z }
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- Query Current Speed & Limit Telemetry
function Nyx.Vehicles.GetCurrentSpeedAndLimit()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        return {
            inVehicle = false,
            speedMph = 0.0,
            speedLimitMph = 45.0,
            zoneType = "urban",
            isSpeeding = false,
            deltaMph = 0.0
        }
    end

    local pCoords = GetEntityCoords(veh)
    local curMph = math.floor((GetEntitySpeed(veh) * 2.236936) * 10 + 0.5) / 10
    local speedLim, zType = Nyx.Vehicles.GetActiveSpeedLimit(pCoords)
    local delta = math.floor((curMph - speedLim) * 10 + 0.5) / 10

    return {
        inVehicle = true,
        speedMph = curMph,
        speedLimitMph = speedLim,
        zoneType = zType,
        isSpeeding = (delta > 5.0),
        deltaMph = delta
    }
end

-- Command: Check Instantaneous Speed Telemetry
RegisterCommand("checkspeed", function()
    local t = Nyx.Vehicles.GetCurrentSpeedAndLimit()
    if not t.inVehicle then
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = "SEBESSÉGMÉRŐ",
            message = "Nem tartózkodsz gépjárműben."
        })
        return
    end

    local statusMsg = t.isSpeeding and string.format("GYORSGÉPJÁRMŰ (+%.1f mph)", t.deltaMph) or "Szabályos"
    TriggerEvent("nyx:ui:notify", {
        type = t.isSpeeding and "warning" or "success",
        title = string.format("SEBESSÉG: %.1f MPH", t.speedMph),
        message = string.format("Övezet: %s | Törvényes határ: %.1f mph | Állapot: %s",
            string.upper(t.zoneType), t.speedLimitMph, statusMsg),
        duration = 6000
    })
end, false)

-- Client Export
exports("GetCurrentSpeedAndLimit", function()
    return Nyx.Vehicles.GetCurrentSpeedAndLimit()
end)

exports("GetActiveSpeedLimit", function(coords)
    return Nyx.Vehicles.GetActiveSpeedLimit(coords or GetEntityCoords(PlayerPedId()))
end)
