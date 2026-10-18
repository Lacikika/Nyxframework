--[[
    Nyxframework: nyx_vehicles
    File: server/diagnostics.lua
    Description: Authoritative server diagnostics engine, OBD-II scanner integration,
                 wear telemetry aggregation, and civic impound terminal dispatcher.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}

--- Helper to safely encode JSON
local function safeJsonEncode(tbl)
    if not tbl then return "[]" end
    local ok, res = pcall(json.encode, tbl)
    return ok and res or "[]"
end

--- 1. Aggregates complete diagnostics overview for player / vehicle
--- @param src number
--- @param identifier string|nil (vin, plate, or nil)
--- @return table overview
function Nyx.Vehicles.GetDiagnosticsOverview(src, identifier)
    local player = exports['nyx_core'] and exports['nyx_core']:GetPlayer(src)
    if not player then
        return { success = false, error = "UNAUTHENTICATED" }
    end

    local fiscalTier = "solvent"
    if exports['nyx_treasury'] and exports['nyx_treasury'].GetMunicipalFiscalTier then
        fiscalTier = exports['nyx_treasury']:GetMunicipalFiscalTier()
    end

    -- If no identifier provided, check if player is currently seated in a spawned vehicle
    local resolvedVin = identifier and Nyx.Vehicles.ResolveVIN(identifier) or nil
    local activeEntity = nil

    if not resolvedVin and Nyx.Vehicles.Active then
        -- Attempt to find by player's active vehicle or seat
        local ped = GetPlayerPed(src)
        if ped and DoesEntityExist(ped) then
            local veh = GetVehiclePedIsIn(ped, false)
            if veh and veh ~= 0 then
                for vVin, activeData in pairs(Nyx.Vehicles.Active) do
                    if activeData.entity == veh then
                        resolvedVin = vVin
                        activeEntity = veh
                        break
                    end
                end
            end
        end
    end

    -- If still no VIN, pick the player's first registered owned vehicle
    if not resolvedVin then
        local firstOwned = MySQL.single.await([[
            SELECT `vin` FROM `nyx_vehicles_owned`
            WHERE `owner_citizen_id` = ?
            ORDER BY `updated_at` DESC LIMIT 1
        ]], { player.citizenId })
        if firstOwned then
            resolvedVin = firstOwned.vin
        end
    end

    local telemetry = nil
    if resolvedVin then
        local wear = Nyx.Vehicles.GetWear(resolvedVin)
        local owned = MySQL.single.await([[
            SELECT `vin`, `plate`, `model_name`, `storage_state`, `garage_id`, `impound_lot_id`,
                   `registration_status`, `registration_expires_at`
            FROM `nyx_vehicles_owned` WHERE `vin` = ?
        ]], { resolvedVin })

        local engHealth = 1000.0
        if Nyx.Vehicles.Active and Nyx.Vehicles.Active[resolvedVin] then
            local active = Nyx.Vehicles.Active[resolvedVin]
            if active.entity and DoesEntityExist(active.entity) then
                engHealth = GetVehicleEngineHealth(active.entity)
            end
        end

        local oil = wear and wear.oilQuality or 100.0
        local brakes = wear and wear.brakePadWear or 100.0
        local trans = wear and wear.transmissionWear or 100.0
        local susp = wear and wear.suspensionWear or 100.0

        local grade, composite, isRoadworthy = Nyx.VehicleDiagnostics.CalculateOverallGrade(engHealth, oil, brakes, trans, susp)
        local dtcCodes = Nyx.VehicleDiagnostics.GenerateDiagnosticCodes(wear, engHealth)

        local regData = Nyx.Vehicles.GetVehicleRegistration and Nyx.Vehicles.GetVehicleRegistration(resolvedVin) or nil

        -- Fetch recent 5 service logs
        local serviceLogs = MySQL.query.await([[
            SELECT `log_id`, `service_type`, `mileage_at_service`, `cost`, `notes`, `created_at`
            FROM `nyx_vehicles_service_logs`
            WHERE `vin` = ?
            ORDER BY `created_at` DESC LIMIT 5
        ]], { resolvedVin }) or {}

        -- Fetch recent 5 diagnostic scans
        local diagScans = MySQL.query.await([[
            SELECT `scan_uuid`, `mileage`, `engine_health`, `overall_grade`, `notes`, `scanned_at`
            FROM `nyx_vehicles_diagnostic_scans`
            WHERE `vin` = ?
            ORDER BY `scanned_at` DESC LIMIT 5
        ]], { resolvedVin }) or {}

        telemetry = {
            vin = resolvedVin,
            plate = (owned and owned.plate) or (wear and wear.plate) or "UNKNOWN",
            modelName = (owned and owned.model_name) or "Vehicle",
            mileage = wear and wear.mileage or 0.0,
            tripOdometer = wear and wear.tripOdometer or 0.0,
            engineHealth = engHealth,
            oilQuality = oil,
            brakePadWear = brakes,
            transmissionWear = trans,
            suspensionWear = susp,
            overallGrade = grade,
            compositeScore = composite,
            isRoadworthy = isRoadworthy,
            dtcCodes = dtcCodes,
            registration = regData,
            serviceLogs = serviceLogs,
            diagnosticScans = diagScans,
            lastServiceMileage = wear and wear.lastServiceMileage or 0.0,
            serviceNotes = wear and wear.serviceNotes or ""
        }
    end

    -- Query all owned vehicles for the player
    local ownedRows = MySQL.query.await([[
        SELECT `vin`, `plate`, `model_name`, `storage_state`, `garage_id`, `impound_lot_id`,
               `impound_fee`, `impound_reason`, `impounded_at`, `registration_status`, `registration_expires_at`
        FROM `nyx_vehicles_owned`
        WHERE `owner_citizen_id` = ?
        ORDER BY `storage_state` ASC, `plate` ASC
    ]], { player.citizenId }) or {}

    local ownedVehicles = {}
    local impoundedVehicles = {}

    local now = os.time()
    for _, r in ipairs(ownedRows) do
        local isImp = (r.storage_state == "impounded")
        local item = {
            vin = r.vin,
            plate = r.plate,
            modelName = r.model_name,
            storageState = r.storage_state,
            garageId = r.garage_id,
            registrationStatus = r.registration_status,
            registrationExpiresAt = r.registration_expires_at
        }

        if isImp then
            local lot = Nyx.Vehicles.ImpoundLots and (Nyx.Vehicles.ImpoundLots[r.impound_lot_id] or Nyx.Vehicles.ImpoundLots["impound_lot_ls"])
            local impAt = tonumber(r.impounded_at) or now
            local elapsedDays = math.floor(math.max(0, now - impAt) / 86400)
            local baseFee = tonumber(r.impound_fee) or (lot and lot.baseFee or 500.00)
            local dailyRate = lot and lot.dailyRate or 150.00

            local costCalc = Nyx.VehicleDiagnostics.CalculateImpoundTotals(baseFee, elapsedDays, dailyRate, fiscalTier)
            item.impoundLotId = r.impound_lot_id
            item.lotLabel = lot and lot.label or "Municipal Lot"
            item.impoundReason = r.impound_reason or "Municipal impound"
            item.impoundedAt = impAt
            item.cost = costCalc

            table.insert(impoundedVehicles, item)
        else
            table.insert(ownedVehicles, item)
        end
    end

    return {
        success = true,
        telemetry = telemetry,
        ownedVehicles = ownedVehicles,
        impoundedVehicles = impoundedVehicles,
        fiscalTier = fiscalTier,
        impoundLots = Nyx.Vehicles.ImpoundLots or {},
        serviceCatalog = Nyx.VehicleDiagnostics.SERVICE_CATALOG
    }
end

--- 2. Executes a Certified OBD-II Diagnostic Scan
--- @param src number
--- @param vinOrPlate string
--- @param notes string|nil
--- @return table scanResult
function Nyx.Vehicles.ScanVehicle(src, vinOrPlate, notes)
    local player = exports['nyx_core'] and exports['nyx_core']:GetPlayer(src)
    if not player then
        return { success = false, error = "UNAUTHENTICATED" }
    end

    local vin = Nyx.Vehicles.ResolveVIN(vinOrPlate)
    if not vin then
        return { success = false, error = "VEHICLE_NOT_FOUND" }
    end

    local wear = Nyx.Vehicles.GetWear(vin)
    if not wear then
        return { success = false, error = "WEAR_DATA_UNAVAILABLE" }
    end

    local engHealth = 1000.0
    if Nyx.Vehicles.Active and Nyx.Vehicles.Active[vin] then
        local active = Nyx.Vehicles.Active[vin]
        if active.entity and DoesEntityExist(active.entity) then
            engHealth = GetVehicleEngineHealth(active.entity)
        end
    end

    local oil = wear.oilQuality or 100.0
    local brakes = wear.brakePadWear or 100.0
    local trans = wear.transmissionWear or 100.0
    local susp = wear.suspensionWear or 100.0

    local grade, composite, isRoadworthy = Nyx.VehicleDiagnostics.CalculateOverallGrade(engHealth, oil, brakes, trans, susp)
    local dtcCodes = Nyx.VehicleDiagnostics.GenerateDiagnosticCodes(wear, engHealth)

    local scanUuid = string.format("scan_%d_%d", os.time(), math.random(1000, 9999))
    local noteText = notes or string.format("OBD-II Scan executed by %s", player.name or player.citizenId)

    local dtcJson = safeJsonEncode(dtcCodes)

    MySQL.prepare.await([[
        INSERT INTO `nyx_vehicles_diagnostic_scans`
        (`scan_uuid`, `vin`, `plate`, `mechanic_citizen_id`, `mileage`, `engine_health`,
         `oil_quality`, `brake_pad_wear`, `transmission_wear`, `suspension_wear`,
         `overall_grade`, `diagnostic_trouble_codes`, `notes`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        scanUuid,
        vin,
        wear.plate or "UNKNOWN",
        player.citizenId,
        wear.mileage,
        engHealth,
        oil,
        brakes,
        trans,
        susp,
        grade,
        dtcJson,
        noteText
    })

    -- Update inspection certification in nyx_vehicles_wear
    local inspStatus = isRoadworthy and "passed" or (grade == "critical" and "warning" or "failed")
    local now = os.time()
    MySQL.prepare.await([[
        UPDATE `nyx_vehicles_wear`
        SET `inspection_status` = ?,
            `last_inspection_at` = ?,
            `inspector_citizen_id` = ?,
            `inspection_notes` = ?
        WHERE `vin` = ?
    ]], { inspStatus, now, player.citizenId, noteText, vin })

    return {
        success = true,
        scanUuid = scanUuid,
        vin = vin,
        plate = wear.plate,
        mileage = wear.mileage,
        engineHealth = engHealth,
        oilQuality = oil,
        brakePadWear = brakes,
        transmissionWear = trans,
        suspensionWear = susp,
        overallGrade = grade,
        compositeScore = composite,
        isRoadworthy = isRoadworthy,
        inspectionStatus = inspStatus,
        dtcCodes = dtcCodes,
        scannedAt = now
    }
end

--- 3. Executes certified service with component restoration
--- @param src number
--- @param payload table
--- @return table serviceResult
function Nyx.Vehicles.PerformCertifiedService(src, payload)
    local okPayload, errPayload = Nyx.VehicleDiagnostics.ValidateServicePayload(payload)
    if not okPayload then
        return { success = false, error = errPayload }
    end

    local vin = Nyx.Vehicles.ResolveVIN(payload.vin or payload.plate)
    if not vin then
        return { success = false, error = "VEHICLE_NOT_FOUND" }
    end

    local serviceType = payload.serviceType
    local notes = payload.notes

    if serviceType == "full_service" then
        -- Execute each individual component service and full overhaul
        local okOil = Nyx.Vehicles.ServiceVehicle(src, vin, "oil_change", notes)
        local okBrk = Nyx.Vehicles.ServiceVehicle(src, vin, "brake_replacement", notes)
        local okTrn = Nyx.Vehicles.ServiceVehicle(src, vin, "transmission_overhaul", notes)
        local okSus = Nyx.Vehicles.ServiceVehicle(src, vin, "suspension_tune", notes)

        -- If vehicle is currently active, also restore engine health
        if Nyx.Vehicles.Active and Nyx.Vehicles.Active[vin] then
            local active = Nyx.Vehicles.Active[vin]
            if active.entity and DoesEntityExist(active.entity) then
                SetVehicleEngineHealth(active.entity, 1000.0)
            end
        end

        local wear = Nyx.Vehicles.GetWear(vin)
        return {
            success = true,
            vin = vin,
            serviceType = "full_service",
            wear = wear
        }
    else
        local okService, res = Nyx.Vehicles.ServiceVehicle(src, vin, serviceType, notes)
        if not okService then
            return { success = false, error = res }
        end
        return {
            success = true,
            vin = vin,
            serviceType = serviceType,
            data = res
        }
    end
end

-- 4. RPC Dispatcher Binding
CreateThread(function()
    if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
        -- Diagnostics Overview
        exports['nyx_core']:RegisterRPC("vehicles:getDiagnosticsOverview", function(src, vinOrIdentifier)
            return Nyx.Vehicles.GetDiagnosticsOverview(src, vinOrIdentifier)
        end)

        -- OBD-II Diagnostic Scan
        exports['nyx_core']:RegisterRPC("vehicles:scanVehicle", function(src, payload)
            local vin = payload and (payload.vin or payload.plate)
            local notes = payload and payload.notes
            return Nyx.Vehicles.ScanVehicle(src, vin, notes)
        end)

        -- Perform Certified Service
        exports['nyx_core']:RegisterRPC("vehicles:performCertifiedService", function(src, payload)
            return Nyx.Vehicles.PerformCertifiedService(src, payload)
        end)

        -- Civic Impound Lots Registry
        exports['nyx_core']:RegisterRPC("vehicles:getCivicImpoundLots", function(src)
            return { success = true, lots = Nyx.Vehicles.ImpoundLots or {} }
        end)
    end
end)
