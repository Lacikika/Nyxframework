--[[
    Nyxframework: nyx_vehicles
    File: client/wear.lua
    Description: Real-time vehicle mileage (odometer) sampling, driving wear
                 mechanics (oil, brakes, transmission, suspension), dynamic handling
                 penalties, and debounced telemetry synchronization.
]]

local currentVeh = 0
local currentPlate = nil
local lastCoords = nil
local lastGear = 1
local lastSync = 0

-- Client Wear State
local currentWear = {
    mileage = 0.0,
    tripOdometer = 0.0,
    oilQuality = 100.0,
    brakePadWear = 100.0,
    transmissionWear = 100.0,
    suspensionWear = 100.0,
    lastServiceMileage = 0.0
}

-- Accumulators for debounced push to server
local accumulatedKm = 0.0
local accumulatedDeltas = {
    oil = 0.0,
    brakes = 0.0,
    transmission = 0.0,
    suspension = 0.0
}

-- 1. Receive wear snapshot from server
RegisterNetEvent("nyx:vehicles:client:syncWearSnapshot", function(netId, wearData)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh == currentVeh and wearData then
        currentWear.mileage = tonumber(wearData.mileage) or currentWear.mileage
        currentWear.tripOdometer = tonumber(wearData.tripOdometer) or currentWear.tripOdometer
        currentWear.oilQuality = tonumber(wearData.oilQuality) or currentWear.oilQuality
        currentWear.brakePadWear = tonumber(wearData.brakePadWear) or currentWear.brakePadWear
        currentWear.transmissionWear = tonumber(wearData.transmissionWear) or currentWear.transmissionWear
        currentWear.suspensionWear = tonumber(wearData.suspensionWear) or currentWear.suspensionWear
    end
end)

-- Hook wear snapshot when vehicle is initially spawned or loaded
AddEventHandler("nyx:vehicles:client:onWearApplied", function(wearData)
    if wearData and type(wearData) == "table" then
        currentWear.mileage = tonumber(wearData.mileage) or 0.0
        currentWear.tripOdometer = tonumber(wearData.tripOdometer) or 0.0
        currentWear.oilQuality = tonumber(wearData.oilQuality) or 100.0
        currentWear.brakePadWear = tonumber(wearData.brakePadWear) or 100.0
        currentWear.transmissionWear = tonumber(wearData.transmissionWear) or 100.0
        currentWear.suspensionWear = tonumber(wearData.suspensionWear) or 100.0
        currentWear.lastServiceMileage = tonumber(wearData.lastServiceMileage) or 0.0
    end
end)

-- 2. Telemetry and Driving Wear Sampling Loop
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if DoesEntityExist(ped) and IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            local isDriver = (GetPedInVehicleSeat(veh, -1) == ped)

            if isDriver then
                sleep = 250
                local plate = GetVehicleNumberPlateText(veh)
                local coords = GetEntityCoords(veh)
                local speedKmh = GetEntitySpeed(veh) * 3.6
                local rpm = GetVehicleCurrentRpm(veh)
                local gear = GetVehicleCurrentGear(veh)

                -- If switched vehicles, request fresh wear data from server
                if veh ~= currentVeh or plate ~= currentPlate then
                    currentVeh = veh
                    currentPlate = plate
                    lastCoords = coords
                    lastGear = gear
                    accumulatedKm = 0.0
                    accumulatedDeltas = { oil = 0.0, brakes = 0.0, transmission = 0.0, suspension = 0.0 }

                    -- Query wear via RPC
                    if exports['nyx_core'] and exports['nyx_core'].CallRPC then
                        CreateThread(function()
                            local ok, res = pcall(function()
                                return exports['nyx_core']:CallRPC("vehicles:getWear", plate)
                            end)
                            if ok and res and res.success and res.wear then
                                TriggerEvent("nyx:vehicles:client:onWearApplied", res.wear)
                            end
                        end)
                    end
                end

                -- Compute distance traveled
                if lastCoords then
                    local distMeters = #(coords - lastCoords)
                    -- Discard micro vibrations (<0.15m) and teleport spikes (>250m)
                    if distMeters >= 0.15 and distMeters <= 250.0 then
                        local deltaKm = distMeters / 1000.0
                        accumulatedKm = accumulatedKm + deltaKm
                        currentWear.mileage = currentWear.mileage + deltaKm
                        currentWear.tripOdometer = currentWear.tripOdometer + deltaKm

                        -- Oil wear: baseline per km + RPM multiplier
                        local oilLoss = deltaKm * ((Config.Wear and Config.Wear.OilDegradationPerKm) or 0.04)
                        if rpm > 0.85 then
                            oilLoss = oilLoss * ((Config.Wear and Config.Wear.OilRpmMultiplier) or 2.5)
                        end
                        accumulatedDeltas.oil = accumulatedDeltas.oil + oilLoss
                        currentWear.oilQuality = math.max(0.0, currentWear.oilQuality - oilLoss)

                        -- Suspension wear: road baseline + offroad detection
                        local suspLoss = deltaKm * ((Config.Wear and Config.Wear.SuspensionWearPerKm) or 0.025)
                        local wheelSurface = GetVehicleWheelSurfaceMaterial(veh, 0)
                        -- 1: tarmac, 2: concrete, higher IDs / flags often represent dirt/grass/gravel
                        local isOffroad = (wheelSurface and wheelSurface > 3) or not IsVehicleOnAllWheels(veh)
                        if isOffroad then
                            suspLoss = suspLoss * ((Config.Wear and Config.Wear.SuspensionOffroadMultiplier) or 3.5)
                        end
                        accumulatedDeltas.suspension = accumulatedDeltas.suspension + suspLoss
                        currentWear.suspensionWear = math.max(0.0, currentWear.suspensionWear - suspLoss)
                    end
                end
                lastCoords = coords

                -- Brake Pad Wear: active deceleration while moving
                local isBraking = (GetControlNormal(0, 72) > 0.1) or IsControlPressed(0, 76) -- Brake or Handbrake
                if isBraking and speedKmh > 5.0 then
                    local dt = 0.25 -- 250ms interval
                    local brakeLoss = dt * ((Config.Wear and Config.Wear.BrakeWearPerBrakeSecond) or 0.006)
                    if speedKmh > 80.0 then
                        brakeLoss = brakeLoss * ((Config.Wear and Config.Wear.BrakeHardStopMultiplier) or 1.8)
                    end
                    accumulatedDeltas.brakes = accumulatedDeltas.brakes + brakeLoss
                    currentWear.brakePadWear = math.max(0.0, currentWear.brakePadWear - brakeLoss)
                end

                -- Transmission Wear: gear changes & aggressive burnouts
                if gear ~= lastGear then
                    lastGear = gear
                    local transLoss = (Config.Wear and Config.Wear.TransmissionWearPerShift) or 0.002
                    accumulatedDeltas.transmission = accumulatedDeltas.transmission + transLoss
                    currentWear.transmissionWear = math.max(0.0, currentWear.transmissionWear - transLoss)
                end

                if IsVehicleInBurnout(veh) then
                    local burnoutLoss = (Config.Wear and Config.Wear.TransmissionBurnoutPenalty) or 0.015
                    accumulatedDeltas.transmission = accumulatedDeltas.transmission + (burnoutLoss * 0.25)
                    currentWear.transmissionWear = math.max(0.0, currentWear.transmissionWear - (burnoutLoss * 0.25))
                end

                -- Push debounced telemetry to server every 15s
                local now = GetGameTimer()
                local syncInterval = (Config.Wear and Config.Wear.SyncIntervalSeconds and (Config.Wear.SyncIntervalSeconds * 1000)) or 15000
                if (now - lastSync) > syncInterval then
                    lastSync = now
                    if accumulatedKm > 0.0 or accumulatedDeltas.oil > 0.0 or accumulatedDeltas.brakes > 0.0 then
                        TriggerServerEvent("nyx:vehicles:server:updateVehicleWear", plate, accumulatedKm, accumulatedDeltas)
                        accumulatedKm = 0.0
                        accumulatedDeltas = { oil = 0.0, brakes = 0.0, transmission = 0.0, suspension = 0.0 }
                    end
                end
            end
        else
            if currentVeh ~= 0 then
                -- Player left vehicle; flush remaining accumulated deltas if any
                if currentPlate and (accumulatedKm > 0.0 or accumulatedDeltas.oil > 0.0) then
                    TriggerServerEvent("nyx:vehicles:server:updateVehicleWear", currentPlate, accumulatedKm, accumulatedDeltas)
                end
                currentVeh = 0
                currentPlate = nil
                lastCoords = nil
                accumulatedKm = 0.0
                accumulatedDeltas = { oil = 0.0, brakes = 0.0, transmission = 0.0, suspension = 0.0 }
            end
        end

        Wait(sleep)
    end
end)

-- 3. Mechanical Degradation & Physical Penalties Loop
CreateThread(function()
    while true do
        local sleep = 1000

        if currentVeh ~= 0 and DoesEntityExist(currentVeh) then
            local ped = PlayerPedId()
            if GetPedInVehicleSeat(currentVeh, -1) == ped then
                sleep = 500
                local speedKmh = GetEntitySpeed(currentVeh) * 3.6

                -- Degradation: Critical Engine Oil (<10% warning, <5% engine health decay)
                if currentWear.oilQuality <= 5.0 and speedKmh > 5.0 then
                    local curHealth = GetVehicleEngineHealth(currentVeh)
                    local decay = (Config.Wear and Config.Wear.Degradation and Config.Wear.Degradation.EngineDamageRateCriticalOil) or 0.75
                    SetVehicleEngineHealth(currentVeh, math.max(0.0, curHealth - decay))
                end

                -- Degradation: Critical Brake Pads (<10% causes weak braking)
                if currentWear.brakePadWear <= 10.0 and (GetControlNormal(0, 72) > 0.1) then
                    -- Slight forward push to counteract braking force when pads are completely degraded
                    local mult = (Config.Wear and Config.Wear.Degradation and Config.Wear.Degradation.ReducedBrakeForceMultiplier) or 0.45
                    if speedKmh > 10.0 then
                        local fwd = GetEntityForwardVector(currentVeh)
                        ApplyForceToEntityCenterOfMass(currentVeh, 1, fwd.x * 0.15, fwd.y * 0.15, 0.0, true, false, true, true)
                    end
                end

                -- Degradation: Critical Transmission (<15% causes gear slippage under hard acceleration)
                if currentWear.transmissionWear <= 15.0 and GetControlNormal(0, 71) > 0.8 then
                    local slipChance = (Config.Wear and Config.Wear.Degradation and Config.Wear.Degradation.TransmissionSlipChance) or 0.15
                    if math.random() < slipChance then
                        -- Momentary clutch slip / power loss
                        SetVehicleCheatPowerIncrease(currentVeh, 0.0)
                        SetVehicleCurrentRpm(currentVeh, 0.2)
                    end
                end

                -- Degradation: Critical Suspension (<15% creates chassis wobble at highway speeds)
                if currentWear.suspensionWear <= 15.0 and speedKmh > 70.0 then
                    if math.random() < 0.2 then
                        local wobbleX = (math.random() - 0.5) * 0.05
                        ApplyForceToEntity(currentVeh, 3, wobbleX, 0.0, 0.02, 0.0, 0.0, 0.0, 0, true, true, true, false, true)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- 4. In-Game Commands and Status Displays
RegisterCommand("odometer", function()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "Odometer",
            message = "You must be inside a vehicle to inspect the odometer."
        })
        return
    end

    local veh = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlateText(veh)

    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = string.format("Odometer: %s", plate),
        message = string.format("Mileage: %.1f km | Trip: %.1f km | Oil: %.0f%% | Brakes: %.0f%%",
            currentWear.mileage, currentWear.tripOdometer, currentWear.oilQuality, currentWear.brakePadWear)
    })
end, false)

RegisterCommand("vehstatus", function()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "Vehicle Diagnostics",
            message = "You must be inside a vehicle to inspect diagnostic status."
        })
        return
    end

    local veh = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlateText(veh)
    local engineHealth = GetVehicleEngineHealth(veh)

    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = string.format("Diagnostics: %s", plate),
        message = string.format("Total: %.1f km (Trip: %.1f km)\nEngine: %.0f/1000 | Oil: %.1f%%\nBrakes: %.1f%% | Transmission: %.1f%%\nSuspension: %.1f%%",
            currentWear.mileage, currentWear.tripOdometer, engineHealth, currentWear.oilQuality,
            currentWear.brakePadWear, currentWear.transmissionWear, currentWear.suspensionWear)
    })
end, false)

RegisterCommand("resettrip", function()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end

    local veh = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlateText(veh)

    if exports['nyx_core'] and exports['nyx_core'].CallRPC then
        local res = exports['nyx_core']:CallRPC("vehicles:resetTrip", plate)
        if res and res.success then
            currentWear.tripOdometer = 0.0
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "Trip Odometer",
                message = "Trip odometer reset to 0.0 km."
            })
        end
    end
end, false)

-- Client Exports
exports("GetVehicleMileage", function()
    return currentWear.mileage
end)

exports("GetVehicleTrip", function()
    return currentWear.tripOdometer
end)

exports("GetVehicleWear", function()
    return {
        mileage = currentWear.mileage,
        tripOdometer = currentWear.tripOdometer,
        oilQuality = currentWear.oilQuality,
        brakePadWear = currentWear.brakePadWear,
        transmissionWear = currentWear.transmissionWear,
        suspensionWear = currentWear.suspensionWear,
        lastServiceMileage = currentWear.lastServiceMileage
    }
end)
