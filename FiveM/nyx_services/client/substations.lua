--[[
    Nyxframework: nyx_services
    File: client/substations.lua
    Description: Physical substation maintenance points, Third-Eye (LALT) target registration,
                 and zero-busywait interaction dispatching.
]]

-- Register Substations with Third-Eye (LALT) Raycast Engine
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    for subId, sub in pairs(Config.PowerGrid.Substations or {}) do
        exports['nyx_interact']:AddTargetCoords("substation_" .. subId, sub.maintenancePoint, 2.5, {
            options = {
                {
                    icon = "fa-solid fa-gas-pump",
                    label = "Refuel Generator (" .. (sub.label or "Substation") .. ")",
                    event = "nyx:services:client:refuelSubstation",
                    args = { subId = subId },
                    canInteract = function(entity, dist)
                        return dist <= 2.5
                    end
                },
                {
                    icon = "fa-solid fa-wrench",
                    label = "Repair Turbine (" .. (sub.label or "Substation") .. ")",
                    event = "nyx:services:client:repairSubstation",
                    args = { subId = subId },
                    canInteract = function(entity, dist)
                        return dist <= 2.5
                    end
                }
            },
            distance = 2.5
        })
    end
end)

-- Event handlers for substation interactions
RegisterNetEvent("nyx:services:client:refuelSubstation", function(args)
    local subId = (type(args) == "table" and args.subId) or args
    if subId and exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        exports['nyx_core']:TriggerServerRPC("services:refuelSubstation", subId)
    end
end)

RegisterNetEvent("nyx:services:client:repairSubstation", function(args)
    local subId = (type(args) == "table" and args.subId) or args
    if subId and exports['nyx_core'] and exports['nyx_core'].TriggerServerRPC then
        exports['nyx_core']:TriggerServerRPC("services:repairSubstation", subId)
    end
end)

-- Relaxed visual beacon thread (Sleeps 1000ms, zero Wait(0) busy-wait)
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local pCoords = GetEntityCoords(ped)

            for subId, sub in pairs(Config.PowerGrid.Substations or {}) do
                local dist = #(pCoords - sub.maintenancePoint)
                if dist < 15.0 then
                    sleep = 250
                    DrawMarker(1, sub.maintenancePoint.x, sub.maintenancePoint.y, sub.maintenancePoint.z - 0.95,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        1.2, 1.2, 0.25, 240, 200, 50, 140,
                        false, false, 2, false, nil, nil, false
                    )
                end
            end
        end

        Wait(sleep)
    end
end)
