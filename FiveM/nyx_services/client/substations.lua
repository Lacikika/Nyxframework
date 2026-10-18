--[[
    Nyxframework: nyx_services
    File: client/substations.lua
    Description: Physical substation maintenance points, dynamic map blips,
                 Third-Eye (LALT) target registration, circuit breaker resets, and telemetry inspection.
]]

local SubstationBlips = {}

-- Create and update dynamic map blips for all regional substations
local function setupSubstationBlips()
    local cfg = Config.PowerGrid.Blips or { Sprite = 354, Scale = 0.85, ColorOnline = 2, ColorWarning = 5, ColorBlackout = 1 }

    for subId, sub in pairs(Config.PowerGrid.Substations or {}) do
        local blip = AddBlipForCoord(sub.coords.x, sub.coords.y, sub.coords.z)
        SetBlipSprite(blip, cfg.Sprite or 354)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, cfg.Scale or 0.85)
        SetBlipColour(blip, cfg.ColorOnline or 2)
        SetBlipAsShortRange(blip, true)

        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName(sub.label or "Power Substation")
        EndTextCommandSetBlipName(blip)

        SubstationBlips[subId] = blip
    end
end

-- Refresh blip colors based on latest GlobalState or event updates
local function updateBlipStates()
    local cfg = Config.PowerGrid.Blips or { ColorOnline = 2, ColorWarning = 5, ColorBlackout = 1 }
    local substations = GlobalState.substations or {}

    for subId, blip in pairs(SubstationBlips) do
        local s = substations[subId]
        if s then
            if s.isBlackout or s.breakerTripped then
                SetBlipColour(blip, cfg.ColorBlackout or 1)
                SetBlipFlashes(blip, true)
            elseif (s.fuelLevel and s.fuelLevel <= 30.0) or (s.conditionHealth and s.conditionHealth <= 30.0) then
                SetBlipColour(blip, cfg.ColorWarning or 5)
                SetBlipFlashes(blip, false)
            else
                SetBlipColour(blip, cfg.ColorOnline or 2)
                SetBlipFlashes(blip, false)
            end
        end
    end
end

-- Register Substations with Third-Eye (LALT) Raycast Engine
CreateThread(function()
    setupSubstationBlips()

    while not exports['nyx_interact'] do
        Wait(200)
    end

    for subId, sub in pairs(Config.PowerGrid.Substations or {}) do
        exports['nyx_interact']:AddTargetCoords("substation_" .. subId, sub.maintenancePoint, 3.0, {
            options = {
                {
                    icon = "fa-solid fa-gauge-high",
                    label = "Inspect Substation Diagnostics",
                    event = "nyx:services:client:inspectSubstation",
                    args = { subId = subId },
                    canInteract = function(entity, dist)
                        return dist <= 3.0
                    end
                },
                {
                    icon = "fa-solid fa-gas-pump",
                    label = "Refuel Generator (" .. (sub.label or "Substation") .. ")",
                    event = "nyx:services:client:refuelSubstation",
                    args = { subId = subId },
                    canInteract = function(entity, dist)
                        return dist <= 3.0
                    end
                },
                {
                    icon = "fa-solid fa-wrench",
                    label = "Repair Turbine (" .. (sub.label or "Substation") .. ")",
                    event = "nyx:services:client:repairSubstation",
                    args = { subId = subId },
                    canInteract = function(entity, dist)
                        return dist <= 3.0
                    end
                },
                {
                    icon = "fa-solid fa-bolt",
                    label = "Reset Circuit Breaker",
                    event = "nyx:services:client:resetBreaker",
                    args = { subId = subId },
                    canInteract = function(entity, dist)
                        return dist <= 3.0
                    end
                }
            },
            distance = 3.0
        })
    end
end)

-- Periodically check and update map blip colors (Sleeps 10000ms idle)
CreateThread(function()
    while true do
        Wait(10000)
        updateBlipStates()
    end
end)

-- Listen for real-time grid changes to update blips immediately
RegisterNetEvent("nyx:services:client:blackoutChanged", function(data)
    Wait(500)
    updateBlipStates()
end)

-- Event handler: Inspect Diagnostics
RegisterNetEvent("nyx:services:client:inspectSubstation", function(args)
    local subId = (type(args) == "table" and args.subId) or args
    if not subId then return end

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("services:getDiagnostics", subId)
        if res and res.success and res.data then
            local d = res.data
            local statusType = (d.status == "BLACKOUT") and "error" or ((d.status == "WARNING") and "warning" or "info")
            local breakerText = d.breakerTripped and "TRIPPED (OFFLINE)" or "NORMAL (CLOSED)"

            TriggerEvent("nyx:ui:notify", {
                type = statusType,
                title = string.upper(d.label or subId),
                message = string.format("Status: %s\nFuel: %.1f%% (~%.1fh)\nTurbine: %.1f%%\nBreaker: %s\nLoad: %.1f MW\nDistricts: %s",
                    d.status, d.fuelLevel or 0.0, d.estimatedRuntimeHours or 0.0, d.conditionHealth or 0.0,
                    breakerText, d.peakLoadMw or 45.0, d.connectedDistricts or "Regional")
            })
        else
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "DIAGNOSTICS ERROR",
                message = "Unable to read substation telemetry console."
            })
        end
    end
end)

-- Event handler: Reset Circuit Breaker
RegisterNetEvent("nyx:services:client:resetBreaker", function(args)
    local subId = (type(args) == "table" and args.subId) or args
    if not subId then return end

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("services:resetBreaker", subId)
        if res and res.success then
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "BREAKER RESET",
                message = "High-voltage circuit breaker closed. Grid successfully re-energized."
            })
            updateBlipStates()
        else
            local errMsg = (res and res.error) or "UNKNOWN"
            local friendlyErrors = {
                ['BREAKER_NOT_TRIPPED'] = "Circuit breaker is already in normal operating position.",
                ['CANNOT_RESET_FUEL_DEPLETED'] = "Cannot energize: Fuel tank completely dry. Refuel first!",
                ['CANNOT_RESET_CRITICAL_DAMAGE'] = "Cannot energize: Critical mechanical damage. Repair turbine first!"
            }
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "BREAKER TRIP LOCKOUT",
                message = friendlyErrors[errMsg] or ("Failed to reset breaker: " .. tostring(errMsg))
            })
        end
    end
end)

-- Event handlers for refueling and repairs
RegisterNetEvent("nyx:services:client:refuelSubstation", function(args)
    local subId = (type(args) == "table" and args.subId) or args
    if not subId then return end

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("services:refuelSubstation", subId)
        if res and res.success then
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "REFUELED",
                message = string.format("Generator refueled. Fuel Level: %.1f%%", (res.data and res.data.fuelLevel) or 100.0)
            })
            updateBlipStates()
        else
            local err = (res and res.error) or "UNKNOWN"
            local msgs = {
                ['FUEL_TANK_FULL'] = "Fuel tank is already at 100% capacity.",
                ['NO_INDUSTRIAL_FUEL'] = "You do not have an Industrial Fuel Drum in your inventory!"
            }
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "REFUEL FAILED",
                message = msgs[err] or ("Refueling failed: " .. tostring(err))
            })
        end
    end
end)

RegisterNetEvent("nyx:services:client:repairSubstation", function(args)
    local subId = (type(args) == "table" and args.subId) or args
    if not subId then return end

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("services:repairSubstation", subId)
        if res and res.success then
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "REPAIRED",
                message = string.format("Generator turbine serviced. Condition: %.1f%%", (res.data and res.data.conditionHealth) or 100.0)
            })
            updateBlipStates()
        else
            local err = (res and res.error) or "UNKNOWN"
            local msgs = {
                ['MAINTENANCE_OPTIMAL'] = "Turbine mechanical condition is already optimal.",
                ['NO_REPAIR_KIT'] = "You do not have a Repair Kit in your inventory!"
            }
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "REPAIR FAILED",
                message = msgs[err] or ("Repair failed: " .. tostring(err))
            })
        end
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
