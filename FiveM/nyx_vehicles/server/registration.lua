--[[
    Nyxframework: nyx_vehicles
    File: server/registration.lua
    Description: Authoritative vehicle registration renewal, statutory late fines,
                 and closed-loop treasury fee processing.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}

--- Queries vehicle registration status and renewal pricing.
--- @param vin string
--- @return table|nil registrationData
function Nyx.Vehicles.GetVehicleRegistration(vin)
    if not vin then return nil end

    local row = MySQL.single.await([[
        SELECT `vin`, `plate`, `model_name`, `owner_citizen_id`,
               `registration_status`, `registration_expires_at`
        FROM `nyx_vehicles_owned`
        WHERE `vin` = ?
    ]], { vin })

    if not row then return nil end

    local now = os.time()
    local exp = tonumber(row.registration_expires_at) or 0
    local rawStatus = row.registration_status or "valid"

    local currentStatus = Nyx.Registration.EvaluateStatus(rawStatus, exp, now)
    local isExpired = (currentStatus == "expired")
    local daysExpired = 0
    if isExpired and exp > 0 then
        daysExpired = math.floor((now - exp) / 86400)
    end

    local feeData = Nyx.Registration.CalculateRenewalFee(row.model_name or "sedan", isExpired, daysExpired)

    return {
        vin = row.vin,
        plate = row.plate,
        modelName = row.model_name,
        ownerCitizenId = row.owner_citizen_id,
        status = currentStatus,
        expiresAt = exp,
        isExpired = isExpired,
        daysExpired = daysExpired,
        fee = feeData
    }
end

--- Renews a vehicle registration authoritatively, executing double-entry transfer to municipal treasury.
--- @param src number
--- @param vin string
--- @return boolean success
--- @return table|string resultOrError
function Nyx.Vehicles.RenewVehicleRegistration(src, vin)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local regData = Nyx.Vehicles.GetVehicleRegistration(vin)
    if not regData then return false, "VEHICLE_NOT_FOUND" end

    if regData.ownerCitizenId ~= player.citizenId and not (player.hasPermission and player.hasPermission("admin")) then
        return false, "UNAUTHORIZED_NOT_OWNER"
    end

    if regData.status == "suspended" then
        return false, "REGISTRATION_SUSPENDED_BY_COURT_OR_POLICE"
    end

    local totalFee = regData.fee.totalFee
    local playerBankAcc = string.format("char:%s:bank", player.citizenId)
    local masterCityAcc = "gov:city:master"

    local currentBal = exports['nyx_treasury']:GetAccountBalance(playerBankAcc) or 0.00
    if currentBal < totalFee then
        return false, string.format("INSUFFICIENT_FUNDS_REQUIRED_%.2f", totalFee)
    end

    local okTransfer, txId = exports['nyx_treasury']:ExecuteTransfer(
        playerBankAcc,
        masterCityAcc,
        totalFee,
        "vehicle_registration",
        "registration:" .. vin,
        string.format("Registration renewal for %s [%s] (Base: $%.2f, Late Fine: $%.2f)",
            regData.modelName or "Vehicle", regData.plate, regData.fee.baseFee, regData.fee.latePenalty),
        0.00
    )

    if not okTransfer then
        return false, "TREASURY_TRANSFER_FAILED"
    end

    local now = os.time()
    local duration = regData.fee.durationSeconds or (14 * 86400)
    local newExpiry = math.max(now, regData.expiresAt) + duration

    MySQL.prepare.await([[
        UPDATE `nyx_vehicles_owned`
        SET `registration_status` = 'valid',
            `registration_expires_at` = ?
        WHERE `vin` = ?
    ]], { newExpiry, vin })

    -- Trigger municipal solvency re-evaluation
    if exports['nyx_treasury'] and exports['nyx_treasury'].EvaluateMunicipalFiscalState then
        exports['nyx_treasury']:EvaluateMunicipalFiscalState()
    end

    return true, {
        vin = vin,
        plate = regData.plate,
        previousStatus = regData.status,
        newStatus = "valid",
        newExpiresAt = newExpiry,
        totalPaid = totalFee,
        txId = txId
    }
end

-- RPC Handlers
if Nyx.RPC and Nyx.RPC.Register then
    Nyx.RPC.Register("vehicles:getRegistration", function(src, payload)
        if not payload or not payload.vin then return nil end
        return Nyx.Vehicles.GetVehicleRegistration(payload.vin)
    end)

    Nyx.RPC.Register("vehicles:renewRegistration", function(src, payload)
        if not payload or not payload.vin then return false, "MISSING_VIN" end
        return Nyx.Vehicles.RenewVehicleRegistration(src, payload.vin)
    end)
end
