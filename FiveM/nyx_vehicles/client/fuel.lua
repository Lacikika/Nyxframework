--[[
    Nyxframework: nyx_vehicles
    File: client/fuel.lua
    Description: Client pump interaction, refueling nozzle animation,
                 underground reservoir depletion alerts, and fuel telemetry.
]]

local isRefueling = false
local cachedStations = {}

-- Update cached gas stations periodically
CreateThread(function()
    while true do
        if exports['nyx_core'] and exports['nyx_core'].CallRPC then
            local ok, res = pcall(function()
                return exports['nyx_core']:CallRPC("vehicles:getGasStations")
            end)
            if ok and res and res.success and res.stations then
                cachedStations = res.stations
            end
        end
        Wait(60000) -- Refresh station list every 60s
    end
end)

-- Find nearest pump prop or nearest station
local function findNearestStation()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local nearest, minDist = nil, 999999.0

    for _, s in pairs(cachedStations) do
        local sc = s.coords
        if sc and sc.x and sc.y and sc.z then
            local dist = #(coords - vector3(sc.x, sc.y, sc.z))
            if dist < minDist then
                minDist = dist
                nearest = s
            end
        end
    end

    return nearest, minDist
end

-- Find nearest vehicle within 5 meters
local function getNearbyVehicle()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local veh = GetVehiclePedIsIn(ped, false)

    if DoesEntityExist(veh) and veh ~= 0 then
        return veh
    end

    -- Look for nearby vehicle if player is on foot
    local handle, entity = FindFirstVehicle()
    local success
    local closestVeh = nil
    local closestDist = 6.0

    repeat
        local vCoords = GetEntityCoords(entity)
        local dist = #(coords - vCoords)
        if dist < closestDist then
            closestDist = dist
            closestVeh = entity
        end
        success, entity = FindNextVehicle(handle)
    until not success

    EndFindVehicle(handle)
    return closestVeh
end

-- Perform vehicle refueling
local function performRefuel(requestedLiters, paymentType)
    if isRefueling then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "Tankolás Folyamatban",
            message = "A tankolás már folyamatban van, kérlek várj!"
        })
        return
    end

    local station, dist = findNearestStation()
    if not station or dist > 40.0 then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "Nincs Benzinkút a Közelben",
            message = "Nem vagy benzinkút vagy üzemanyagtöltő állomás közelében!"
        })
        return
    end

    -- Pre-flight check on reservoir depletion
    if station.fuelStock and station.fuelStock <= 0.0 then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "A Benzinkút Készlete Kiapadt!",
            message = "A földalatti üzemanyagtartály teljesen üres. A tankolás szünetel, amíg egy tartálykocsi újra fel nem tölti a kutat!"
        })
        return
    end

    local veh = getNearbyVehicle()
    if not veh or not DoesEntityExist(veh) then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "Jármű Hiányzik",
            message = "Nincs jármű a közeledben a tankoláshoz!"
        })
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    isRefueling = true

    local ped = PlayerPedId()
    TaskTurnPedToFaceEntity(ped, veh, 1000)
    Wait(1000)

    -- Play refuel animation if on foot
    if not IsPedInAnyVehicle(ped, false) then
        TaskStartScenarioInPlace(ped, "PROP_HUMAN_BUM_BIN", 0, true)
    end

    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = "Tankolás Elindítva",
        message = string.format("Üzemanyag szivattyúzása folyamatban (%s)...", station.name)
    })

    Wait(3500) -- Refueling pump pumping simulation

    ClearPedTasks(ped)

    exports['nyx_core']:CallRPC("vehicles:refuelVehicle", {
        stationId = station.stationId,
        vehicleNetId = netId,
        liters = requestedLiters or 65.0,
        paymentType = paymentType or "bank"
    }, function(resp)
        isRefueling = false

        if resp and resp.success then
            SetVehicleFuelLevel(veh, resp.newFuelLevel)
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "Sikeres Tankolás",
                message = string.format("Betankolva: %.1f liter | Fizetve: $%.2f ($%.2f/L) | Kút szint: %.0fL",
                    resp.litersRefueled, resp.totalCost, resp.pricePerLiter, resp.remainingReservoir)
            })
        else
            local err = (resp and resp.error) or "ISMERETLEN_HIBA"
            if err == "RESERVOIR_DEPLETED" then
                TriggerEvent("nyx:ui:notify", {
                    type = "error",
                    title = "Kiapadt Tartály!",
                    message = "A földalatti üzemanyagtartály kifogyott! Nem sikerült üzemanyagot vételezni."
                })
            elseif err == "TANK_ALREADY_FULL" then
                TriggerEvent("nyx:ui:notify", {
                    type = "warning",
                    title = "Tele Tank",
                    message = "A jármű üzemanyagtartálya már teljesen tele van!"
                })
            elseif err == "INSUFFICIENT_FUNDS" then
                TriggerEvent("nyx:ui:notify", {
                    type = "error",
                    title = "Nincs Elég Pénz",
                    message = string.format("Nincs elegendő fedezet a tankoláshoz (Szükséges: $%.2f)!", resp.required or 0)
                })
            else
                TriggerEvent("nyx:ui:notify", {
                    type = "error",
                    title = "Tankolási Hiba",
                    message = string.format("A tankolás megszakadt: %s", tostring(err))
                })
            end
        end
    end)
end

-- Chat command: /refuel [liters] [cash/bank]
RegisterCommand("refuel", function(source, args)
    local liters = tonumber(args[1])
    local payment = args[2] or "bank"
    performRefuel(liters, payment)
end, false)

RegisterCommand("tankol", function(source, args)
    local liters = tonumber(args[1])
    local payment = args[2] or "bank"
    performRefuel(liters, payment)
end, false)

-- Chat command: /gasstations - Check nearby station stocks
RegisterCommand("gasstations", function()
    local nearest, dist = findNearestStation()
    if not nearest then
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = "Benzinkutak",
            message = "Nincs elérhető benzinkút adat."
        })
        return
    end

    local status = Nyx.VehicleFuel.EvaluateReservoirStatus(
        nearest.fuelStock, nearest.fuelCapacity, nearest.criticalThreshold, nearest.degradedThreshold
    )
    local badge = Nyx.VehicleFuel.FormatFuelBadge(status)

    TriggerEvent("nyx:ui:notify", {
        type = (status == "depleted" and "error") or (status == "critical_shortage" and "warning") or "info",
        title = string.format("%s (%.0fm)", nearest.name, dist),
        message = string.format("Készlet: %.0f / %.0f L (%s) | Ár: $%.2f/L",
            nearest.fuelStock, nearest.fuelCapacity, badge.text, nearest.currentPrice or nearest.basePrice)
    })
end, false)

-- Client Exports
exports("RefuelVehicle", function(requestedLiters, paymentType)
    performRefuel(requestedLiters, paymentType)
end)

exports("GetNearestGasStation", function()
    return findNearestStation()
end)

exports("IsRefueling", function()
    return isRefueling
end)
