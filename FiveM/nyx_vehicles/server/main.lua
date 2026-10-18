--[[
    Nyxframework: nyx_vehicles
    File: server/main.lua
    Description: Core server initialization, RPC registration, debounced damage batch flush,
                 and lifecycle orchestration.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}

CreateThread(function()
    print("^4[Nyx:Vehicles]^7 Initializing Persistent Vehicle Lifecycle & Modular Systems...^7")

    -- 1. Register RPC Routes
    if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
        -- Query player's owned vehicles
        exports['nyx_core']:RegisterRPC("vehicles:getOwnedVehicles", function(src)
            local player = exports['nyx_core']:GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end
            local list = Nyx.Vehicles.GetPlayerVehicles(player.citizenId)
            return { success = true, vehicles = list }
        end)

        -- Spawn vehicle from garage
        exports['nyx_core']:RegisterRPC("vehicles:spawnVehicle", function(src, vin, coords, heading)
            local ok, res = Nyx.Vehicles.SpawnVehicle(src, vin, coords, heading)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Despawn / store vehicle to garage
        exports['nyx_core']:RegisterRPC("vehicles:despawnVehicle", function(src, vin, garageId)
            local ok, res = Nyx.Vehicles.DespawnVehicle(src, vin, garageId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Toggle remote door locks
        exports['nyx_core']:RegisterRPC("vehicles:toggleLock", function(src, vinOrNetId)
            local ok, res = Nyx.Vehicles.ToggleLock(src, vinOrNetId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Share / give key to another citizen
        exports['nyx_core']:RegisterRPC("vehicles:giveKey", function(src, targetCitId, vin, keyType)
            local ok, res = Nyx.Vehicles.GiveKey(src, targetCitId, vin, keyType)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Repair vehicle with toolkit
        exports['nyx_core']:RegisterRPC("vehicles:repairVehicle", function(src, vin)
            local ok, res = Nyx.Vehicles.RepairVehicle(src, vin, true)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Validate access and open vehicle trunk
        exports['nyx_core']:RegisterRPC("vehicles:openTrunk", function(src, netId)
            local vin = Nyx.Vehicles.ByNetId[tonumber(netId)]
            local active = vin and Nyx.Vehicles.Active[vin]

            if not active then
                return { success = false, error = "VEHICLE_NOT_FOUND" }
            end

            if active.lockState == 1 then
                return { success = false, error = "VEHICLE_LOCKED" }
            end

            local trunkId = "trunk:" .. active.plate
            return {
                success = true,
                containerId = trunkId,
                plate = active.plate,
                type = "trunk"
            }
        end)

        -- Validate access and open vehicle glovebox
        exports['nyx_core']:RegisterRPC("vehicles:openGlovebox", function(src, netId)
            local vin = Nyx.Vehicles.ByNetId[tonumber(netId)]
            local active = vin and Nyx.Vehicles.Active[vin]

            if not active then
                return { success = false, error = "VEHICLE_NOT_FOUND" }
            end

            if active.lockState == 1 then
                return { success = false, error = "VEHICLE_LOCKED" }
            end

            local gloveboxId = "glovebox:" .. active.plate
            return {
                success = true,
                containerId = gloveboxId,
                plate = active.plate,
                type = "glovebox"
            }
        end)
    end

    -- 2. Debounced Damage Snapshot Persistence Flush (Every 30s)
    CreateThread(function()
        while true do
            Wait(Config.Persistence and (Config.Persistence.DamageFlushInterval * 1000) or 30000)
            Nyx.Vehicles.FlushDamageBatch()
        end
    end)

    print("^2[Nyx:Vehicles]^7 Online and authoritative.^7")
end)

-- Receive telemetry and damage sync from active driver
RegisterNetEvent("nyx:vehicles:server:updateVehicleState", function(vin, condition, fuel, coords)
    if not vin then return end
    Nyx.Vehicles.UpdateState(vin, condition, fuel, coords)
end)
