--[[
    Nyxframework: nyx_vehicles
    File: server/fuel.lua
    Description: Authoritative server management for underground gas station reservoirs,
                 pump fuel dispensing, dynamic scarcity pricing, zero-fuel lockout,
                 and bulk fuel hauler logistics fulfillment.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}
Nyx.VehicleFuel = Nyx.VehicleFuel or {}
Nyx.VehicleFuel.Stations = {}

local function generateUuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return (string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end))
end

-- ----------------------------------------------------------------------------
-- 1. Hydrate Gas Stations from Database on Startup
-- ----------------------------------------------------------------------------
local function hydrateGasStations()
    local rows = MySQL.query.await([[
        SELECT `station_id`, `name`, `brand`, `zone_id`, `reservoir_stash_id`,
               `coords`, `fuel_capacity`, `fuel_stock`, `fuel_price_per_liter`,
               `critical_threshold`, `degraded_threshold`, `is_active`
        FROM `nyx_vehicles_gas_stations`
        WHERE `is_active` = 1
    ]])

    if rows and #rows > 0 then
        for _, r in ipairs(rows) do
            local coords = type(r.coords) == "string" and json.decode(r.coords) or r.coords
            Nyx.VehicleFuel.Stations[r.station_id] = {
                stationId = r.station_id,
                name = r.name,
                brand = r.brand,
                zoneId = r.zone_id,
                reservoirStashId = r.reservoir_stash_id,
                coords = coords,
                fuelCapacity = tonumber(r.fuel_capacity) or 10000.0,
                fuelStock = tonumber(r.fuel_stock) or 5000.0,
                basePrice = tonumber(r.fuel_price_per_liter) or 1.85,
                criticalThreshold = tonumber(r.critical_threshold) or 1000.0,
                degradedThreshold = tonumber(r.degraded_threshold) or 2500.0,
                isActive = (r.is_active == 1)
            }
        end
        print(string.format("^2[Nyx:Vehicles]^7 Hydrated %d gas station underground reservoirs from database.^7", #rows))
    else
        -- Fallback default stations if fresh boot
        local defaults = {
            { id = "gas_legion", name = "Legion Square Petrol", brand = "RON", zone = "zone_ls_metro", stash = "reservoir:gas_legion", coords = { x = 265.0, y = -1262.0, z = 29.3 }, cap = 10000.0, stock = 7500.0, price = 1.85 },
            { id = "gas_davis", name = "Davis LTD Gasoline", brand = "LTD", zone = "zone_ls_metro", stash = "reservoir:gas_davis", coords = { x = -70.0, y = -1761.5, z = 29.5 }, cap = 10000.0, stock = 6000.0, price = 1.80 },
            { id = "gas_sandy_shores", name = "Sandy Shores 24/7 Gas", brand = "Globe Oil", zone = "zone_sandy_shores", stash = "reservoir:gas_sandy_shores", coords = { x = 1966.5, y = 3741.0, z = 32.3 }, cap = 8000.0, stock = 4000.0, price = 2.10 },
            { id = "gas_paleto", name = "Paleto Bay Xero Gas", brand = "Xero Gas", zone = "zone_paleto_bay", stash = "reservoir:gas_paleto", coords = { x = 179.8, y = 6602.8, z = 31.9 }, cap = 8000.0, stock = 4500.0, price = 2.15 },
            { id = "gas_rockford", name = "Rockford Hills RON Express", brand = "RON", zone = "zone_ls_metro", stash = "reservoir:gas_rockford", coords = { x = -2096.5, y = -320.2, z = 13.2 }, cap = 12000.0, stock = 8000.0, price = 1.95 }
        }
        for _, d in ipairs(defaults) do
            Nyx.VehicleFuel.Stations[d.id] = {
                stationId = d.id,
                name = d.name,
                brand = d.brand,
                zoneId = d.zone,
                reservoirStashId = d.stash,
                coords = d.coords,
                fuelCapacity = d.cap,
                fuelStock = d.stock,
                basePrice = d.price,
                criticalThreshold = d.cap * 0.10,
                degradedThreshold = d.cap * 0.25,
                isActive = true
            }
        end
    end
end

MySQL.ready(function()
    CreateThread(function()
        while not (exports['nyx_core'] and exports['nyx_core'].IsDatabaseReady and exports['nyx_core']:IsDatabaseReady()) do
            Wait(50)
        end
        hydrateGasStations()
    end)
end)

-- ----------------------------------------------------------------------------
-- 2. Automated Logistics Shortage Contract Dispatcher
-- ----------------------------------------------------------------------------
function Nyx.VehicleFuel.CheckShortageContract(station)
    if not station or not station.stationId then return end

    if station.fuelStock <= station.criticalThreshold then
        local existing = MySQL.scalar.await([[
            SELECT COUNT(*) FROM `nyx_logistics_freight_contracts`
            WHERE `dest_inventory_id` = ? AND `status` IN ('available', 'in_transit')
        ]], { station.reservoirStashId })

        if existing == 0 then
            local pods, payoutPerUnit, totalPayout, escrow = Nyx.VehicleFuel.CalculateBulkDeliveryContract(
                station.fuelStock, station.fuelCapacity
            )
            local contractUuid = generateUuid()
            local srcCoords = Nyx.VehicleFuel.Defaults.RefineryCoords
            local dstCoords = station.coords

            local contractId = MySQL.insert.await([[
                INSERT INTO `nyx_logistics_freight_contracts`
                (`contract_uuid`, `contract_type`, `issuer_type`, `issuer_id`, `title`,
                 `source_inventory_id`, `dest_inventory_id`, `source_coords`, `dest_coords`, `zone_id`,
                 `item_id`, `quantity`, `payout_per_unit`, `total_payout`, `escrow_deposit`, `status`, `deadline_seconds`)
                VALUES (?, 'bulk_fuel', 'gas_station', ?, ?, ?, ?, ?, ?, ?, 'bulk_fuel_tank', ?, ?, ?, ?, 'available', ?)
            ]], {
                contractUuid,
                station.stationId,
                string.format("Sürgősségi Üzemanyag Szállítás: %s", station.name),
                Nyx.VehicleFuel.Defaults.RefineryStashId,
                station.reservoirStashId,
                json.encode(srcCoords),
                json.encode(dstCoords),
                station.zoneId or "zone_ls_metro",
                pods,
                payoutPerUnit,
                totalPayout,
                escrow,
                1800
            })

            if contractId then
                MySQL.prepare([[
                    UPDATE `nyx_vehicles_gas_stations`
                    SET `last_emergency_contract_at` = NOW()
                    WHERE `station_id` = ?
                ]], { station.stationId })

                MySQL.prepare([[
                    INSERT INTO `nyx_vehicles_fuel_audit`
                    (`audit_uuid`, `station_id`, `reservoir_stash_id`, `action`, `liters`, `cost`, `price_per_liter`, `remaining_stock`, `contract_id`, `notes`)
                    VALUES (?, ?, ?, 'CONTRACT_TRIGGERED', ?, ?, ?, ?, ?, 'Automated refinery bulk fuel delivery mission dispatched to freight board')
                ]], {
                    generateUuid(),
                    station.stationId,
                    station.reservoirStashId,
                    pods * 500.0,
                    totalPayout,
                    payoutPerUnit,
                    station.fuelStock,
                    contractId
                })

                TriggerClientEvent("nyx:logistics:client:newContractAvailable", -1, {
                    contractId = contractId,
                    title = string.format("Sürgősségi Üzemanyag: %s", station.name),
                    quantity = pods,
                    totalPayout = totalPayout,
                    escrowDeposit = escrow,
                    zoneId = station.zoneId
                })

                print(string.format("^3[Nyx:Vehicles] Bulk fuel delivery mission #%d dispatched for %s (%d pods / %dL, $%.2f payout)^7",
                    contractId, station.name, pods, pods * 500, totalPayout))
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- 3. Register RPC Routes with nyx_core
-- ----------------------------------------------------------------------------
CreateThread(function()
    if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
        -- Query all active gas stations
        exports['nyx_core']:RegisterRPC("vehicles:getGasStations", function(src)
            local list = {}
            for id, s in pairs(Nyx.VehicleFuel.Stations) do
                local curPrice = Nyx.VehicleFuel.CalculateDynamicPrice(s.basePrice, s.fuelStock, s.fuelCapacity)
                local status = Nyx.VehicleFuel.EvaluateReservoirStatus(s.fuelStock, s.fuelCapacity, s.criticalThreshold, s.degradedThreshold)
                table.insert(list, {
                    stationId = s.stationId,
                    name = s.name,
                    brand = s.brand,
                    zoneId = s.zoneId,
                    reservoirStashId = s.reservoirStashId,
                    coords = s.coords,
                    fuelCapacity = s.fuelCapacity,
                    fuelStock = s.fuelStock,
                    currentPrice = curPrice,
                    status = status,
                    badge = Nyx.VehicleFuel.FormatFuelBadge(status)
                })
            end
            return { success = true, stations = list }
        end)

        -- Query specific gas station status
        exports['nyx_core']:RegisterRPC("vehicles:getGasStationStatus", function(src, stationId)
            local s = Nyx.VehicleFuel.Stations[stationId]
            if not s then return { success = false, error = "STATION_NOT_FOUND" } end

            local curPrice = Nyx.VehicleFuel.CalculateDynamicPrice(s.basePrice, s.fuelStock, s.fuelCapacity)
            local status = Nyx.VehicleFuel.EvaluateReservoirStatus(s.fuelStock, s.fuelCapacity, s.criticalThreshold, s.degradedThreshold)
            return {
                success = true,
                station = {
                    stationId = s.stationId,
                    name = s.name,
                    brand = s.brand,
                    zoneId = s.zoneId,
                    coords = s.coords,
                    fuelCapacity = s.fuelCapacity,
                    fuelStock = s.fuelStock,
                    currentPrice = curPrice,
                    status = status,
                    badge = Nyx.VehicleFuel.FormatFuelBadge(status)
                }
            }
        end)

        -- Refuel vehicle from pump
        exports['nyx_core']:RegisterRPC("vehicles:refuelVehicle", function(src, payload)
            local player = exports['nyx_core']:GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local okVal, errVal = Nyx.VehicleFuel.ValidateRefuelPayload(payload)
            if not okVal then return { success = false, error = errVal } end

            local station = Nyx.VehicleFuel.Stations[payload.stationId]
            if not station or not station.isActive then
                return { success = false, error = "STATION_UNAVAILABLE" }
            end

            local vehEntity = NetworkGetEntityFromNetworkId(payload.vehicleNetId)
            if not DoesEntityExist(vehEntity) then
                return { success = false, error = "VEHICLE_NOT_FOUND" }
            end

            -- Proximity check (player and vehicle within 30m of gas station)
            local ped = GetPlayerPed(tostring(src))
            local pCoords = GetEntityCoords(ped)
            local vCoords = GetEntityCoords(vehEntity)
            local sCoords = vector3(station.coords.x, station.coords.y, station.coords.z)

            if #(pCoords - sCoords) > 40.0 or #(vCoords - sCoords) > 40.0 then
                return { success = false, error = "OUT_OF_RANGE" }
            end

            local plate = GetVehicleNumberPlateText(vehEntity):gsub("^%s*(.-)%s*$", "%1")
            local currentTank = GetVehicleFuelLevel(vehEntity)
            local maxTank = (Config.Fuel and Config.Fuel.DefaultTankCapacity) or Nyx.VehicleFuel.Defaults.DefaultVehicleTank

            -- Calculate authoritative refuel amount and guard zero stock
            local refuelAmount, calcStatus = Nyx.VehicleFuel.CalculateRefuelAmount(
                currentTank, maxTank, station.fuelStock, payload.liters
            )

            if calcStatus ~= "OK" or refuelAmount <= 0.0 then
                return { success = false, error = calcStatus }
            end

            local dynamicPrice = Nyx.VehicleFuel.CalculateDynamicPrice(
                station.basePrice, station.fuelStock, station.fuelCapacity
            )
            local totalCost = math.floor((refuelAmount * dynamicPrice) * 100.0 + 0.5) / 100.0
            local paymentType = payload.paymentType or "bank"

            -- Verify player funds
            local playerBal = player:getMoney(paymentType) or 0.0
            if playerBal < totalCost then
                return { success = false, error = "INSUFFICIENT_FUNDS", required = totalCost }
            end

            -- Deduct money
            player:removeMoney(paymentType, totalCost, string.format("Tankolás: %s (%.1fL @ $%.2f/L)", station.name, refuelAmount, dynamicPrice))

            -- Transfer cut to municipal reserves if treasury exists
            if exports['nyx_treasury'] and exports['nyx_treasury'].DepositFunds then
                exports['nyx_treasury']:DepositFunds("gov:city:master", totalCost, string.format("Üzemanyag Jövedéki Adó & Értékesítés: %s", station.name))
            end

            -- Update station reservoir stock
            station.fuelStock = math.max(0.0, station.fuelStock - refuelAmount)
            MySQL.prepare([[
                UPDATE `nyx_vehicles_gas_stations`
                SET `fuel_stock` = ?
                WHERE `station_id` = ?
            ]], { station.fuelStock, station.stationId })

            -- Update vehicle fuel level
            local newFuelLevel = math.min(maxTank, currentTank + refuelAmount)
            SetVehicleFuelLevel(vehEntity, newFuelLevel)

            -- Sync to active vehicle cache if tracked
            local vin = Nyx.Vehicles.ByNetId and Nyx.Vehicles.ByNetId[payload.vehicleNetId]
            if vin and Nyx.Vehicles.Active and Nyx.Vehicles.Active[vin] then
                Nyx.Vehicles.Active[vin].fuelLevel = newFuelLevel
            end

            -- Audit log
            MySQL.prepare([[
                INSERT INTO `nyx_vehicles_fuel_audit`
                (`audit_uuid`, `station_id`, `reservoir_stash_id`, `action`, `liters`, `cost`, `price_per_liter`, `remaining_stock`, `vehicle_plate`, `citizen_id`, `notes`)
                VALUES (?, ?, ?, 'REFUELED_VEHICLE', ?, ?, ?, ?, ?, ?, ?)
            ]], {
                generateUuid(),
                station.stationId,
                station.reservoirStashId,
                refuelAmount,
                totalCost,
                dynamicPrice,
                station.fuelStock,
                plate,
                player.citizenId,
                string.format("Refueled %.1fL into vehicle %s", refuelAmount, plate)
            })

            -- Check if shortage threshold crossed
            Nyx.VehicleFuel.CheckShortageContract(station)

            return {
                success = true,
                litersRefueled = refuelAmount,
                totalCost = totalCost,
                pricePerLiter = dynamicPrice,
                newFuelLevel = newFuelLevel,
                remainingReservoir = station.fuelStock
            }
        end)

        -- Manual restock from inventory items
        exports['nyx_core']:RegisterRPC("vehicles:restockGasStation", function(src, payload)
            local player = exports['nyx_core']:GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local okVal, errVal, litersAdded = Nyx.VehicleFuel.ValidateRestockPayload(payload)
            if not okVal then return { success = false, error = errVal } end

            local station = Nyx.VehicleFuel.Stations[payload.stationId]
            if not station then return { success = false, error = "STATION_NOT_FOUND" } end

            local playerInv = string.format("char:%s:inventory", player.citizenId)
            local hasItem = exports['nyx_inventory']:HasItem(playerInv, payload.itemId, payload.quantity)
            if not hasItem then
                return { success = false, error = "MISSING_RESTOCK_ITEM" }
            end

            local okRemove = exports['nyx_inventory']:RemoveItem(playerInv, payload.itemId, payload.quantity)
            if not okRemove then
                return { success = false, error = "FAILED_TO_REMOVE_ITEM" }
            end

            station.fuelStock = math.min(station.fuelCapacity, station.fuelStock + litersAdded)
            MySQL.prepare([[
                UPDATE `nyx_vehicles_gas_stations`
                SET `fuel_stock` = ?
                WHERE `station_id` = ?
            ]], { station.fuelStock, station.stationId })

            MySQL.prepare([[
                INSERT INTO `nyx_vehicles_fuel_audit`
                (`audit_uuid`, `station_id`, `reservoir_stash_id`, `action`, `liters`, `remaining_stock`, `citizen_id`, `notes`)
                VALUES (?, ?, ?, 'RESTOCKED_MANUAL', ?, ?, ?, ?)
            ]], {
                generateUuid(),
                station.stationId,
                station.reservoirStashId,
                litersAdded,
                station.fuelStock,
                player.citizenId,
                string.format("Manual restock of %dx %s (+%.1fL)", payload.quantity, payload.itemId, litersAdded)
            })

            return {
                success = true,
                litersAdded = litersAdded,
                newStock = station.fuelStock
            }
        end)
    end
end)

-- ----------------------------------------------------------------------------
-- 4. Bulk Fuel Freight Logistics Delivery Event Listener
-- ----------------------------------------------------------------------------
RegisterNetEvent("nyx:vehicles:server:bulkFuelDelivered", function(destInvId, contractId, itemId, quantity)
    if not destInvId then return end

    local targetStation = nil
    for _, s in pairs(Nyx.VehicleFuel.Stations) do
        if s.reservoirStashId == destInvId then
            targetStation = s
            break
        end
    end

    if not targetStation then
        -- Query from database if station was not cached
        local row = MySQL.single.await("SELECT * FROM `nyx_vehicles_gas_stations` WHERE `reservoir_stash_id` = ?", { destInvId })
        if row then
            targetStation = {
                stationId = row.station_id,
                name = row.name,
                fuelCapacity = tonumber(row.fuel_capacity) or 10000.0,
                fuelStock = tonumber(row.fuel_stock) or 0.0,
                reservoirStashId = row.reservoir_stash_id
            }
            Nyx.VehicleFuel.Stations[row.station_id] = targetStation
        end
    end

    if targetStation then
        local litersPerUnit = (itemId == "industrial_fuel" and 50.0) or 500.0
        local addedLiters = litersPerUnit * (quantity or 1)
        targetStation.fuelStock = math.min(targetStation.fuelCapacity, targetStation.fuelStock + addedLiters)

        MySQL.prepare([[
            UPDATE `nyx_vehicles_gas_stations`
            SET `fuel_stock` = ?, `last_delivery_at` = NOW()
            WHERE `reservoir_stash_id` = ?
        ]], { targetStation.fuelStock, destInvId })

        MySQL.prepare([[
            INSERT INTO `nyx_vehicles_fuel_audit`
            (`audit_uuid`, `station_id`, `reservoir_stash_id`, `action`, `liters`, `remaining_stock`, `contract_id`, `notes`)
            VALUES (?, ?, ?, 'BULK_DELIVERED', ?, ?, ?, 'Commercial bulk tanker cargo successfully delivered and pumped into reservoir')
        ]], {
            generateUuid(),
            targetStation.stationId,
            targetStation.reservoirStashId,
            addedLiters,
            targetStation.fuelStock,
            contractId
        })

        print(string.format("^2[Nyx:Vehicles] Bulk tanker delivery #%s received at %s: +%.1fL (Current stock: %.1f / %.1fL)^7",
            tostring(contractId), targetStation.name, addedLiters, targetStation.fuelStock, targetStation.fuelCapacity))
    end
end)

-- ----------------------------------------------------------------------------
-- 5. Exported APIs
-- ----------------------------------------------------------------------------
function Nyx.VehicleFuel.GetGasStation(stationId)
    return Nyx.VehicleFuel.Stations[stationId]
end

function Nyx.VehicleFuel.GetAllGasStations()
    return Nyx.VehicleFuel.Stations
end

function Nyx.VehicleFuel.GetGasStationReservoir(stationId)
    local s = Nyx.VehicleFuel.Stations[stationId]
    return s and s.fuelStock or 0.0
end

function Nyx.VehicleFuel.ReplenishReservoir(stationId, liters)
    local s = Nyx.VehicleFuel.Stations[stationId]
    if not s then return false, "STATION_NOT_FOUND" end
    liters = tonumber(liters) or 0.0
    if liters <= 0.0 then return false, "INVALID_LITERS" end

    s.fuelStock = math.min(s.fuelCapacity, s.fuelStock + liters)
    MySQL.prepare("UPDATE `nyx_vehicles_gas_stations` SET `fuel_stock` = ? WHERE `station_id` = ?", { s.fuelStock, stationId })
    return true, s.fuelStock
end
