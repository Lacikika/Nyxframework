--[[
    Nyxframework: nyx_vehicles
    File: server/tolls_and_weighing.lua
    Description: Authoritative server handlers for automated RFID/plate toll deduction,
                 treasury revenue routing, commercial weigh station inspections,
                 cargo manifest verification, and automated MDT dispatch alerts.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}
Nyx.TollsAndWeighing = Nyx.TollsAndWeighing or {}

-- Standardized RPC Bridge to nyx_core
Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
            exports['nyx_core']:RegisterRPC(route, handler)
        end
    end,
    GenerateNonce = function()
        local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        return (string.gsub(template, '[xy]', function(c)
            local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format('%x', v)
        end))
    end
}

--- Process automated RFID/plate toll gantry pass
--- @param src number Player source ID
--- @param plazaId string Toll plaza identifier
--- @param plate string Vehicle license plate
--- @param vehicleClass number Vehicle class ID
--- @return table result { success = bool, fee = number, plazaId = string, txUuid = string }
function Nyx.Vehicles.ProcessTollPass(src, plazaId, plate, vehicleClass)
    src = tonumber(src)
    plate = tostring(plate or "UNKNOWN")
    vehicleClass = tonumber(vehicleClass) or 0
    plazaId = tostring(plazaId or "plaza_del_perro_fwy")

    local plaza = MySQL.single.await([[
        SELECT `plaza_id`, `zone_name`, `base_fee`, `commercial_axle_multiplier`, `active_status`
        FROM `nyx_toll_plazas` WHERE `plaza_id` = ?
    ]], { plazaId })

    if not plaza or tonumber(plaza.active_status or 1) == 0 then
        -- Default fallback plaza if DB query returns nil
        plaza = {
            plaza_id = plazaId,
            zone_name = "Highway Toll Plaza",
            base_fee = 5.00,
            commercial_axle_multiplier = 1.50,
            active_status = 1
        }
    end

    local fee = Nyx.TollsAndWeighing.CalculateTollFee(
        vehicleClass,
        tonumber(plaza.base_fee) or 5.00,
        tonumber(plaza.commercial_axle_multiplier) or 1.50,
        1.00
    )

    -- Determine account/citizen source
    local player = Nyx.GetPlayer and Nyx.GetPlayer(src) or nil
    local citizenId = player and player.citizenId or ("CIT_" .. src)
    local accountId = "citizen:" .. citizenId

    -- Route fee directly into public treasury master account earmarked for road degradation repair
    local masterAcc = "gov:city:master"
    local txUuid = nil

    if exports['nyx_treasury'] and exports['nyx_treasury'].TransferFunds then
        local ok, tx = pcall(function()
            return exports['nyx_treasury']:TransferFunds(
                accountId,
                masterAcc,
                fee,
                "highway_toll",
                string.format("Automated RFID toll pass at %s (%s)", plaza.zone_name, plate)
            )
        end)
        if ok and tx then txUuid = tx end
    end

    -- Update toll plaza total collected statistic
    MySQL.update.await([[
        UPDATE `nyx_toll_plazas`
        SET `total_collected` = `total_collected` + ?
        WHERE `plaza_id` = ?
    ]], { fee, plazaId })

    -- Sync municipal infrastructure degradation if treasury module is available
    if exports['nyx_treasury'] and exports['nyx_treasury'].EvaluateMunicipalFiscalState then
        pcall(function() exports['nyx_treasury']:EvaluateMunicipalFiscalState() end)
    end

    return {
        success = true,
        fee = fee,
        plazaId = plazaId,
        txUuid = txUuid
    }
end

--- Inspect commercial vehicle weight, cross-reference freight contracts and pallets, and log result
--- @param src number Driver source ID
--- @param plate string Vehicle plate
--- @param vehicleClass number Vehicle class
--- @param didBypass boolean Whether driver bypassed scale without halting
--- @return table inspectionResult { logId = number, status = string, grossWeightKg = number, maxAllowedKg = number, fine = number }
function Nyx.Vehicles.InspectWeighStation(src, plate, vehicleClass, didBypass)
    src = tonumber(src)
    plate = tostring(plate or "COMMERCIAL")
    vehicleClass = tonumber(vehicleClass) or 20
    didBypass = not not didBypass

    local player = Nyx.GetPlayer and Nyx.GetPlayer(src) or nil
    local driverId = player and player.citizenId or ("CIT_" .. (src or 0))

    -- 1. Calculate Gross Vehicle Weight Rating (GVWR)
    local trunkWeightKg = 0.0
    local palletWeightKg = 0.0
    local activeManifestId = nil
    local isContrabandFlagged = false

    -- Query loaded pallets attached to vehicle or active freight contract in nyx_logistics
    if exports['nyx_logistics'] and exports['nyx_logistics'].GetVehiclePallets then
        local ok, pallets = pcall(function() return exports['nyx_logistics']:GetVehiclePallets(plate) end)
        if ok and type(pallets) == "table" then
            for _, p in ipairs(pallets) do
                palletWeightKg = palletWeightKg + (tonumber(p.weightKg or p.weight) or 250.0)
                if p.manifestId then activeManifestId = p.manifestId end
                if p.isContraband or p.isSealedBreached then isContrabandFlagged = true end
            end
        end
    end

    -- Query active contract if manifest missing
    if not activeManifestId and exports['nyx_logistics'] and exports['nyx_logistics'].GetActiveContractForDriver then
        local ok, contract = pcall(function() return exports['nyx_logistics']:GetActiveContractForDriver(driverId) end)
        if ok and type(contract) == "table" and contract.id then
            activeManifestId = "MANIFEST_" .. contract.id
        end
    end

    local grossWeightKg = Nyx.TollsAndWeighing.CalculateGVWR(vehicleClass, trunkWeightKg, palletWeightKg)
    local maxAllowedKg = Nyx.TollsAndWeighing.GetMaxAllowedWeight(vehicleClass)
    local hasValidManifest = (activeManifestId ~= nil)

    local status = Nyx.TollsAndWeighing.DetermineInspectionStatus(
        grossWeightKg,
        maxAllowedKg,
        hasValidManifest,
        isContrabandFlagged,
        didBypass
    )

    local fine = 0.00
    if status == "OVERWEIGHT" or status == "BYPASSED" then
        fine = Nyx.TollsAndWeighing.CalculateOverweightFine(grossWeightKg, maxAllowedKg)
        if status == "BYPASSED" then
            fine = fine + 500.00 -- Bypass surcharge fine
        end
    end

    -- Insert inspection log in nyx_weigh_station_logs
    local logId = MySQL.insert.await([[
        INSERT INTO `nyx_weigh_station_logs`
            (`vehicle_plate`, `driver_identifier`, `manifest_id`, `gross_weight_kg`, `max_allowed_kg`, `overweight_fine`, `inspection_status`)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        plate,
        driverId,
        activeManifestId,
        grossWeightKg,
        maxAllowedKg,
        fine,
        status
    })

    -- Trigger automated MDT dispatch notification if BYPASSED, OVERWEIGHT, or CONTRABAND_FLAG
    if status == "BYPASSED" or status == "OVERWEIGHT" or status == "CONTRABAND_FLAG" then
        local alertTitle = "Kereskedelmi Tengelysúly-Sértés"
        local alertCode = "10-88"
        local priority = "medium"

        if status == "BYPASSED" then
            alertTitle = "Mérőállomás Megkerülése (Körözött Tehergépjármű)"
            alertCode = "10-99"
            priority = "high"
        elseif status == "CONTRABAND_FLAG" then
            alertTitle = "Gyanús Illegális Teher / Lepecsételt Raklap"
            alertCode = "10-85"
            priority = "high"
        end

        local alertDesc = string.format(
            "Jármű Rendszám: %s | Vezető: %s | Súly: %.1f kg / %.1f kg max | Bírság: $%.2f | Státusz: %s",
            plate, driverId, grossWeightKg, maxAllowedKg, fine, status
        )

        if exports['nyx_mdt'] and exports['nyx_mdt'].CreateCall then
            pcall(function()
                exports['nyx_mdt']:CreateCall(
                    alertCode,
                    alertTitle,
                    alertDesc,
                    "Automated Scale Sensor",
                    { x = 2500.0, y = 4200.0, z = 45.0 },
                    "Senora Freeway Commercial Scale Pad",
                    priority
                )
            end)
        end
    end

    return {
        logId = logId,
        status = status,
        grossWeightKg = grossWeightKg,
        maxAllowedKg = maxAllowedKg,
        fine = fine
    }
end

-- RPC Endpoints
Nyx.RPC.Register("nyx_vehicles:processToll", function(src, data)
    data = data or {}
    return Nyx.Vehicles.ProcessTollPass(src, data.plazaId, data.plate, data.vehicleClass)
end)

Nyx.RPC.Register("nyx_vehicles:inspectWeighStation", function(src, data)
    data = data or {}
    return Nyx.Vehicles.InspectWeighStation(src, data.plate, data.vehicleClass, data.didBypass)
end)

-- Register Net Events
RegisterNetEvent("nyx_vehicles:server:processToll", function(plazaId, plate, vehicleClass)
    local src = source
    Nyx.Vehicles.ProcessTollPass(src, plazaId, plate, vehicleClass)
end)

RegisterNetEvent("nyx_vehicles:server:inspectWeighStation", function(plate, vehicleClass, didBypass)
    local src = source
    Nyx.Vehicles.InspectWeighStation(src, plate, vehicleClass, didBypass)
end)
