--[[
    Nyxframework: nyx_services
    File: server/repair_stations.lua
    Description: Municipal public auto-repair stations, fiscal crisis/bankruptcy interlocks,
                 and closed-loop treasury fee processing.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.RepairStations = {}

-- 1. Initialize Repair Stations Registry
function Nyx.Services.LoadRepairStations()
    local defaultStations = {
        ['repair_depot_ls'] = {
            id = "repair_depot_ls",
            label = "Los Santos Municipal Public Works Repair Depot",
            coords = vector3(-338.4, -136.2, 39.0),
            baseLabor = 150.00,
            partsMult = 1.00,
            status = "operational"
        },
        ['repair_sandy_shores'] = {
            id = "repair_sandy_shores",
            label = "Sandy Shores Municipal Auto Maintenance Bay",
            coords = vector3(1735.6, 3311.2, 41.2),
            baseLabor = 120.00,
            partsMult = 1.10,
            status = "operational"
        },
        ['repair_paleto_bay'] = {
            id = "repair_paleto_bay",
            label = "Paleto Bay Public Service Maintenance Stall",
            coords = vector3(110.8, 6626.5, 31.8),
            baseLabor = 130.00,
            partsMult = 1.15,
            status = "operational"
        }
    }

    local rows = MySQL.query.await("SELECT * FROM `nyx_services_repair_stations`")
    if rows and #rows > 0 then
        for _, r in ipairs(rows) do
            local coords = { x = 0.0, y = 0.0, z = 0.0 }
            if type(r.coords) == "string" then
                local ok, parsed = pcall(json.decode, r.coords)
                if ok and type(parsed) == "table" then coords = parsed end
            end

            Nyx.Services.RepairStations[r.station_id] = {
                id = r.station_id,
                label = r.label,
                coords = vector3(coords.x, coords.y, coords.z),
                baseLabor = tonumber(r.base_labor_fee) or 150.00,
                partsMult = tonumber(r.parts_cost_multiplier) or 1.00,
                status = r.status or "operational"
            }
        end
    else
        Nyx.Services.RepairStations = defaultStations
    end
end

-- 2. Query Repair Estimate with Solvency Surcharges & Bankruptcy Kit Guards
function Nyx.Services.GetRepairEstimate(src, stationId, vehicleNetId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local station = Nyx.Services.RepairStations[stationId] or Nyx.Services.RepairStations["repair_depot_ls"]
    if not station then return false, "REPAIR_STATION_NOT_FOUND" end

    if station.status == "offline" then
        return false, "REPAIR_STATION_DECOMMISSIONED"
    end

    local vehEntity = NetworkGetEntityFromNetworkId(tonumber(vehicleNetId) or 0)
    local engineHealth = 1000.0
    local bodyHealth = 1000.0

    if DoesEntityExist(vehEntity) then
        engineHealth = GetVehicleEngineHealth(vehEntity)
        bodyHealth = GetVehicleBodyHealth(vehEntity)
    else
        -- Check active vehicle memory cache in nyx_vehicles
        local activeVeh = exports['nyx_vehicles']:GetActiveVehicle(vehicleNetId)
        if activeVeh and activeVeh.condition then
            engineHealth = activeVeh.condition.engine or 1000.0
            bodyHealth = activeVeh.condition.body or 1000.0
        end
    end

    local damageRatio = math.max(0.0, math.min(1.0, (1000.0 - math.min(engineHealth, bodyHealth)) / 1000.0))
    if damageRatio <= 0.01 then
        return false, "VEHICLE_IN_OPTIMAL_CONDITION"
    end

    -- Check if player carries physical tool_repairkit
    local hasRepairKit = false
    if exports['nyx_inventory'] and exports['nyx_inventory'].GetItemCount then
        local invId = "citizen:" .. player.citizenId
        local count = exports['nyx_inventory']:GetItemCount(invId, "tool_repairkit") or 0
        hasRepairKit = (count > 0)
    end

    local fiscalTier = "solvent"
    if exports['nyx_treasury'] and exports['nyx_treasury'].GetMunicipalFiscalTier then
        fiscalTier = exports['nyx_treasury']:GetMunicipalFiscalTier()
    end

    local okCalc, calcResult = exports['nyx_treasury']:CalculatePublicRepairCost(
        station.baseLabor,
        damageRatio,
        station.partsMult,
        hasRepairKit
    )

    if not okCalc then
        return false, calcResult
    end

    return true, {
        stationId = station.id,
        stationLabel = station.label,
        damageRatio = damageRatio,
        engineHealth = engineHealth,
        bodyHealth = bodyHealth,
        fiscalTier = fiscalTier,
        hasRepairKit = hasRepairKit,
        cost = calcResult
    }
end

-- 3. Execute Public Vehicle Repair and Treasury Revenue Settlement
function Nyx.Services.RepairVehicleAtStation(src, stationId, vehicleNetId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local okEst, est = Nyx.Services.GetRepairEstimate(src, stationId, vehicleNetId)
    if not okEst then return false, est end

    local totalCost = est.cost.totalCost
    local playerBankAcc = string.format("char:%s:bank", player.citizenId)
    local masterCityAcc = "gov:city:master"

    -- Bankruptcy Guard: If municipal treasury is bankrupt, player must supply repair kit
    if est.fiscalTier == "bankrupt" then
        if not est.hasRepairKit then
            return false, "STATION_INSOLVENT_REQUIRES_REPAIR_KIT"
        end

        local invId = "citizen:" .. player.citizenId
        local removed, remErr = exports['nyx_inventory']:RemoveItem(invId, "tool_repairkit", 1)
        if not removed then
            return false, "INSUFFICIENT_REPAIR_KITS_IN_INVENTORY"
        end
    end

    -- Debit player funds and credit municipal master reserve
    local currentBal = exports['nyx_treasury']:GetAccountBalance(playerBankAcc) or 0.00
    if currentBal < totalCost then
        local cashBal = player:getWallet("cash") or 0.00
        if (currentBal + cashBal) < totalCost then
            return false, string.format("INSUFFICIENT_FUNDS_REQUIRED_%.2f", totalCost)
        end
    end

    local okTransfer, txId = exports['nyx_treasury']:ExecuteTransfer(
        playerBankAcc,
        masterCityAcc,
        totalCost,
        "municipal_repair",
        "repair:" .. stationId,
        string.format("Municipal public repair at %s (Labor: $%.2f, Parts: $%.2f, Surcharge: $%.2f)",
            est.stationLabel, est.cost.laborFee, est.cost.partsFee, est.cost.surcharge),
        0.00
    )

    if not okTransfer then
        return false, "TREASURY_TRANSFER_FAILED"
    end

    -- Repair vehicle server-side
    local vehEntity = NetworkGetEntityFromNetworkId(tonumber(vehicleNetId) or 0)
    if DoesEntityExist(vehEntity) then
        SetVehicleEngineHealth(vehEntity, 1000.0)
        SetVehicleBodyHealth(vehEntity, 1000.0)
        SetVehicleFixed(vehEntity)
        SetVehicleDeformationFixed(vehEntity)
    end

    -- Also repair in nyx_vehicles active state
    local activeVeh = exports['nyx_vehicles']:GetActiveVehicle(vehicleNetId)
    if activeVeh then
        activeVeh.condition = {
            engine = 1000.0,
            body = 1000.0,
            dirt = 0.0,
            tires = { false, false, false, false },
            doors = {},
            windows = {}
        }
    end

    TriggerClientEvent("nyx:vehicles:client:repair", -1, tonumber(vehicleNetId), true)

    -- Trigger municipal solvency re-evaluation
    if exports['nyx_treasury'] and exports['nyx_treasury'].EvaluateMunicipalFiscalState then
        exports['nyx_treasury']:EvaluateMunicipalFiscalState()
    end

    return true, {
        stationId = stationId,
        totalPaid = totalCost,
        txId = txId,
        fiscalTier = est.fiscalTier,
        usedRepairKit = (est.fiscalTier == "bankrupt")
    }
end

-- Load Stations on Resource Start
MySQL.ready(function()
    Nyx.Services.LoadRepairStations()
end)

-- RPC Handlers
if Nyx.RPC and Nyx.RPC.Register then
    Nyx.RPC.Register("services:getRepairEstimate", function(src, payload)
        if not payload or not payload.stationId or not payload.vehicleNetId then
            return false, "INVALID_PAYLOAD"
        end
        return Nyx.Services.GetRepairEstimate(src, payload.stationId, payload.vehicleNetId)
    end)

    Nyx.RPC.Register("services:repairAtStation", function(src, payload)
        if not payload or not payload.stationId or not payload.vehicleNetId then
            return false, "INVALID_PAYLOAD"
        end
        return Nyx.Services.RepairVehicleAtStation(src, payload.stationId, payload.vehicleNetId)
    end)
end
