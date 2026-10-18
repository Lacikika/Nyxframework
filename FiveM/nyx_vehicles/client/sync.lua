--[[
    Nyxframework: nyx_vehicles
    File: client/sync.lua
    Description: Client damage telemetry, flat tire deformation sampling,
                 and fuel consumption synchronization.
]]

local currentVin = nil
local currentFuel = 65.0
local lastSyncTime = 0

-- Apply persistent damage snapshot to vehicle entity
RegisterNetEvent("nyx:vehicles:client:applyVehicleState", function(data)
    local timeout = 50
    local veh = NetworkGetEntityFromNetworkId(data.netId)
    while not DoesEntityExist(veh) and timeout > 0 do
        Wait(50)
        timeout = timeout - 1
        veh = NetworkGetEntityFromNetworkId(data.netId)
    end

    if DoesEntityExist(veh) then
        local cond = data.condition or {}
        if cond.engine then SetVehicleEngineHealth(veh, tonumber(cond.engine) or 1000.0) end
        if cond.body then SetVehicleBodyHealth(veh, tonumber(cond.body) or 1000.0) end
        if cond.dirt then SetVehicleDirtLevel(veh, tonumber(cond.dirt) or 0.0) end

        -- Apply tire bursts
        if cond.tires and type(cond.tires) == "table" then
            local tireIndices = { 0, 1, 4, 5 }
            for i, idx in ipairs(tireIndices) do
                if cond.tires[i] == true then
                    SetVehicleTyreBurst(veh, idx, true, 1000.0)
                end
            end
        end

        currentFuel = tonumber(data.fuelLevel) or 65.0
        SetVehicleFuelLevel(veh, currentFuel)
    end
end)

-- Full repair event
RegisterNetEvent("nyx:vehicles:client:repairVehicle", function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(veh) then
        SetVehicleEngineHealth(veh, 1000.0)
        SetVehicleBodyHealth(veh, 1000.0)
        SetVehicleFixed(veh)
        SetVehicleDirtLevel(veh, 0.0)
    end
end)

-- Driver Telemetry & Fuel Consumption Loop (Tick rate: 1000ms idle, 100ms when driver)
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if DoesEntityExist(ped) and IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            local isDriver = (GetPedInVehicleSeat(veh, -1) == ped)

            if isDriver then
                sleep = 100
                local plate = GetVehicleNumberPlateText(veh)
                local speed = GetEntitySpeed(veh) * 3.6 -- km/h

                -- Calculate fuel burn
                local fuelBurn = (Config.Fuel and Config.Fuel.IdleBurnPerMinute or 0.02) / 600.0
                if speed > 5.0 then
                    fuelBurn = fuelBurn + ((Config.Fuel and Config.Fuel.DriveBurnMultiplier or 0.12) * (speed / 100.0)) / 100.0
                end

                currentFuel = math.max(0.0, currentFuel - fuelBurn)
                SetVehicleFuelLevel(veh, currentFuel)

                -- Stall engine if fuel empty
                if currentFuel <= 0.0 then
                    SetVehicleEngineOn(veh, false, true, true)
                end

                -- Transmit debounced telemetry every 15 seconds
                local now = GetGameTimer()
                if (now - lastSyncTime) > (Config.Fuel and (Config.Fuel.SyncIntervalSeconds * 1000) or 15000) then
                    lastSyncTime = now

                    local condition = {
                        engine = GetVehicleEngineHealth(veh),
                        body = GetVehicleBodyHealth(veh),
                        dirt = GetVehicleDirtLevel(veh),
                        tires = {
                            IsVehicleTyreBurst(veh, 0, false),
                            IsVehicleTyreBurst(veh, 1, false),
                            IsVehicleTyreBurst(veh, 4, false),
                            IsVehicleTyreBurst(veh, 5, false)
                        }
                    }

                    local c = GetEntityCoords(veh)
                    local h = GetEntityHeading(veh)
                    local coords = { x = c.x, y = c.y, z = c.z, heading = h }

                    -- Notify server with updated state
                    TriggerServerEvent("nyx:vehicles:server:updateVehicleState", plate, condition, currentFuel, coords)
                end
            end
        end

        Wait(sleep)
    end
end)
