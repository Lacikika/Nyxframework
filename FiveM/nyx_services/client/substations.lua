--[[
    Nyxframework: nyx_services
    File: client/substations.lua
    Description: Physical substation maintenance points, fuel offloading prompts,
                 and turbine repair interactions.
]]

-- Substation Interaction Thread (Adaptive: 1000ms idle, 0ms in proximity)
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local pCoords = GetEntityCoords(ped)

            for subId, sub in pairs(Config.PowerGrid.Substations or {}) do
                local dist = #(pCoords - sub.maintenancePoint)

                if dist < 15.0 then
                    sleep = 0
                    DrawMarker(1, sub.maintenancePoint.x, sub.maintenancePoint.y, sub.maintenancePoint.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 0.25, 240, 200, 50, 180, false, false, 2, false, nil, nil, false)

                    if dist <= 2.2 then
                        BeginTextCommandDisplayText("STRING")
                        local prompt = string.format("[~y~E~w~] Refuel Generator (Industrial Fuel)\n[~b~G~w~] Repair Turbine (Repair Kit)\n~s~Substation: ~g~%s~s~", sub.label)
                        AddTextComponentSubstringPlayerName(prompt)
                        SetTextFont(0)
                        SetTextScale(0.32, 0.32)
                        SetTextColour(255, 255, 255, 220)
                        SetTextCentre(true)

                        SetDrawOrigin(sub.maintenancePoint.x, sub.maintenancePoint.y, sub.maintenancePoint.z + 0.35, 0)
                        EndTextCommandDisplayText(0.0, 0.0)
                        ClearDrawOrigin()

                        if IsControlJustPressed(0, 38) then -- E key: Refuel
                            if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
                                exports['nyx_core']:TriggerServerRPC("services:refuelSubstation", subId)
                            end
                            Wait(500)
                        elseif IsControlJustPressed(0, 47) then -- G key: Repair
                            if exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
                                exports['nyx_core']:TriggerServerRPC("services:repairSubstation", subId)
                            end
                            Wait(500)
                        end
                    end
                elseif dist < 30.0 and sleep > 250 then
                    sleep = 250
                end
            end
        end

        Wait(sleep)
    end
end)
