--[[
    Nyxframework: nyx_vehicles
    File: client/tolls_and_weighing.lua
    Description: Spatial trigger zone monitoring for highway toll gantries and weigh station scale pads,
                 3-second weight stabilization checks, and NUI/HUD bridge to nyx_ui.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}
Nyx.TollsAndWeighing = Nyx.TollsAndWeighing or {}

local isCheckingScalePad = false
local scalePadHaltTimer = 0
local activeGantryCooldowns = {} -- [plazaId] = timestamp

-- Spatial Toll Gantry Zone Definitions
local TollGantries = {
    { id = "plaza_del_perro_fwy", label = "Del Perro Freeway Toll Gantry", coords = vector3(-1200.0, -1500.0, 4.0), radius = 25.0 },
    { id = "plaza_la_puerta_fwy", label = "La Puerta Freeway Toll Plaza", coords = vector3(150.0, -2200.0, 6.0), radius = 25.0 },
    { id = "plaza_palomino_fwy", label = "Palomino Freeway East Barrier", coords = vector3(2500.0, -400.0, 90.0), radius = 30.0 },
    { id = "plaza_senora_fwy", label = "Senora Freeway North Express Gantry", coords = vector3(2600.0, 4300.0, 45.0), radius = 30.0 }
}

-- Spatial Scale Pad Zone Definitions
local ScalePads = {
    { id = "scale_senora_north", label = "Senora Commercial Weigh Station", coords = vector3(2520.0, 4210.0, 45.0), radius = 12.0 },
    { id = "scale_port_south", label = "Los Santos Port Scale Pad", coords = vector3(800.0, -3000.0, 5.0), radius = 12.0 }
}

--- Trigger HUD / NUI Notification bridge to nyx_ui
local function SendHudNotification(title, message, notifyType)
    SendNUIMessage({
        action = "nyx_ui:showNotification",
        data = {
            title = title or "Tranzit Rendszer",
            message = message or "",
            type = notifyType or "info",
            duration = 5000
        }
    })
end

-- Monitor Toll Gantries and Scale Pads Spatial Triggers
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if IsPedInAnyVehicle(ped, false) and GetPedInVehicleSeat(GetVehiclePedIsIn(ped, false), -1) == ped then
            local veh = GetVehiclePedIsIn(ped, false)
            local coords = GetEntityCoords(veh)
            local speedMps = GetEntitySpeed(veh)
            local speedKmh = speedMps * 3.6
            local now = GetGameTimer()

            -- 1. Check Toll Gantries
            for _, gantry in ipairs(TollGantries) do
                local dist = #(coords - gantry.coords)
                if dist <= gantry.radius then
                    sleep = 200
                    local lastPass = activeGantryCooldowns[gantry.id] or 0
                    if (now - lastPass) > 15000 then -- 15 second cooldown per gantry pass
                        activeGantryCooldowns[gantry.id] = now
                        local plate = GetVehicleNumberPlateText(veh)
                        local vClass = GetVehicleClass(veh)

                        TriggerServerEvent("nyx_vehicles:server:processToll", gantry.id, plate, vClass)
                        SendHudNotification("Útdíj Levonás", string.format("%s automatikus útdíj áthaladás regisztrálva (%s).", gantry.label, plate), "info")
                    end
                end
            end

            -- 2. Check Weigh Station Scale Pads
            for _, pad in ipairs(ScalePads) do
                local dist = #(coords - pad.coords)
                if dist <= pad.radius then
                    sleep = 100
                    local vClass = GetVehicleClass(veh)

                    -- Requires vehicle to halt (speed < 1.0 km/h) for 3 seconds on scale pad
                    if speedKmh < 1.0 then
                        if not isCheckingScalePad then
                            isCheckingScalePad = true
                            scalePadHaltTimer = GetGameTimer()
                            SendHudNotification("Mérlegelés Folyamatban", "Maradjon mozdulatlan a mérlegpadon 3 másodpercig...", "warning")
                        else
                            local elapsed = GetGameTimer() - scalePadHaltTimer
                            if elapsed >= 3000 then
                                isCheckingScalePad = false
                                scalePadHaltTimer = GetGameTimer() + 20000 -- Cooldown

                                local plate = GetVehicleNumberPlateText(veh)
                                TriggerServerEvent("nyx_vehicles:server:inspectWeighStation", plate, vClass, false)
                                SendHudNotification("Mérlegelés Kész", "Tengelysúly és fuvarlevél ellenőrzés sikeresen lefutott.", "success")
                            end
                        end
                    else
                        if isCheckingScalePad then
                            isCheckingScalePad = false
                            SendHudNotification("Mérlegelés Megszakítva", "A jármű elmozdult a mérlegpadról!", "error")
                        end

                        -- If commercial vehicle drives through scale pad at high speed (> 25 km/h) without halting, trigger BYPASS alert
                        if (vClass == 10 or vClass == 20 or vClass == 11) and speedKmh > 25.0 then
                            local lastBypass = activeGantryCooldowns[pad.id] or 0
                            if (now - lastBypass) > 30000 then
                                activeGantryCooldowns[pad.id] = now
                                local plate = GetVehicleNumberPlateText(veh)
                                TriggerServerEvent("nyx_vehicles:server:inspectWeighStation", plate, vClass, true)
                                SendHudNotification("MÉRŐÁLLOMÁS MEGKERÜLÉSE", "Riasztás kiküldve a hatóságoknak!", "error")
                            end
                        end
                    end
                end
            end
        else
            isCheckingScalePad = false
        end

        Wait(sleep)
    end
end)
