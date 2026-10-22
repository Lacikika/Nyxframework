--[[
    Nyxframework: nyx_services
    File: client/water_utility.lua
    Description: Client-side spatial interactions, target hooks via nyx_interact,
                 and UI telemetry bridge via nyx_ui for fire hydrants and water reservoirs.
]]

Nyx = Nyx or {}

-- Initialize spatial interaction points for fire hydrants and reservoirs
local function SetupWaterUtilityTargets()
    if not exports['nyx_interact'] then return end

    local hydrants = GlobalState.fireHydrants or {}
    for hydrantId, h in pairs(hydrants) do
        if h.coords then
            exports['nyx_interact']:AddTargetCoords("fire_hydrant_" .. hydrantId, vec3(h.coords.x, h.coords.y, h.coords.z), 2.5, {
                options = {
                    {
                        icon = "fa-solid fa-fire-hydrant",
                        label = string.format("Inspect Hydrant Pressure (ID: %s)", hydrantId),
                        action = function()
                            TriggerEvent("nyx_services:client:inspectHydrant", hydrantId)
                        end
                    },
                    {
                        icon = "fa-solid fa-hose",
                        label = "Connect Tender Hose / Draft Water",
                        action = function()
                            TriggerEvent("nyx_services:client:draftHydrantMenu", hydrantId)
                        end
                    }
                ],
                distance = 2.5
            })
        end
    end

    local reservoirs = GlobalState.waterReservoirs or {}
    for resId, r in pairs(reservoirs) do
        if r.coords then
            exports['nyx_interact']:AddTargetCoords("reservoir_valve_" .. resId, vec3(r.coords.x, r.coords.y, r.coords.z), 3.0, {
                options = {
                    {
                        icon = "fa-solid fa-faucet-drip",
                        label = string.format("Access Intake Valve (%s)", r.label or resId),
                        action = function()
                            TriggerEvent("nyx_services:client:openReservoirMenu", resId)
                        end
                    }
                ],
                distance = 3.0
            })
        end
    end
end

-- Event handler for inspecting hydrant status
RegisterNetEvent("nyx_services:client:inspectHydrant", function(hydrantId)
    local hydrants = GlobalState.fireHydrants or {}
    local h = hydrants[hydrantId]
    if not h then
        if exports['nyx_notify'] then
            exports['nyx_notify']:SendNotification("Hydrant telemetry unavailable.", "error")
        end
        return
    end

    local statusText = string.format("Hydrant %s | Pressure: %.1f PSI | Active: %s", hydrantId, h.pressurePsi or 0.0, h.isActive and "YES" or "NO")
    if exports['nyx_notify'] then
        exports['nyx_notify']:SendNotification(statusText, "info")
    else
        print("[Nyx:WaterUtility] " .. statusText)
    end
end)

-- Event handler for opening reservoir intake menu
RegisterNetEvent("nyx_services:client:openReservoirMenu", function(reservoirId)
    local reservoirs = GlobalState.waterReservoirs or {}
    local r = reservoirs[reservoirId]
    if not r then
        if exports['nyx_notify'] then
            exports['nyx_notify']:SendNotification("Reservoir telemetry unavailable.", "error")
        end
        return
    end

    local statusText = string.format("Reservoir: %s | Level: %.0f/%.0f L | Purity: %.1f%% | Contam: %.2f PPM",
        r.label or reservoirId, r.waterLevelLiters or 0, r.maxCapacityLiters or 0, r.purityPercentage or 100, r.contaminationPpm or 0)
    if exports['nyx_notify'] then
        exports['nyx_notify']:SendNotification(statusText, "info")
    else
        print("[Nyx:WaterUtility] " .. statusText)
    end
end)

-- Event handler for opening drafting menu
RegisterNetEvent("nyx_services:client:draftHydrantMenu", function(hydrantId)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("services:draftHydrant", function(success, res)
            if success and res then
                local msg = string.format("Drafted %sL. Reservoir Level: %sL | Pressure: %.1f PSI | Purity: %.1f%%",
                    res.litersDrawn, res.remainingLevel, res.pressurePsi, res.purity)
                if exports['nyx_notify'] then
                    exports['nyx_notify']:SendNotification(msg, "success")
                end
            else
                local err = string.format("Failed to draft from hydrant: %s", tostring(res))
                if exports['nyx_notify'] then
                    exports['nyx_notify']:SendNotification(err, "error")
                end
            end
        end, hydrantId, 500.0) -- Draft 500L standard batch
    end
end)

CreateThread(function()
    Wait(2000)
    SetupWaterUtilityTargets()
end)

RegisterNetEvent("nyx:core:client:dbReady", function()
    Wait(1000)
    SetupWaterUtilityTargets()
end)
