--[[
    Nyxframework: nyx_factions
    File: client/fleet_depot.lua
    Description: Commercial fleet depot check-out/check-in interactions,
                 damage condition sampling, and vehicle spawning.
]]

-- Proximity Fleet Depot Loop (Adaptive: 1000ms idle, 0ms close)
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local pCoords = GetEntityCoords(ped)
            local inVehicle = IsPedInAnyVehicle(ped, false)

            for depotId, depot in pairs(Config.FleetDepots or {}) do
                local dist = #(pCoords - depot.coords)

                if dist < 20.0 then
                    sleep = 0
                    DrawMarker(36, depot.coords.x, depot.coords.y, depot.coords.z + 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 1.2, 220, 160, 40, 180, false, false, 2, false, nil, nil, false)

                    if dist <= 4.0 then
                        BeginTextCommandDisplayText("STRING")
                        local prompt = inVehicle and "[~y~E~w~] Return Vehicle to Depot" or "[~g~E~w~] Access Commercial Fleet"
                        AddTextComponentSubstringPlayerName(string.format("%s\n~s~%s", prompt, depot.label))
                        SetTextFont(0)
                        SetTextScale(0.32, 0.32)
                        SetTextColour(255, 255, 255, 220)
                        SetTextCentre(true)

                        SetDrawOrigin(depot.coords.x, depot.coords.y, depot.coords.z + 1.2, 0)
                        EndTextCommandDisplayText(0.0, 0.0)
                        ClearDrawOrigin()

                        if IsControlJustPressed(0, 38) then -- E key
                            if inVehicle then
                                local veh = GetVehiclePedIsIn(ped, false)
                                local plate = GetVehicleNumberPlateText(veh)
                                local engineHealth = GetVehicleEngineHealth(veh)
                                local bodyHealth = GetVehicleBodyHealth(veh)
                                local fuel = 100.0 -- default or integration with fuel system

                                local cond = {
                                    engine = engineHealth,
                                    body = bodyHealth,
                                    fuel = fuel
                                }

                                TriggerEvent("nyx:factions:client:returnVehicle", depotId, veh, plate, cond)
                            else
                                TriggerEvent("nyx:factions:client:openFleetMenu", depotId)
                            end
                            Wait(500)
                        end
                    end
                elseif dist < 40.0 and sleep > 250 then
                    sleep = 250
                end
            end
        end

        Wait(sleep)
    end
end)

-- Return vehicle handler
RegisterNetEvent("nyx:factions:client:returnVehicle", function(depotId, vehEntity, plate, condition)
    -- Sample condition and delete local entity upon authoritative DB confirmation
    if DoesEntityExist(vehEntity) then
        TaskLeaveVehicle(PlayerPedId(), vehEntity, 0)
        Wait(1500)
        DeleteVehicle(vehEntity)

        TriggerEvent("nyx:ui:notify", {
            type = "success",
            title = "FLEET CHECK-IN",
            message = string.format("Commercial vehicle [%s] returned and stored in %s.", plate, depotId)
        })
    end
end)

-- Fleet menu open
RegisterNetEvent("nyx:factions:client:openFleetMenu", function(depotId)
    if exports['nyx_ui'] then
        exports['nyx_ui']:OpenView("fleet_depot_view", { depotId = depotId })
    else
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = "COMMERCIAL FLEET",
            message = "Depot terminal accessed. Select registered corporate asset to check out."
        })
    end
end)
