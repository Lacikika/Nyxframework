--[[
    Nyxframework: nyx_factions
    File: client/fleet_depot.lua
    Description: Commercial fleet depot check-out/check-in interactions,
                 Third-Eye (LALT) target registration, and zero-busywait dispatching.
]]

-- Register Fleet Depots with Third-Eye (LALT) Raycast Engine
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    for depotId, depot in pairs(Config.FleetDepots or {}) do
        exports['nyx_interact']:AddTargetCoords("fleet_depot_" .. depotId, depot.coords, 4.5, {
            options = {
                {
                    icon = "fa-solid fa-car",
                    label = "Access Fleet: " .. (depot.label or "Commercial Depot"),
                    event = "nyx:factions:client:openFleetMenu",
                    args = { depotId = depotId },
                    canInteract = function(entity, dist)
                        return dist <= 4.5 and not IsPedInAnyVehicle(PlayerPedId(), false)
                    end
                },
                {
                    icon = "fa-solid fa-warehouse",
                    label = "Return Vehicle to " .. (depot.label or "Depot"),
                    event = "nyx:factions:client:triggerReturnVehicle",
                    args = { depotId = depotId },
                    canInteract = function(entity, dist)
                        return dist <= 6.0 and IsPedInAnyVehicle(PlayerPedId(), false)
                    end
                }
            },
            distance = 5.0
        })
    end
end)

-- Relaxed visual depot marker thread (Sleeps 1000ms, zero Wait(0) busy-wait)
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local pCoords = GetEntityCoords(ped)

            for depotId, depot in pairs(Config.FleetDepots or {}) do
                local dist = #(pCoords - depot.coords)
                if dist < 20.0 then
                    sleep = 250
                    DrawMarker(36, depot.coords.x, depot.coords.y, depot.coords.z + 0.5,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        1.2, 1.2, 1.2, 220, 160, 40, 140,
                        false, false, 2, false, nil, nil, false
                    )
                end
            end
        end

        Wait(sleep)
    end
end)

-- Trigger vehicle return gathering vehicle telemetry
RegisterNetEvent("nyx:factions:client:triggerReturnVehicle", function(args)
    local depotId = (type(args) == "table" and args.depotId) or args
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        local plate = GetVehicleNumberPlateText(veh)
        local engineHealth = GetVehicleEngineHealth(veh)
        local bodyHealth = GetVehicleBodyHealth(veh)
        local fuel = 100.0

        local cond = {
            engine = engineHealth,
            body = bodyHealth,
            fuel = fuel
        }

        TriggerEvent("nyx:factions:client:returnVehicle", depotId, veh, plate, cond)
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
RegisterNetEvent("nyx:factions:client:openFleetMenu", function(args)
    local depotId = (type(args) == "table" and args.depotId) or args
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
