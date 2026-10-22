--[[
    Nyxframework: nyx_vehicles
    File: server/transit_permits.lua
    Description: Authoritative server state, MySQL database persistence, treasury fee transfers,
                 permit issuance, active permit checks, and MDT violation logging.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}
Nyx.TransitPermitsServer = Nyx.TransitPermitsServer or {}

-- Generate unique transit permit identifier
local function generatePermitId(plate)
    local cleanPlate = string.gsub(tostring(plate or "HEAVY01"), "%s+", "")
    return string.format("permit_%s_%d_%d", string.lower(cleanPlate), os.time(), math.random(1000, 9999))
end

--- Purchase a commercial heavy-haul transit permit
--- @param src number Player source
--- @param plate string Vehicle license plate
--- @param permitType string ('SINGLE_TRIP', 'DAILY_PASS', 'ANNUAL_HEAVY_HAUL')
--- @param requestedMaxWeightKg number Requested max weight capacity in kg
--- @return table result { success = boolean, permitId = string, feePaid = number, expiresAt = string, error = string }
function Nyx.Vehicles.IssueTransitPermit(src, plate, permitType, requestedMaxWeightKg)
    local player = Nyx.GetPlayer and Nyx.GetPlayer(src)
    local citizenId = player and player.citizenId or ("CIT_SRC_" .. tostring(src))
    plate = string.upper(tostring(plate or "")):match("^%s*(.-)%s*$")

    if not plate or #plate == 0 then
        return { success = false, error = "INVALID_PLATE" }
    end

    permitType = tostring(permitType or "SINGLE_TRIP")
    requestedMaxWeightKg = tonumber(requestedMaxWeightKg) or 25000.0

    local feePaid, surcharge = Nyx.TransitPermits.CalculatePermitFee(permitType, requestedMaxWeightKg, 1.00)

    -- Debit player or faction treasury account
    local factionId = player and player.factionId or nil
    if exports['nyx_treasury'] and exports['nyx_treasury'].TransferFunds then
        local debitAccount = factionId and ("faction:" .. factionId) or ("char:" .. citizenId .. ":bank")
        local successTransfer = exports['nyx_treasury']:TransferFunds(debitAccount, "gov:city:master", feePaid, "transit_permit_fee", "COMMERCIAL_TRANSIT_PERMIT")
        if not successTransfer then
            return { success = false, error = "INSUFFICIENT_FUNDS" }
        end
    end

    local durationSeconds = Nyx.TransitPermits.PermitDurationsSeconds[permitType] or 86400
    local permitId = generatePermitId(plate)

    local query = [[
        INSERT INTO `nyx_commercial_transit_permits`
          (`permit_id`, `vehicle_plate`, `applicant_identifier`, `faction_id`, `permit_type`, `max_weight_capacity_kg`, `fee_paid`, `issued_at`, `expires_at`, `status`)
        VALUES
          (?, ?, ?, ?, ?, ?, ?, NOW(), DATE_ADD(NOW(), INTERVAL ? SECOND), 'ACTIVE')
    ]]

    if MySQL and MySQL.prepare then
        pcall(MySQL.prepare.await, query, { permitId, plate, citizenId, factionId, permitType, requestedMaxWeightKg, feePaid, durationSeconds })
    end

    return {
        success = true,
        permitId = permitId,
        vehiclePlate = plate,
        permitType = permitType,
        maxWeightCapacityKg = requestedMaxWeightKg,
        feePaid = feePaid,
        surchargePaid = surcharge,
        status = "ACTIVE"
    }
end

--- Get active transit permit for a vehicle plate
--- @param plate string Vehicle license plate
--- @return table|nil permit Active permit record if valid
function Nyx.Vehicles.GetActiveTransitPermit(plate)
    plate = string.upper(tostring(plate or "")):match("^%s*(.-)%s*$")
    if not plate or #plate == 0 then return nil end

    local query = [[
        SELECT `permit_id`, `vehicle_plate`, `applicant_identifier`, `faction_id`, `permit_type`,
               `max_weight_capacity_kg`, `fee_paid`, `status`, UNIX_TIMESTAMP(`expires_at`) AS `expires_at_epoch`
        FROM `nyx_commercial_transit_permits`
        WHERE `vehicle_plate` = ? AND `status` = 'ACTIVE' AND `expires_at` > NOW()
        ORDER BY `max_weight_capacity_kg` DESC
        LIMIT 1
    ]]

    if MySQL and MySQL.single then
        local ok, row = pcall(MySQL.single.await, query, { plate })
        if ok and row then
            return row
        end
    end

    return nil
end

--- Audit log a commercial permit violation and notify MDT dispatch
--- @param plate string Vehicle license plate
--- @param driverIdentifier string Driver citizen ID or source
--- @param measuredWeightKg number Measured weight
--- @param permittedWeightKg number Allowed permitted weight
--- @param violationType string Violation classification
--- @param assessedFine number Fine amount
--- @return boolean success
function Nyx.Vehicles.LogPermitViolation(plate, driverIdentifier, measuredWeightKg, permittedWeightKg, violationType, assessedFine)
    plate = string.upper(tostring(plate or "")):match("^%s*(.-)%s*$")
    measuredWeightKg = tonumber(measuredWeightKg) or 0.0
    permittedWeightKg = tonumber(permittedWeightKg) or 0.0
    assessedFine = tonumber(assessedFine) or 0.0

    local query = [[
        INSERT INTO `nyx_permit_violation_logs`
          (`vehicle_plate`, `driver_identifier`, `measured_weight_kg`, `permitted_weight_kg`, `violation_type`, `assessed_fine`, `timestamp`)
        VALUES
          (?, ?, ?, ?, ?, ?, NOW())
    ]]

    if MySQL and MySQL.prepare then
        pcall(MySQL.prepare.await, query, { plate, driverIdentifier or "UNKNOWN", measuredWeightKg, permittedWeightKg, violationType, assessedFine })
    end

    -- Trigger MDT police dispatch alert for commercial violation
    TriggerEvent("nyx:mdt:server:dispatchAlert", {
        code = "COMMERCIAL_PERMIT_VIOLATION",
        title = "Commercial Heavy Transit Violation",
        details = string.format("Plate: %s | Type: %s | Weight: %.1f kg vs Permitted: %.1f kg | Fine: $%.2f",
            plate, violationType, measuredWeightKg, permittedWeightKg, assessedFine),
        plate = plate
    })

    return true
end

-- RPC Handlers
if Nyx and Nyx.RPC and Nyx.RPC.Register then
    Nyx.RPC.Register("vehicles:transit:issuePermit", function(src, payload)
        if not payload or not payload.plate then
            return { success = false, error = "INVALID_PAYLOAD" }
        end
        return Nyx.Vehicles.IssueTransitPermit(src, payload.plate, payload.permitType, payload.maxWeightCapacityKg)
    end)

    Nyx.RPC.Register("vehicles:transit:checkPermit", function(src, payload)
        if not payload or not payload.plate then
            return { isValid = false, status = "NO_PERMIT" }
        end
        local permit = Nyx.Vehicles.GetActiveTransitPermit(payload.plate)
        local isValid, status = Nyx.TransitPermits.EvaluatePermitValidity(permit, payload.measuredWeightKg, os.time())
        return { isValid = isValid, status = status, permit = permit }
    end)
end
