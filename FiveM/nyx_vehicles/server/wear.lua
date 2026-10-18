--[[
    Nyxframework: nyx_vehicles
    File: server/wear.lua
    Description: Authoritative vehicle mileage tracking (odometer), component
                 wear simulation (oil, brakes, transmission, suspension),
                 batch persistence flush, and certified mechanic servicing.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}
Nyx.Vehicles.WearCache = {}
Nyx.Vehicles.DirtyWear = {}
Nyx.Vehicles.LastWearUpdate = {}

-- Helper: Normalize VIN or Plate or NetId
function Nyx.Vehicles.ResolveVIN(identifier)
    if not identifier then return nil end

    -- Check if directly a known VIN
    if type(identifier) == "string" and Nyx.Vehicles.Active[identifier] then
        return identifier
    end

    -- Check if NetId (number or numeric string)
    local netId = tonumber(identifier)
    if netId and Nyx.Vehicles.ByNetId[netId] then
        return Nyx.Vehicles.ByNetId[netId]
    end

    -- Check if Plate
    if type(identifier) == "string" and Nyx.Vehicles.ByPlate[identifier] then
        return Nyx.Vehicles.ByPlate[identifier]
    end

    -- If string matches standard VIN format
    if type(identifier) == "string" and #identifier >= 12 then
        return identifier
    end

    return nil
end

-- 1. Load wear snapshot from database or initialize default
function Nyx.Vehicles.LoadWear(vin, plate)
    if not vin then return nil end

    if Nyx.Vehicles.WearCache[vin] then
        return Nyx.Vehicles.WearCache[vin]
    end

    local row = MySQL.single.await([[
        SELECT `vin`, `plate`, `mileage`, `trip_odometer`, `oil_quality`,
               `brake_pad_wear`, `transmission_wear`, `suspension_wear`,
               `last_service_mileage`, `service_notes`
        FROM `nyx_vehicles_wear`
        WHERE `vin` = ?
    ]], { vin })

    if row then
        Nyx.Vehicles.WearCache[vin] = {
            vin = row.vin,
            plate = row.plate or plate,
            mileage = tonumber(row.mileage) or 0.0,
            tripOdometer = tonumber(row.trip_odometer) or 0.0,
            oilQuality = tonumber(row.oil_quality) or 100.0,
            brakePadWear = tonumber(row.brake_pad_wear) or 100.0,
            transmissionWear = tonumber(row.transmission_wear) or 100.0,
            suspensionWear = tonumber(row.suspension_wear) or 100.0,
            lastServiceMileage = tonumber(row.last_service_mileage) or 0.0,
            serviceNotes = row.service_notes
        }
    else
        local defaultWear = {
            vin = vin,
            plate = plate or "UNKNOWN",
            mileage = 0.0,
            tripOdometer = 0.0,
            oilQuality = 100.0,
            brakePadWear = 100.0,
            transmissionWear = 100.0,
            suspensionWear = 100.0,
            lastServiceMileage = 0.0,
            serviceNotes = "Factory delivery inspection passed"
        }

        MySQL.prepare([[
            INSERT INTO `nyx_vehicles_wear`
            (`vin`, `plate`, `mileage`, `trip_odometer`, `oil_quality`, `brake_pad_wear`,
             `transmission_wear`, `suspension_wear`, `last_service_mileage`, `service_notes`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE `plate` = VALUES(`plate`)
        ]], {
            defaultWear.vin,
            defaultWear.plate,
            defaultWear.mileage,
            defaultWear.tripOdometer,
            defaultWear.oilQuality,
            defaultWear.brakePadWear,
            defaultWear.transmissionWear,
            defaultWear.suspensionWear,
            defaultWear.lastServiceMileage,
            defaultWear.serviceNotes
        })

        Nyx.Vehicles.WearCache[vin] = defaultWear
    end

    return Nyx.Vehicles.WearCache[vin]
end

-- 2. Query wear data for vehicle
function Nyx.Vehicles.GetWear(vinOrIdentifier)
    local vin = Nyx.Vehicles.ResolveVIN(vinOrIdentifier)
    if not vin then return nil end

    if Nyx.Vehicles.WearCache[vin] then
        return Nyx.Vehicles.WearCache[vin]
    end

    local active = Nyx.Vehicles.Active[vin]
    return Nyx.Vehicles.LoadWear(vin, active and active.plate or nil)
end

-- 3. Update wear & mileage with telemetry sanity bounds
function Nyx.Vehicles.UpdateWear(identifier, deltaKm, wearDeltas)
    local vin = Nyx.Vehicles.ResolveVIN(identifier)
    if not vin then return false, "VEHICLE_NOT_FOUND" end

    local wear = Nyx.Vehicles.WearCache[vin]
    if not wear then
        wear = Nyx.Vehicles.LoadWear(vin)
    end
    if not wear then return false, "WEAR_DATA_UNAVAILABLE" end

    deltaKm = tonumber(deltaKm) or 0.0
    if deltaKm < 0.0 then deltaKm = 0.0 end

    -- Sanity check: verify distance delta against max reasonable speed
    local now = os.time()
    local lastTime = Nyx.Vehicles.LastWearUpdate[vin] or (now - 15)
    local elapsedSec = math.max(1, now - lastTime)
    Nyx.Vehicles.LastWearUpdate[vin] = now

    local maxSpeed = (Config.Wear and Config.Wear.MaxSpeedKmhSanity) or 450.0
    local maxAllowedKm = (maxSpeed / 3600.0) * elapsedSec + 0.5
    if deltaKm > maxAllowedKm then
        if Config.Debug then
            print(string.format("^3[Nyx:Vehicles:Wear]^7 Clamping suspicious distance delta: %.2f km (Max allowed: %.2f km)^7", deltaKm, maxAllowedKm))
        end
        deltaKm = maxAllowedKm
    end

    wear.mileage = math.max(0.0, wear.mileage + deltaKm)
    wear.tripOdometer = math.max(0.0, wear.tripOdometer + deltaKm)

    if wearDeltas and type(wearDeltas) == "table" then
        local oilLoss = tonumber(wearDeltas.oil) or 0.0
        local brakeLoss = tonumber(wearDeltas.brakes) or 0.0
        local transLoss = tonumber(wearDeltas.transmission) or 0.0
        local suspLoss = tonumber(wearDeltas.suspension) or 0.0

        -- Clamp max loss per packet to prevent manipulation
        wear.oilQuality = math.max(0.0, math.min(100.0, wear.oilQuality - math.min(10.0, math.max(0.0, oilLoss))))
        wear.brakePadWear = math.max(0.0, math.min(100.0, wear.brakePadWear - math.min(10.0, math.max(0.0, brakeLoss))))
        wear.transmissionWear = math.max(0.0, math.min(100.0, wear.transmissionWear - math.min(10.0, math.max(0.0, transLoss))))
        wear.suspensionWear = math.max(0.0, math.min(100.0, wear.suspensionWear - math.min(10.0, math.max(0.0, suspLoss))))
    end

    Nyx.Vehicles.DirtyWear[vin] = true

    local active = Nyx.Vehicles.Active[vin]
    if active then
        active.wear = wear
    end

    return true, wear
end

-- 4. Reset trip odometer
function Nyx.Vehicles.ResetTrip(vinOrIdentifier)
    local vin = Nyx.Vehicles.ResolveVIN(vinOrIdentifier)
    if not vin then return false, "VEHICLE_NOT_FOUND" end

    local wear = Nyx.Vehicles.WearCache[vin] or Nyx.Vehicles.LoadWear(vin)
    if not wear then return false, "WEAR_DATA_UNAVAILABLE" end

    wear.tripOdometer = 0.0
    Nyx.Vehicles.DirtyWear[vin] = true

    local active = Nyx.Vehicles.Active[vin]
    if active and active.netId then
        TriggerClientEvent("nyx:vehicles:client:syncWearSnapshot", -1, active.netId, wear)
    end

    return true, wear
end

-- 5. Perform certified mechanic service or field repair
function Nyx.Vehicles.ServiceVehicle(src, vinOrIdentifier, serviceType, notes)
    local player = exports['nyx_core'] and exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local vin = Nyx.Vehicles.ResolveVIN(vinOrIdentifier)
    if not vin then return false, "VEHICLE_NOT_FOUND" end

    local wear = Nyx.Vehicles.WearCache[vin] or Nyx.Vehicles.LoadWear(vin)
    if not wear then return false, "WEAR_DATA_UNAVAILABLE" end

    local active = Nyx.Vehicles.Active[vin]
    local plate = active and active.plate or wear.plate or "UNKNOWN"

    local costs = (Config.Wear and Config.Wear.ServiceCosts) or {}
    local cost = costs[serviceType] or 0.0

    -- Deduct required repair item or cash
    local invId = "citizen:" .. player.citizenId
    local reqItem = (Config.Wear and Config.Wear.ServiceRequiredItem) or "tool_repairkit"

    if exports['nyx_inventory'] and exports['nyx_inventory'].HasItem then
        local hasTool = exports['nyx_inventory']:HasItem(invId, reqItem, 1)
        if not hasTool and cost > 0.0 then
            -- Fallback: Check if player can pay monetary fee
            if player.money and player.money.cash and player.money.cash >= cost then
                exports['nyx_core']:RemoveMoney(src, 'cash', cost, "vehicle_maintenance_" .. serviceType)
            else
                return false, "INSUFFICIENT_FUNDS_OR_TOOL"
            end
        elseif hasTool and serviceType ~= "full_inspection" then
            -- Remove consumable tool only on full inspection / major overhaul if desired
            if serviceType == "transmission_overhaul" or serviceType == "suspension_tune" then
                exports['nyx_inventory']:RemoveItem(invId, reqItem, 1)
            end
        end
    end

    -- Apply servicing to component wear
    local previousCondition = {
        oil = wear.oilQuality,
        brakes = wear.brakePadWear,
        transmission = wear.transmissionWear,
        suspension = wear.suspensionWear
    }

    if serviceType == "oil_change" then
        wear.oilQuality = 100.0
    elseif serviceType == "brake_replacement" then
        wear.brakePadWear = 100.0
    elseif serviceType == "transmission_overhaul" then
        wear.transmissionWear = 100.0
    elseif serviceType == "suspension_tune" then
        wear.suspensionWear = 100.0
    elseif serviceType == "full_inspection" then
        -- Full inspection restores all wear if toolkit was used
        wear.oilQuality = 100.0
        wear.brakePadWear = 100.0
        wear.transmissionWear = 100.0
        wear.suspensionWear = 100.0
    end

    wear.lastServiceMileage = wear.mileage
    wear.serviceNotes = notes or string.format("Service '%s' performed by %s", serviceType, player.name or player.citizenId)

    -- Log to nyx_vehicles_service_logs
    MySQL.prepare([[
        INSERT INTO `nyx_vehicles_service_logs`
        (`vin`, `plate`, `mechanic_citizen_id`, `service_type`, `mileage_at_service`, `cost`, `notes`)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        vin,
        plate,
        player.citizenId,
        serviceType,
        wear.mileage,
        cost,
        wear.serviceNotes
    })

    -- Immediate database save for servicing
    MySQL.prepare([[
        UPDATE `nyx_vehicles_wear`
        SET `oil_quality` = ?,
            `brake_pad_wear` = ?,
            `transmission_wear` = ?,
            `suspension_wear` = ?,
            `last_service_mileage` = ?,
            `service_notes` = ?
        WHERE `vin` = ?
    ]], {
        wear.oilQuality,
        wear.brakePadWear,
        wear.transmissionWear,
        wear.suspensionWear,
        wear.lastServiceMileage,
        wear.serviceNotes,
        vin
    })

    Nyx.Vehicles.DirtyWear[vin] = nil

    if active and active.netId then
        TriggerClientEvent("nyx:vehicles:client:syncWearSnapshot", -1, active.netId, wear)
    end

    return true, {
        vin = vin,
        plate = plate,
        serviceType = serviceType,
        wear = wear,
        previous = previousCondition
    }
end

-- 6. Debounced Flush of dirty wear snapshots to MySQL
function Nyx.Vehicles.FlushWearBatch()
    local dirty = Nyx.Vehicles.DirtyWear
    Nyx.Vehicles.DirtyWear = {}

    local count = 0
    for vin, _ in pairs(dirty) do
        local wear = Nyx.Vehicles.WearCache[vin]
        if wear then
            count = count + 1
            MySQL.prepare([[
                UPDATE `nyx_vehicles_wear`
                SET `mileage` = ?,
                    `trip_odometer` = ?,
                    `oil_quality` = ?,
                    `brake_pad_wear` = ?,
                    `transmission_wear` = ?,
                    `suspension_wear` = ?
                WHERE `vin` = ?
            ]], {
                wear.mileage,
                wear.tripOdometer,
                wear.oilQuality,
                wear.brakePadWear,
                wear.transmissionWear,
                wear.suspensionWear,
                vin
            })
        end
    end

    if count > 0 and Config.Debug then
        print(string.format("^2[Nyx:Vehicles:Wear]^7 Flushed mileage & wear data for %d vehicles.^7", count))
    end
end

-- 7. Network and RPC Route Binding
CreateThread(function()
    -- Periodic debounced DB wear flush
    CreateThread(function()
        while true do
            Wait(Config.Persistence and (Config.Persistence.DamageFlushInterval * 1000) or 30000)
            Nyx.Vehicles.FlushWearBatch()
        end
    end)

    if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
        -- Query wear & mileage details
        exports['nyx_core']:RegisterRPC("vehicles:getWear", function(src, vinOrNetId)
            local wear = Nyx.Vehicles.GetWear(vinOrNetId)
            if not wear then
                return { success = false, error = "VEHICLE_NOT_FOUND" }
            end
            return { success = true, wear = wear }
        end)

        -- Reset trip odometer
        exports['nyx_core']:RegisterRPC("vehicles:resetTrip", function(src, vinOrNetId)
            local ok, res = Nyx.Vehicles.ResetTrip(vinOrNetId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Service / repair vehicle component wear
        exports['nyx_core']:RegisterRPC("vehicles:serviceVehicle", function(src, vinOrNetId, serviceType, notes)
            local ok, res = Nyx.Vehicles.ServiceVehicle(src, vinOrNetId, serviceType, notes)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Retrieve service log history
        exports['nyx_core']:RegisterRPC("vehicles:getServiceLogs", function(src, vinOrNetId)
            local vin = Nyx.Vehicles.ResolveVIN(vinOrNetId)
            if not vin then
                return { success = false, error = "VEHICLE_NOT_FOUND" }
            end

            local logs = MySQL.query.await([[
                SELECT `log_id`, `vin`, `plate`, `mechanic_citizen_id`, `service_type`,
                       `mileage_at_service`, `cost`, `notes`, `created_at`
                FROM `nyx_vehicles_service_logs`
                WHERE `vin` = ?
                ORDER BY `created_at` DESC
                LIMIT 25
            ]], { vin })

            return { success = true, logs = logs or {} }
        end)
    end
end)

-- Receive client mileage and wear telemetry
RegisterNetEvent("nyx:vehicles:server:updateVehicleWear", function(identifier, deltaKm, wearDeltas)
    if not identifier then return end
    Nyx.Vehicles.UpdateWear(identifier, deltaKm, wearDeltas)
end)
