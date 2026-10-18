--[[
    Nyxframework: nyx_vehicles
    File: server/impound.lua
    Description: Authoritative municipal impound lots, impounding workflow,
                 fiscal crisis surcharges, and treasury revenue settlement.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}
Nyx.Vehicles.ImpoundLots = {}

-- 1. Initialize Impound Lots Registry
function Nyx.Vehicles.LoadImpoundLots()
    local defaultLots = {
        ['impound_lot_ls'] = {
            id = "impound_lot_ls",
            label = "Los Santos Municipal Auto Impound",
            coords = vector3(401.2, -1631.5, 29.3),
            releaseCoords = vector4(405.0, -1640.0, 29.3, 230.0),
            baseFee = 500.00,
            dailyRate = 150.00
        },
        ['impound_lot_sandy'] = {
            id = "impound_lot_sandy",
            label = "Blaine County Sheriff Impound Compound",
            coords = vector3(1853.2, 3685.4, 34.2),
            releaseCoords = vector4(1860.0, 3678.0, 34.0, 30.0),
            baseFee = 350.00,
            dailyRate = 100.00
        }
    }

    local rows = MySQL.query.await("SELECT * FROM `nyx_vehicles_impound_lots`")
    if rows and #rows > 0 then
        for _, r in ipairs(rows) do
            local coords = { x = 0.0, y = 0.0, z = 0.0 }
            local rel = { x = 0.0, y = 0.0, z = 0.0, w = 0.0 }
            if type(r.coords) == "string" then
                local ok, parsed = pcall(json.decode, r.coords)
                if ok and type(parsed) == "table" then coords = parsed end
            end
            if type(r.release_coords) == "string" then
                local ok, parsed = pcall(json.decode, r.release_coords)
                if ok and type(parsed) == "table" then rel = parsed end
            end

            Nyx.Vehicles.ImpoundLots[r.lot_id] = {
                id = r.lot_id,
                label = r.label,
                coords = vector3(coords.x, coords.y, coords.z),
                releaseCoords = vector4(rel.x, rel.y, rel.z, rel.w or 0.0),
                baseFee = tonumber(r.base_fee) or 500.00,
                dailyRate = tonumber(r.daily_storage_fee) or 150.00
            }
        end
    else
        Nyx.Vehicles.ImpoundLots = defaultLots
    end
end

-- 2. Authoritatively Impound a Vehicle
function Nyx.Vehicles.ImpoundVehicle(vin, reason, fee, impoundLotId, officerCitizenId)
    if not vin then return false, "MISSING_VIN" end

    local row = MySQL.single.await([[
        SELECT `vin`, `plate`, `owner_citizen_id`, `storage_state`
        FROM `nyx_vehicles_owned`
        WHERE `vin` = ?
    ]], { vin })

    if not row then return false, "VEHICLE_NOT_FOUND" end

    local lotId = impoundLotId or "impound_lot_ls"
    local lot = Nyx.Vehicles.ImpoundLots[lotId] or Nyx.Vehicles.ImpoundLots["impound_lot_ls"]
    local assignedFee = tonumber(fee) or (lot and lot.baseFee or 500.00)

    -- If currently spawned in world, despawn entity
    if Nyx.Vehicles.Active and Nyx.Vehicles.Active[vin] then
        local active = Nyx.Vehicles.Active[vin]
        if active.entity and DoesEntityExist(active.entity) then
            DeleteEntity(active.entity)
        end
        if active.entity then Nyx.Vehicles.ByEntity[active.entity] = nil end
        if active.netId then Nyx.Vehicles.ByNetId[active.netId] = nil end
        if active.plate then Nyx.Vehicles.ByPlate[active.plate] = nil end
        Nyx.Vehicles.Active[vin] = nil
    end

    local now = os.time()
    MySQL.prepare.await([[
        UPDATE `nyx_vehicles_owned`
        SET `storage_state` = 'impounded',
            `impound_lot_id` = ?,
            `impound_fee` = ?,
            `impound_reason` = ?,
            `impounded_by` = ?,
            `impounded_at` = ?
        WHERE `vin` = ?
    ]], { lotId, assignedFee, reason or "Municipal violation", officerCitizenId or "CITY_DISPATCH", now, vin })

    -- Log impound action
    MySQL.prepare.await([[
        INSERT INTO `nyx_vehicles_impound_logs`
            (`vin`, `plate`, `action`, `citizen_id`, `officer_citizen_id`, `impound_lot_id`, `base_fee`, `emergency_surcharge`, `total_paid`, `notes`)
        VALUES (?, ?, 'impounded', ?, ?, ?, ?, 0.00, 0.00, ?)
    ]], { vin, row.plate, row.owner_citizen_id, officerCitizenId, lotId, assignedFee, reason or "Vehicle impounded" })

    TriggerEvent("nyx:vehicles:server:vehicleImpounded", vin, row.plate, lotId, assignedFee)

    return true, {
        vin = vin,
        plate = row.plate,
        lotId = lotId,
        fee = assignedFee,
        impoundedAt = now
    }
end

-- 3. Query Impounded Vehicles for a Citizen
function Nyx.Vehicles.GetImpoundedVehicles(citizenId, optionalLotId)
    local query = [[
        SELECT `vin`, `plate`, `model_name`, `impound_lot_id`, `impound_fee`, `impound_reason`, `impounded_at`
        FROM `nyx_vehicles_owned`
        WHERE `owner_citizen_id` = ? AND `storage_state` = 'impounded'
    ]]
    local params = { citizenId }

    if optionalLotId then
        query = query .. " AND `impound_lot_id` = ?"
        table.insert(params, optionalLotId)
    end

    local rows = MySQL.query.await(query, params)
    if not rows then return {} end

    local fiscalTier = "solvent"
    if exports['nyx_treasury'] and exports['nyx_treasury'].GetMunicipalFiscalTier then
        fiscalTier = exports['nyx_treasury']:GetMunicipalFiscalTier()
    end

    local now = os.time()
    local results = {}

    for _, r in ipairs(rows) do
        local lot = Nyx.Vehicles.ImpoundLots[r.impound_lot_id] or Nyx.Vehicles.ImpoundLots["impound_lot_ls"]
        local impAt = tonumber(r.impounded_at) or now
        local elapsedSec = math.max(0, now - impAt)
        local elapsedDays = math.floor(elapsedSec / 86400)

        local baseFee = tonumber(r.impound_fee) or (lot and lot.baseFee or 500.00)
        local dailyRate = lot and lot.dailyRate or 150.00

        local costCalc = Nyx.Degradation.CalculateImpoundReleaseCost(baseFee, elapsedDays, dailyRate, fiscalTier)

        table.insert(results, {
            vin = r.vin,
            plate = r.plate,
            modelName = r.model_name,
            impoundLotId = r.impound_lot_id,
            lotLabel = lot and lot.label or "Municipal Lot",
            impoundReason = r.impound_reason,
            impoundedAt = impAt,
            elapsedDays = elapsedDays,
            cost = costCalc
        })
    end

    return results
end

-- 4. Authoritative Release of Impounded Vehicle
function Nyx.Vehicles.ReleaseImpoundedVehicle(src, vin, impoundLotId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local row = MySQL.single.await([[
        SELECT `vin`, `plate`, `model_name`, `model_hash`, `owner_citizen_id`, `storage_state`,
               `impound_lot_id`, `impound_fee`, `impounded_at`
        FROM `nyx_vehicles_owned`
        WHERE `vin` = ?
    ]], { vin })

    if not row then return false, "VEHICLE_NOT_FOUND" end

    if row.owner_citizen_id ~= player.citizenId and not player.hasPermission and not (player.hasPermission and player.hasPermission("police")) then
        return false, "UNAUTHORIZED_NOT_OWNER"
    end

    if row.storage_state ~= "impounded" then
        return false, "VEHICLE_NOT_IMPOUNDED"
    end

    local lotId = impoundLotId or row.impound_lot_id or "impound_lot_ls"
    local lot = Nyx.Vehicles.ImpoundLots[lotId] or Nyx.Vehicles.ImpoundLots["impound_lot_ls"]

    local fiscalTier = "solvent"
    if exports['nyx_treasury'] and exports['nyx_treasury'].GetMunicipalFiscalTier then
        fiscalTier = exports['nyx_treasury']:GetMunicipalFiscalTier()
    end

    local canRelease, releaseErr = Nyx.Registration.CanReleaseFromImpound(row, fiscalTier)
    if not canRelease then
        return false, releaseErr
    end

    local now = os.time()
    local impAt = tonumber(row.impounded_at) or now
    local elapsedDays = math.floor(math.max(0, now - impAt) / 86400)

    local baseFee = tonumber(row.impound_fee) or (lot and lot.baseFee or 500.00)
    local dailyRate = lot and lot.dailyRate or 150.00
    local costCalc = Nyx.Degradation.CalculateImpoundReleaseCost(baseFee, elapsedDays, dailyRate, fiscalTier)

    local totalCost = costCalc.totalFee

    -- Double-Entry Treasury Settlement: Player Wallet/Bank -> Municipal Master Reserve
    local playerBankAcc = string.format("char:%s:bank", player.citizenId)
    local masterCityAcc = "gov:city:master"

    local currentBal = exports['nyx_treasury']:GetAccountBalance(playerBankAcc) or 0.00
    if currentBal < totalCost then
        -- Also check cash wallet if bank balance is insufficient
        local cashBal = player:getWallet("cash") or 0.00
        if (currentBal + cashBal) < totalCost then
            return false, string.format("INSUFFICIENT_FUNDS_REQUIRED_%.2f", totalCost)
        end
    end

    local okTransfer, txId = exports['nyx_treasury']:ExecuteTransfer(
        playerBankAcc,
        masterCityAcc,
        totalCost,
        "impound_release",
        "impound:" .. vin,
        string.format("Impound release for %s [%s] (Base: $%.2f, Storage: $%.2f, Surcharge: $%.2f)",
            row.model_name or "Vehicle", row.plate, costCalc.baseFee, costCalc.storageFee, costCalc.emergencySurcharge),
        0.00
    )

    if not okTransfer then
        return false, "TREASURY_SETTLEMENT_FAILED"
    end

    -- Update database: vehicle is now stored at impound garage
    MySQL.prepare.await([[
        UPDATE `nyx_vehicles_owned`
        SET `storage_state` = 'stored',
            `garage_id` = ?,
            `impound_lot_id` = NULL,
            `impound_fee` = 0.00,
            `impound_reason` = NULL,
            `impounded_by` = NULL,
            `impounded_at` = NULL
        WHERE `vin` = ?
    ]], { lotId, vin })

    -- Log release action
    MySQL.prepare.await([[
        INSERT INTO `nyx_vehicles_impound_logs`
            (`vin`, `plate`, `action`, `citizen_id`, `officer_citizen_id`, `impound_lot_id`, `base_fee`, `emergency_surcharge`, `total_paid`, `treasury_tx_id`, `notes`)
        VALUES (?, ?, 'released', ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        vin,
        row.plate,
        player.citizenId,
        row.impounded_by,
        lotId,
        costCalc.baseFee + costCalc.storageFee,
        costCalc.emergencySurcharge,
        totalCost,
        txId,
        string.format("Vehicle released under fiscal tier '%s'", fiscalTier)
    })

    -- Trigger municipal solvency re-evaluation since master treasury received funds
    if exports['nyx_treasury'] and exports['nyx_treasury'].EvaluateMunicipalFiscalState then
        exports['nyx_treasury']:EvaluateMunicipalFiscalState()
    end

    return true, {
        vin = vin,
        plate = row.plate,
        lotId = lotId,
        totalPaid = totalCost,
        txId = txId,
        costBreakdown = costCalc
    }
end

-- Load Lots on Resource Start
MySQL.ready(function()
    Nyx.Vehicles.LoadImpoundLots()
end)

-- RPC Handlers
if Nyx.RPC and Nyx.RPC.Register then
    Nyx.RPC.Register("vehicles:getImpoundedVehicles", function(src, payload)
        local player = Nyx.GetPlayer(src)
        if not player then return {} end
        return Nyx.Vehicles.GetImpoundedVehicles(player.citizenId, payload and payload.lotId)
    end)

    Nyx.RPC.Register("vehicles:releaseImpoundedVehicle", function(src, payload)
        if not payload or not payload.vin then return false, "MISSING_VIN" end
        return Nyx.Vehicles.ReleaseImpoundedVehicle(src, payload.vin, payload.lotId)
    end)

    Nyx.RPC.Register("vehicles:impoundVehicle", function(src, payload)
        local player = Nyx.GetPlayer(src)
        if not player then return false, "UNAUTHENTICATED" end
        if not payload or not payload.vin then return false, "MISSING_VIN" end
        return Nyx.Vehicles.ImpoundVehicle(payload.vin, payload.reason, payload.fee, payload.lotId, player.citizenId)
    end)
end
