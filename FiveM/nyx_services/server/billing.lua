--[[
    Nyxframework: nyx_services
    File: server/billing.lua
    Description: Metered utility consumption simulation, automatic billing cycle,
                 delinquency tracking, and service suspension enforcement.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}

-- 1. Register a new property utility meter
function Nyx.Services.RegisterMeter(meterId, ownerCitizenId, linkedSubstationId, propertyType)
    if not meterId or not ownerCitizenId or not linkedSubstationId then
        return false, "MISSING_METER_FIELDS"
    end

    local allowed = { ['residential'] = true, ['commercial'] = true, ['industrial'] = true }
    local pType = allowed[propertyType] and propertyType or "residential"

    local success = MySQL.prepare.await([[
        INSERT INTO `nyx_services_utility_meters`
            (`meter_id`, `owner_citizen_id`, `linked_substation_id`, `property_type`)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `owner_citizen_id` = VALUES(`owner_citizen_id`),
            `linked_substation_id` = VALUES(`linked_substation_id`),
            `property_type` = VALUES(`property_type`)
    ]], { meterId, ownerCitizenId, linkedSubstationId, pType })

    return (success ~= nil), meterId
end

-- 2. Record metered consumption delta (kWh & Water)
function Nyx.Services.RecordConsumption(meterId, kwhDelta, waterDelta)
    local kwh = math.max(0.00, tonumber(kwhDelta) or 0.00)
    local water = math.max(0.00, tonumber(waterDelta) or 0.00)

    local affected = MySQL.update.await([[
        UPDATE `nyx_services_utility_meters`
        SET `kwh_consumed` = `kwh_consumed` + ?,
            `water_consumed` = `water_consumed` + ?
        WHERE `meter_id` = ? AND `is_service_suspended` = 0
    ]], { kwh, water, meterId })

    return (affected and affected > 0)
end

-- 3. Run Automated Public Utility Billing Cycle
function Nyx.Services.ProcessUtilityBillingCycle()
    local meters = MySQL.query.await("SELECT * FROM `nyx_services_utility_meters`")
    if not meters or #meters == 0 then return end

    local kwhRate = Config.Billing.KwhTariff or 0.15
    local waterRate = Config.Billing.WaterTariff or 0.05
    local destAcc = Config.Billing.PublicWorksAccount or "gov:dept:works"
    local cutoffThreshold = Config.Billing.SuspensionThreshold or 2500.00

    local settledCount = 0
    local suspendedCount = 0

    for _, m in ipairs(meters) do
        -- Simulate baseline usage per profile if idle
        local profile = Config.Billing.ConsumptionProfiles[m.property_type] or { kwh = 120.0, water = 80.0 }
        local kwhConsumed = (tonumber(m.kwh_consumed) or 0.00) + profile.kwh
        local waterConsumed = (tonumber(m.water_consumed) or 0.00) + profile.water

        local newCharges = math.floor(((kwhConsumed * kwhRate) + (waterConsumed * waterRate)) * 100) / 100
        local totalDue = newCharges + (tonumber(m.unpaid_balance) or 0.00)

        if totalDue > 0.00 then
            local ownerAcc = "citizen:" .. m.owner_citizen_id
            local ownerBal = exports['nyx_treasury']:GetAccountBalance(ownerAcc) or 0.00

            if ownerBal >= totalDue then
                -- Direct Settlement
                local ok, txId = exports['nyx_treasury']:ExecuteTransfer(
                    ownerAcc,
                    destAcc,
                    totalDue,
                    "utility_bill",
                    "meter:" .. m.meter_id,
                    string.format("Public Utility Settlement (Power & Water: %s)", m.meter_id),
                    0.0
                )

                if ok then
                    settledCount = settledCount + 1
                    MySQL.prepare.await([[
                        UPDATE `nyx_services_utility_meters`
                        SET `kwh_consumed` = 0.00,
                            `water_consumed` = 0.00,
                            `unpaid_balance` = 0.00,
                            `is_service_suspended` = 0
                        WHERE `meter_id` = ?
                    ]], { m.meter_id })
                end
            else
                -- Insufficient liquidity -> Record arrears and evaluate cutoff
                local newUnpaid = totalDue
                local isSuspended = (newUnpaid >= cutoffThreshold) and 1 or tonumber(m.is_service_suspended)

                if isSuspended == 1 and tonumber(m.is_service_suspended) == 0 then
                    suspendedCount = suspendedCount + 1
                    local player = Nyx.GetPlayerByCitizenId(m.owner_citizen_id)
                    if player then
                        TriggerClientEvent("nyx:ui:notify", player.source, {
                            type = "error",
                            title = "UTILITY SERVICE SUSPENDED",
                            message = string.format("Power & water cut off for property %s. Arrears: $%.2f", m.meter_id, newUnpaid)
                        })
                    end
                end

                MySQL.prepare.await([[
                    UPDATE `nyx_services_utility_meters`
                    SET `kwh_consumed` = 0.00,
                        `water_consumed` = 0.00,
                        `unpaid_balance` = ?,
                        `is_service_suspended` = ?
                    WHERE `meter_id` = ?
                ]], { newUnpaid, isSuspended, m.meter_id })
            end
        end
    end

    if Config.Debug then
        print(string.format("^2[Nyx:Services]^7 Billing Cycle Complete: %d meters settled, %d newly suspended.^7",
            settledCount, suspendedCount))
    end
end

-- 4. Manual bill payment / arrears settlement
function Nyx.Services.PayUtilityBill(src, meterId, amount)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local meter = MySQL.single.await("SELECT * FROM `nyx_services_utility_meters` WHERE `meter_id` = ?", { meterId })
    if not meter then return false, "METER_NOT_FOUND" end

    local unpaid = tonumber(meter.unpaid_balance) or 0.00
    if unpaid <= 0.00 then
        return false, "NO_OUTSTANDING_BALANCE"
    end

    local payAmount = math.min(unpaid, tonumber(amount) or unpaid)
    local ownerAcc = "citizen:" .. player.citizenId
    local destAcc = Config.Billing.PublicWorksAccount or "gov:dept:works"

    local ok, txId = exports['nyx_treasury']:ExecuteTransfer(
        ownerAcc,
        destAcc,
        payAmount,
        "utility_settlement",
        "meter:" .. meterId,
        "Manual Arrears Payment for Utilities",
        0.0
    )

    if not ok then
        return false, "INSUFFICIENT_FUNDS"
    end

    local remaining = unpaid - payAmount
    local isSuspended = (remaining >= (Config.Billing.SuspensionThreshold or 2500.00)) and 1 or 0

    MySQL.prepare.await([[
        UPDATE `nyx_services_utility_meters`
        SET `unpaid_balance` = ?, `is_service_suspended` = ?
        WHERE `meter_id` = ?
    ]], { remaining, isSuspended, meterId })

    return true, {
        meterId = meterId,
        paid = payAmount,
        remaining = remaining,
        isSuspended = (isSuspended == 1)
    }
end

-- 5. Query meter status
function Nyx.Services.GetMeter(meterId)
    return MySQL.single.await("SELECT * FROM `nyx_services_utility_meters` WHERE `meter_id` = ?", { meterId })
end
