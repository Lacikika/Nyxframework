--[[
    Nyxframework: nyx_services & nyx_properties
    File: server/billing.lua
    Description: Authoritative municipal utility metering, continuous kilowatt-hour and water
                 consumption simulation, automated billing cycles, double-entry treasury settlements,
                 delinquency state machine enforcement, and power cut-off interlocks.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}

-- 1. Register or update a property utility meter
function Nyx.Services.RegisterMeter(meterId, ownerCitizenId, linkedSubstationId, propertyType, propertyId)
    if not meterId or not ownerCitizenId or not linkedSubstationId then
        return false, "MISSING_METER_FIELDS"
    end

    local allowed = { ['residential'] = true, ['commercial'] = true, ['industrial'] = true }
    local pType = allowed[propertyType] and propertyType or "residential"
    local propId = tonumber(propertyId)

    local success = MySQL.prepare.await([[
        INSERT INTO `nyx_services_utility_meters`
            (`meter_id`, `owner_citizen_id`, `property_id`, `linked_substation_id`, `property_type`)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `owner_citizen_id` = VALUES(`owner_citizen_id`),
            `property_id` = COALESCE(VALUES(`property_id`), `property_id`),
            `linked_substation_id` = VALUES(`linked_substation_id`),
            `property_type` = VALUES(`property_type`)
    ]], { meterId, ownerCitizenId, propId, linkedSubstationId, pType })

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

-- 3. Calculate Aggregate Real-Time Substation Grid Load (MW)
function Nyx.Services.GetSubstationGridLoad(substationId)
    substationId = tostring(substationId or "grid_central_ls")
    local s = Nyx.Services.GetSubstation(substationId)
    local maxCap = s and s.peakLoadMw or 75.00

    local meters = MySQL.query.await([[
        SELECT m.*, p.`land_area_sqm`, p.`has_backup_generator`
        FROM `nyx_services_utility_meters` m
        LEFT JOIN `nyx_properties` p ON m.`property_id` = p.`property_id`
        WHERE m.`linked_substation_id` = ?
    ]], { substationId }) or {}

    local connectedList = {}
    for _, m in ipairs(meters) do
        table.insert(connectedList, {
            propertyType = m.property_type,
            isUtilitySuspended = (tonumber(m.is_service_suspended) == 1),
            hasBackupGenerator = (tonumber(m.has_backup_generator) == 1),
            landAreaSqm = tonumber(m.land_area_sqm) or 150.00
        })
    end

    local aggregateMw, metrics = Nyx.Metering.CalculateSubstationGridDraw(substationId, connectedList, maxCap)

    -- If aggregate load exceeds substation capacity, trip circuit breaker!
    if metrics.isOverloaded and s and not s.breakerTripped then
        s.breakerTripped = true
        s.failureReason = "overload_trip"
        if Nyx.Services.EvaluateSubstationState then
            Nyx.Services.EvaluateSubstationState(s, true)
        end
        print(string.format("^1[Nyx:Services:PowerGrid] GRID OVERLOAD: Substation '%s' tripped! Current load %.2f MW exceeds capacity %.2f MW.^7",
            substationId, aggregateMw, maxCap))
    end

    return aggregateMw, metrics
end

-- 4. Run Automated Municipal Utility Billing Cycle
function Nyx.Services.ProcessUtilityBillingCycle()
    local meters = MySQL.query.await([[
        SELECT m.*, p.`land_area_sqm`, p.`label` AS `property_label`, p.`has_backup_generator`
        FROM `nyx_services_utility_meters` m
        LEFT JOIN `nyx_properties` p ON m.`property_id` = p.`property_id`
    ]])
    if not meters or #meters == 0 then return end

    local kwhTariff = (Config.Billing and Config.Billing.KwhTariff) or Nyx.Metering.Config.DefaultKwhTariff
    local waterTariff = (Config.Billing and Config.Billing.WaterTariff) or Nyx.Metering.Config.DefaultWaterTariff
    local destAcc = (Config.Billing and Config.Billing.PublicWorksAccount) or Nyx.Metering.Config.PublicWorksAccount
    local cutoffThreshold = (Config.Billing and Config.Billing.SuspensionThreshold) or Nyx.Metering.Config.SuspensionThreshold

    local settledCount = 0
    local newlySuspendedCount = 0
    local totalRevenueCollected = 0.00

    for _, m in ipairs(meters) do
        -- Simulate continuous usage delta based on property profile, land footprint & weather
        local landArea = tonumber(m.land_area_sqm) or 150.00
        local weather = (GlobalState and GlobalState.weather) or "CLEAR"
        local deltaKwh, deltaWater = Nyx.Metering.CalculateConsumptionDelta(m.property_type, landArea, 0, weather, 1.0)

        local currentKwh = (tonumber(m.kwh_consumed) or 0.00) + deltaKwh
        local currentWater = (tonumber(m.water_consumed) or 0.00) + deltaWater
        local unpaidArrears = tonumber(m.unpaid_balance) or 0.00
        local missedCycles = tonumber(m.consecutive_unpaid_cycles) or 0

        -- Grid stress multiplier from substation state
        local sub = Nyx.Services.GetSubstation(m.linked_substation_id)
        local stressMult = 1.00
        if sub and sub.fuelLevel and sub.fuelLevel < 20.00 then
            stressMult = 1.25 -- Scarcity surcharge
        end

        local bill = Nyx.Metering.CalculateUtilityBill({
            kwhConsumed = currentKwh,
            waterConsumed = currentWater,
            kwhTariff = kwhTariff,
            waterTariff = waterTariff,
            unpaidArrears = unpaidArrears,
            missedCycles = missedCycles,
            isReconnecting = false,
            gridStressMultiplier = stressMult,
            customCutoff = cutoffThreshold
        })

        local nowTime = os.time()
        local invUuid = Nyx.Metering.GenerateInvoiceUuid(m.meter_id, nowTime, math.random(100, 999))
        local ownerAcc = "citizen:" .. m.owner_citizen_id
        local ownerBal = exports['nyx_treasury'] and exports['nyx_treasury']:GetAccountBalance(ownerAcc) or 0.00

        if bill.totalDue > 0.00 and ownerBal >= bill.totalDue then
            -- 4.1 Direct Treasury Settlement (Double-Entry Transfer)
            local ok, txId = exports['nyx_treasury']:ExecuteTransfer(
                ownerAcc,
                destAcc,
                bill.totalDue,
                "utility_bill",
                "meter:" .. m.meter_id,
                string.format("Municipal Utility Settlement (%s: %s)", m.property_type, m.meter_id),
                0.0
            )

            if ok then
                settledCount = settledCount + 1
                totalRevenueCollected = totalRevenueCollected + bill.totalDue

                -- Insert Paid Invoice
                MySQL.prepare.await([[
                    INSERT INTO `nyx_services_utility_invoices`
                        (`invoice_uuid`, `meter_id`, `property_id`, `owner_citizen_id`, `substation_id`,
                         `cycle_period_start`, `cycle_period_end`, `kwh_consumed`, `water_consumed`,
                         `kwh_tariff`, `water_tariff`, `energy_charge`, `water_charge`,
                         `late_penalty`, `reconnect_fee`, `total_due`, `amount_paid`,
                         `status`, `treasury_tx_uuid`, `paid_at`)
                    VALUES (?, ?, ?, ?, ?, NOW() - INTERVAL 30 MINUTE, NOW(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'paid', ?, NOW())
                ]], {
                    invUuid, m.meter_id, m.property_id, m.owner_citizen_id, m.linked_substation_id,
                    bill.kwhConsumed, bill.waterConsumed, bill.kwhTariff, bill.waterTariff,
                    bill.energyCharge, bill.waterCharge, bill.latePenalty, bill.reconnectFee,
                    bill.totalDue, bill.totalDue, txId
                })

                -- Reset meter counters and restore service if previously suspended
                local wasSuspended = (tonumber(m.is_service_suspended) == 1)
                MySQL.prepare.await([[
                    UPDATE `nyx_services_utility_meters`
                    SET `kwh_consumed` = 0.00,
                        `water_consumed` = 0.00,
                        `unpaid_balance` = 0.00,
                        `last_reading_kwh` = ?,
                        `last_reading_water` = ?,
                        `last_billed_at` = NOW(),
                        `consecutive_unpaid_cycles` = 0,
                        `delinquency_tier` = 0,
                        `meter_status` = 'active',
                        `is_service_suspended` = 0,
                        `reconnected_at` = IF(? = 1, NOW(), `reconnected_at`)
                    WHERE `meter_id` = ?
                ]], { currentKwh, currentWater, wasSuspended and 1 or 0, m.meter_id })

                if wasSuspended then
                    -- Synchronize property engine
                    if m.property_id then
                        MySQL.prepare.await([[
                            UPDATE `nyx_properties`
                            SET `is_utility_suspended` = 0, `utility_status` = 'normal'
                            WHERE `property_id` = ?
                        ]], { m.property_id })

                        MySQL.prepare.await([[
                            INSERT INTO `nyx_property_audit`
                                (`property_id`, `action`, `actor_citizen_id`, `amount`, `notes`)
                            VALUES (?, 'UTILITY_RECONNECTED', ?, ?, 'Utility service restored after billing cycle settlement')
                        ]], { m.property_id, m.owner_citizen_id, bill.totalDue })
                    end

                    local logUuid = Nyx.Metering.GenerateLogUuid("RECN", nowTime, math.random(100, 999))
                    MySQL.prepare.await([[
                        INSERT INTO `nyx_services_utility_delinquency_logs`
                            (`log_uuid`, `meter_id`, `property_id`, `owner_citizen_id`, `action`, `arrears_amount`, `notes`)
                        VALUES (?, ?, ?, ?, 'RECONNECTED', 0.00, 'Automated billing settlement cleared all arrears')
                    ]], { logUuid, m.meter_id, m.property_id, m.owner_citizen_id })

                    local player = Nyx.GetPlayerByCitizenId(m.owner_citizen_id)
                    if player then
                        TriggerClientEvent("nyx:ui:notify", player.source, {
                            type = "success",
                            title = "KÖZMŰVEK VISSZAKAPCSOLVA",
                            message = string.format("Az esedékes közműdíj ($%.2f) kiegyenlítésre került. Az áram- és vízszolgáltatás helyreállt!", bill.totalDue)
                        })
                    end
                end
            end
        else
            -- 4.2 Insufficient Liquidity: Record Overdue Arrears and Evaluate Delinquency State Machine
            local newMissed = missedCycles + 1
            local newArrears = bill.totalDue

            local tier, status, shouldSuspend = Nyx.Metering.EvaluateDelinquencyTier(newMissed, newArrears, cutoffThreshold)
            local wasSuspended = (tonumber(m.is_service_suspended) == 1)
            local nowSuspended = shouldSuspend or wasSuspended

            -- Insert Overdue Invoice
            MySQL.prepare.await([[
                INSERT INTO `nyx_services_utility_invoices`
                    (`invoice_uuid`, `meter_id`, `property_id`, `owner_citizen_id`, `substation_id`,
                     `cycle_period_start`, `cycle_period_end`, `kwh_consumed`, `water_consumed`,
                     `kwh_tariff`, `water_tariff`, `energy_charge`, `water_charge`,
                     `late_penalty`, `reconnect_fee`, `total_due`, `amount_paid`, `status`)
                VALUES (?, ?, ?, ?, ?, NOW() - INTERVAL 30 MINUTE, NOW(), ?, ?, ?, ?, ?, ?, ?, ?, ?, 0.00, 'overdue')
            ]], {
                invUuid, m.meter_id, m.property_id, m.owner_citizen_id, m.linked_substation_id,
                bill.kwhConsumed, bill.waterConsumed, bill.kwhTariff, bill.waterTariff,
                bill.energyCharge, bill.waterCharge, bill.latePenalty, bill.reconnectFee,
                bill.totalDue
            })

            -- Check if newly disconnected
            local newlyDisconnected = (nowSuspended and not wasSuspended)
            if newlyDisconnected then
                newlySuspendedCount = newlySuspendedCount + 1
            end

            -- Update meter
            MySQL.prepare.await([[
                UPDATE `nyx_services_utility_meters`
                SET `kwh_consumed` = 0.00,
                    `water_consumed` = 0.00,
                    `unpaid_balance` = ?,
                    `last_reading_kwh` = ?,
                    `last_reading_water` = ?,
                    `last_billed_at` = NOW(),
                    `consecutive_unpaid_cycles` = ?,
                    `delinquency_tier` = ?,
                    `meter_status` = ?,
                    `is_service_suspended` = ?,
                    `disconnected_at` = IF(? = 1 AND `disconnected_at` IS NULL, NOW(), `disconnected_at`)
                WHERE `meter_id` = ?
            ]], {
                newArrears, currentKwh, currentWater, newMissed, tier, status,
                nowSuspended and 1 or 0, newlyDisconnected and 1 or 0, m.meter_id
            })

            -- Delinquency Enforcement & Cut-off interlocks
            if newlyDisconnected then
                if m.property_id then
                    MySQL.prepare.await([[
                        UPDATE `nyx_properties`
                        SET `is_utility_suspended` = 1, `utility_status` = 'cut_off'
                        WHERE `property_id` = ?
                    ]], { m.property_id })

                    MySQL.prepare.await([[
                        INSERT INTO `nyx_property_audit`
                            (`property_id`, `action`, `actor_citizen_id`, `amount`, `notes`)
                        VALUES (?, 'UTILITY_CUTOFF_ENFORCED', ?, ?, 'Utility cutoff enforced due to debt exceeding statutory threshold')
                    ]], { m.property_id, m.owner_citizen_id, newArrears })

                    -- Update memory in nyx_properties if loaded
                    if Nyx.Properties and Nyx.Properties.Loaded and Nyx.Properties.Loaded[m.property_id] then
                        Nyx.Properties.Loaded[m.property_id].isUtilitySuspended = true
                        Nyx.Properties.Loaded[m.property_id].utilityStatus = "cut_off"
                    end
                end

                local logUuid = Nyx.Metering.GenerateLogUuid("CUTO", nowTime, math.random(100, 999))
                MySQL.prepare.await([[
                    INSERT INTO `nyx_services_utility_delinquency_logs`
                        (`log_uuid`, `meter_id`, `property_id`, `owner_citizen_id`, `action`, `arrears_amount`, `notes`)
                    VALUES (?, ?, ?, ?, 'POWER_CUTOFF_ENFORCED', ?, 'Statutory cutoff enforced for non-payment')
                ]], { logUuid, m.meter_id, m.property_id, m.owner_citizen_id, newArrears })

                local player = Nyx.GetPlayerByCitizenId(m.owner_citizen_id)
                if player then
                    TriggerClientEvent("nyx:ui:notify", player.source, {
                        type = "error",
                        title = "KÖZMŰVEK LEKAPCSOLVA",
                        message = string.format("Közműtartozás ($%.2f) miatt az ingatlanod (%s) áram- és vízszolgáltatása felfüggesztésre került!",
                            newArrears, m.property_label or m.meter_id)
                    })
                end
            elseif tier == 1 then
                local logUuid = Nyx.Metering.GenerateLogUuid("NOTC", nowTime, math.random(100, 999))
                MySQL.prepare.await([[
                    INSERT INTO `nyx_services_utility_delinquency_logs`
                        (`log_uuid`, `meter_id`, `property_id`, `owner_citizen_id`, `action`, `arrears_amount`, `notes`)
                    VALUES (?, ?, ?, ?, 'NOTICE_ISSUED', ?, 'Grace notice issued for unpaid billing cycle')
                ]], { logUuid, m.meter_id, m.property_id, m.owner_citizen_id, newArrears })

                local player = Nyx.GetPlayerByCitizenId(m.owner_citizen_id)
                if player then
                    TriggerClientEvent("nyx:ui:notify", player.source, {
                        type = "warning",
                        title = "KÖZMŰSZÁMLA FELSZÓLÍTÁS",
                        message = string.format("Fizetési felszólítás: $%.2f esedékes közműdíj az ingatlanodra (%s). Kérjük rendezd mielőbb!",
                            newArrears, m.property_label or m.meter_id)
                    })
                end
            end
        end
    end

    if Config.Debug then
        print(string.format("^2[Nyx:Services]^7 Utility Billing Cycle Complete: %d settled ($%.2f collected), %d newly cut off.^7",
            settledCount, totalRevenueCollected, newlySuspendedCount))
    end
end

-- 5. Manual Bill Payment / Arrears Settlement
function Nyx.Services.PayUtilityBill(src, meterId, amount)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local meter = MySQL.single.await([[
        SELECT m.*, p.`label` AS `property_label`
        FROM `nyx_services_utility_meters` m
        LEFT JOIN `nyx_properties` p ON m.`property_id` = p.`property_id`
        WHERE m.`meter_id` = ?
    ]], { meterId })
    if not meter then return false, "METER_NOT_FOUND" end

    local unpaid = tonumber(meter.unpaid_balance) or 0.00
    if unpaid <= 0.00 then
        return false, "NO_OUTSTANDING_BALANCE"
    end

    local payAmount = math.min(unpaid, tonumber(amount) or unpaid)
    payAmount = Nyx.Metering.RoundToCent(payAmount)
    if payAmount <= 0.00 then
        return false, "INVALID_PAYMENT_AMOUNT"
    end

    local ownerAcc = "citizen:" .. player.citizenId
    local destAcc = (Config.Billing and Config.Billing.PublicWorksAccount) or Nyx.Metering.Config.PublicWorksAccount
    local cutoffThreshold = (Config.Billing and Config.Billing.SuspensionThreshold) or Nyx.Metering.Config.SuspensionThreshold

    local ok, txId = exports['nyx_treasury']:ExecuteTransfer(
        ownerAcc,
        destAcc,
        payAmount,
        "utility_settlement",
        "meter:" .. meterId,
        string.format("Manual Utility Arrears Settlement: %s", meterId),
        0.0
    )

    if not ok then
        return false, "INSUFFICIENT_FUNDS"
    end

    local wasSuspended = (tonumber(meter.is_service_suspended) == 1)
    local settlement = Nyx.Metering.CalculatePaymentSettlement(unpaid, payAmount, wasSuspended, cutoffThreshold)

    -- Update meter record
    MySQL.prepare.await([[
        UPDATE `nyx_services_utility_meters`
        SET `unpaid_balance` = ?,
            `is_service_suspended` = ?,
            `delinquency_tier` = ?,
            `meter_status` = ?,
            `consecutive_unpaid_cycles` = IF(? <= 0.00, 0, `consecutive_unpaid_cycles`),
            `reconnected_at` = IF(? = 1, NOW(), `reconnected_at`)
        WHERE `meter_id` = ?
    ]], {
        settlement.remainingArrears,
        settlement.isSuspended and 1 or 0,
        settlement.newTier,
        settlement.newStatus,
        settlement.remainingArrears,
        settlement.canReconnect and 1 or 0,
        meterId
    })

    -- Update recent overdue invoices
    MySQL.prepare.await([[
        UPDATE `nyx_services_utility_invoices`
        SET `status` = 'settled_post_cutoff',
            `amount_paid` = `total_due`,
            `treasury_tx_uuid` = ?,
            `paid_at` = NOW()
        WHERE `meter_id` = ? AND `status` = 'overdue'
    ]], { txId, meterId })

    -- Reconnect property power & water if eligible
    if settlement.canReconnect then
        if meter.property_id then
            MySQL.prepare.await([[
                UPDATE `nyx_properties`
                SET `is_utility_suspended` = 0, `utility_status` = 'normal'
                WHERE `property_id` = ?
            ]], { meter.property_id })

            MySQL.prepare.await([[
                INSERT INTO `nyx_property_audit`
                    (`property_id`, `action`, `actor_citizen_id`, `amount`, `notes`)
                VALUES (?, 'UTILITY_RECONNECTED', ?, ?, 'Power and water re-energized after arrears settlement')
            ]], { meter.property_id, player.citizenId, payAmount })

            if Nyx.Properties and Nyx.Properties.Loaded and Nyx.Properties.Loaded[meter.property_id] then
                Nyx.Properties.Loaded[meter.property_id].isUtilitySuspended = false
                Nyx.Properties.Loaded[meter.property_id].utilityStatus = "normal"
            end
        end

        local logUuid = Nyx.Metering.GenerateLogUuid("RECN", os.time(), math.random(100, 999))
        MySQL.prepare.await([[
            INSERT INTO `nyx_services_utility_delinquency_logs`
                (`log_uuid`, `meter_id`, `property_id`, `owner_citizen_id`, `action`, `arrears_amount`, `actor_citizen_id`, `notes`)
            VALUES (?, ?, ?, ?, 'RECONNECTED', ?, ?, 'Manual arrears payment restored service')
        ]], { logUuid, meterId, meter.property_id, meter.owner_citizen_id, settlement.remainingArrears, player.citizenId })

        TriggerClientEvent("nyx:services:client:utilityReconnected", -1, meterId, meter.property_id)
    end

    return true, {
        meterId = meterId,
        propertyId = meter.property_id,
        paid = payAmount,
        remaining = settlement.remainingArrears,
        isSuspended = settlement.isSuspended,
        reconnected = settlement.canReconnect,
        status = settlement.newStatus,
        txId = txId
    }
end

-- 6. Query Utility Meter Details
function Nyx.Services.GetMeter(meterId)
    local m = MySQL.single.await([[
        SELECT m.*, p.`label` AS `property_label`, p.`type` AS `prop_type`, p.`has_backup_generator`
        FROM `nyx_services_utility_meters` m
        LEFT JOIN `nyx_properties` p ON m.`property_id` = p.`property_id`
        WHERE m.`meter_id` = ?
    ]], { meterId })
    return m
end

-- 7. Query Meter by Property ID
function Nyx.Services.GetMeterByPropertyId(propertyId)
    propertyId = tonumber(propertyId)
    local m = MySQL.single.await([[
        SELECT m.*, p.`label` AS `property_label`, p.`type` AS `prop_type`, p.`has_backup_generator`
        FROM `nyx_services_utility_meters` m
        LEFT JOIN `nyx_properties` p ON m.`property_id` = p.`property_id`
        WHERE m.`property_id` = ? OR m.`meter_id` = CONCAT('meter:prop:', (SELECT `property_code` FROM `nyx_properties` WHERE `property_id` = ?))
    ]], { propertyId, propertyId })
    return m
end

-- 8. Query Invoices History for Meter
function Nyx.Services.GetUtilityInvoices(meterId, limit)
    limit = math.min(50, math.max(1, tonumber(limit) or 10))
    local invoices = MySQL.query.await([[
        SELECT * FROM `nyx_services_utility_invoices`
        WHERE `meter_id` = ?
        ORDER BY `created_at` DESC
        LIMIT ?
    ]], { meterId, limit }) or {}
    return invoices
end

-- 9. Authoritative Power Cutoff Enforcement (Admin / Automated)
function Nyx.Services.EnforcePowerCutoff(meterId, reason, actorCitizenId)
    local meter = Nyx.Services.GetMeter(meterId)
    if not meter then return false, "METER_NOT_FOUND" end

    MySQL.prepare.await([[
        UPDATE `nyx_services_utility_meters`
        SET `is_service_suspended` = 1,
            `meter_status` = 'disconnected',
            `disconnected_at` = NOW()
        WHERE `meter_id` = ?
    ]], { meterId })

    if meter.property_id then
        MySQL.prepare.await([[
            UPDATE `nyx_properties`
            SET `is_utility_suspended` = 1, `utility_status` = 'cut_off'
            WHERE `property_id` = ?
        ]], { meter.property_id })

        if Nyx.Properties and Nyx.Properties.Loaded and Nyx.Properties.Loaded[meter.property_id] then
            Nyx.Properties.Loaded[meter.property_id].isUtilitySuspended = true
            Nyx.Properties.Loaded[meter.property_id].utilityStatus = "cut_off"
        end
    end

    local logUuid = Nyx.Metering.GenerateLogUuid("CUTO", os.time(), math.random(100, 999))
    MySQL.prepare.await([[
        INSERT INTO `nyx_services_utility_delinquency_logs`
            (`log_uuid`, `meter_id`, `property_id`, `owner_citizen_id`, `action`, `arrears_amount`, `actor_citizen_id`, `notes`)
        VALUES (?, ?, ?, ?, 'POWER_CUTOFF_ENFORCED', ?, ?, ?)
    ]], { logUuid, meterId, meter.property_id, meter.owner_citizen_id, meter.unpaid_balance or 0.00, actorCitizenId or "ENFORCEMENT", reason or "Municipal power cut-off enforced" })

    TriggerClientEvent("nyx:services:client:utilityCutoffEnforced", -1, meterId, meter.property_id)
    return true, { meterId = meterId, isSuspended = true }
end

-- 10. Authoritative Utility Reconnection (Admin / Payment)
function Nyx.Services.ReconnectUtility(meterId, actorCitizenId)
    local meter = Nyx.Services.GetMeter(meterId)
    if not meter then return false, "METER_NOT_FOUND" end

    MySQL.prepare.await([[
        UPDATE `nyx_services_utility_meters`
        SET `is_service_suspended` = 0,
            `meter_status` = 'active',
            `reconnected_at` = NOW()
        WHERE `meter_id` = ?
    ]], { meterId })

    if meter.property_id then
        MySQL.prepare.await([[
            UPDATE `nyx_properties`
            SET `is_utility_suspended` = 0, `utility_status` = 'normal'
            WHERE `property_id` = ?
        ]], { meter.property_id })

        if Nyx.Properties and Nyx.Properties.Loaded and Nyx.Properties.Loaded[meter.property_id] then
            Nyx.Properties.Loaded[meter.property_id].isUtilitySuspended = false
            Nyx.Properties.Loaded[meter.property_id].utilityStatus = "normal"
        end
    end

    local logUuid = Nyx.Metering.GenerateLogUuid("RECN", os.time(), math.random(100, 999))
    MySQL.prepare.await([[
        INSERT INTO `nyx_services_utility_delinquency_logs`
            (`log_uuid`, `meter_id`, `property_id`, `owner_citizen_id`, `action`, `arrears_amount`, `actor_citizen_id`, `notes`)
        VALUES (?, ?, ?, ?, 'RECONNECTED', ?, ?, 'Municipal administrative reconnection')
    ]], { logUuid, meterId, meter.property_id, meter.owner_citizen_id, meter.unpaid_balance or 0.00, actorCitizenId or "ADMIN" })

    TriggerClientEvent("nyx:services:client:utilityReconnected", -1, meterId, meter.property_id)
    return true, { meterId = meterId, isSuspended = false }
end
