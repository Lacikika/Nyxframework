--[[
    Nyxframework: nyx_properties
    File: server/leases.lua
    Description: Authoritative Commercial Real Estate Leasing Engine.
                 Handles lease agreements, public storefront relisting cycles,
                 security deposit escrow, municipal tax splits, delinquency lockouts,
                 and automated eviction sweeps.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}
Nyx.Properties.CommercialLeases = {} -- [lease_id] = leaseRecord

local function generateTxUuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

-- ----------------------------------------------------------------------------
-- 1. Hydrate Commercial Leases from Database on Server Startup
-- ----------------------------------------------------------------------------
function Nyx.Properties.HydrateCommercialLeases()
    local rows = MySQL.query.await([[
        SELECT l.*, p.`property_code`, p.`label` AS `property_label`, p.`type` AS `prop_type`
        FROM `nyx_property_commercial_leases` l
        LEFT JOIN `nyx_properties` p ON l.`property_id` = p.`property_id`
    ]])

    Nyx.Properties.CommercialLeases = {}

    if rows then
        for _, r in ipairs(rows) do
            local leaseData = {
                leaseId = r.lease_id,
                leaseUuid = r.lease_uuid,
                propertyId = tonumber(r.property_id),
                propertyCode = r.property_code,
                propertyLabel = r.property_label,
                lessorType = r.lessor_type,
                lessorAccountId = r.lessor_account_id,
                lesseeType = r.lessee_type,
                lesseeId = r.lessee_id,
                lesseeAccountId = r.lessee_account_id,
                authorizedSignerCitizenId = r.authorized_signer_citizen_id,
                zoningUsage = r.zoning_usage,
                cycleRent = tonumber(r.cycle_rent) or 0.00,
                securityDepositHeld = tonumber(r.security_deposit_held) or 0.00,
                rentalTaxRate = tonumber(r.rental_tax_rate) or 0.0500,
                leaseTermCycles = tonumber(r.lease_term_cycles) or 4,
                cyclesCompleted = tonumber(r.cycles_completed) or 0,
                consecutiveMissedCycles = tonumber(r.consecutive_missed_cycles) or 0,
                delinquencyTier = tonumber(r.delinquency_tier) or 0,
                arrearsBalance = tonumber(r.arrears_balance) or 0.00,
                latePenaltyRate = tonumber(r.late_penalty_rate) or 0.1000,
                leaseStatus = r.lease_status,
                nextBillingDueAt = r.next_billing_due_at,
                gracePeriodExpiresAt = r.grace_period_expires_at,
                evictionDeadlineAt = r.eviction_deadline_at,
                lastBilledAt = r.last_billed_at,
                lastSettledAt = r.last_settled_at,
                escrowDepositTxId = r.escrow_deposit_tx_id,
                createdAt = r.created_at
            }

            Nyx.Properties.CommercialLeases[r.lease_id] = leaseData

            -- Synchronize property record in memory
            local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[leaseData.propertyId]
            if prop then
                prop.isLeased = (r.lease_status == 'active' or r.lease_status == 'grace_period' or r.lease_status == 'lapsed')
                prop.activeLeaseId = r.lease_id
                prop.leaseStatus = (r.lease_status == 'active') and 'leased_active'
                    or ((r.lease_status == 'grace_period') and 'in_grace_period'
                    or ((r.lease_status == 'lapsed') and 'lease_lapsed'
                    or 'available_for_lease'))
            end
        end
        print(string.format("^2[Nyx:Properties] Hydrated %d commercial real estate leases.^7", #rows))
    end
end

-- Hook hydration into startup
MySQL.ready(function()
    Nyx.Properties.HydrateCommercialLeases()
end)

-- ----------------------------------------------------------------------------
-- 2. Query Getters
-- ----------------------------------------------------------------------------
function Nyx.Properties.GetCommercialLease(leaseId)
    if not leaseId then return nil end
    return Nyx.Properties.CommercialLeases[leaseId]
end

function Nyx.Properties.GetCommercialLeaseByProperty(propertyId)
    propertyId = tonumber(propertyId)
    if not propertyId then return nil end

    for _, lease in pairs(Nyx.Properties.CommercialLeases) do
        if lease.propertyId == propertyId and (lease.leaseStatus == 'active' or lease.leaseStatus == 'grace_period' or lease.leaseStatus == 'lapsed') then
            return lease
        end
    end
    return nil
end

function Nyx.Properties.GetCommercialLeasesByLessee(lesseeId)
    if not lesseeId then return {} end
    local list = {}
    for _, lease in pairs(Nyx.Properties.CommercialLeases) do
        if lease.lesseeId == lesseeId then
            table.insert(list, lease)
        end
    end
    return list
end

function Nyx.Properties.GetAvailableCommercialProperties()
    local available = {}
    if Nyx.Properties.Loaded then
        for propId, prop in pairs(Nyx.Properties.Loaded) do
            local isCommercial = (prop.type == 'commercial' or prop.type == 'industrial' or (prop.commercialZoning and prop.commercialZoning ~= 'none'))
            local isUnleased = (not prop.activeLeaseId or prop.leaseStatus == 'available_for_lease' or not prop.isLeased)
            if isCommercial and isUnleased and not prop.reclaimedForAuction then
                table.insert(available, {
                    propertyId = prop.id,
                    propertyCode = prop.code,
                    label = prop.label,
                    type = prop.type,
                    commercialZoning = prop.commercialZoning or (prop.type == 'industrial' and 'industrial_warehouse' or 'retail_storefront'),
                    baseRentalRate = prop.baseRentalRate or (prop.price and prop.price * 0.01) or 2500.00,
                    landAreaSqm = prop.landAreaSqm or 200.0,
                    zoneId = prop.zoneId or "zone_ls_metro",
                    entrance = prop.entrance
                })
            end
        end
    end
    return available
end

function Nyx.Properties.IsPropertyLeaseLapsed(propertyId)
    local lease = Nyx.Properties.GetCommercialLeaseByProperty(propertyId)
    if not lease then return false end
    return (lease.leaseStatus == 'lapsed' or lease.leaseStatus == 'evicted' or lease.delinquencyTier >= 2)
end

-- ----------------------------------------------------------------------------
-- 3. Authoritative Lease Signing Pipeline
-- ----------------------------------------------------------------------------
function Nyx.Properties.SignCommercialLease(src, payload)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local okVal, cleanPayload = Nyx.CommercialLeases.ValidateLeaseProposal(payload)
    if not okVal then
        return false, cleanPayload
    end

    local propertyId = cleanPayload.propertyId
    local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[propertyId]
    if not prop then
        return false, "PROPERTY_NOT_FOUND"
    end

    -- Verify property is commercial/industrial and not already actively leased
    local isCommercial = (prop.type == 'commercial' or prop.type == 'industrial' or (prop.commercialZoning and prop.commercialZoning ~= 'none'))
    if not isCommercial then
        return false, "PROPERTY_NOT_ZONED_FOR_COMMERCE"
    end

    local existingLease = Nyx.Properties.GetCommercialLeaseByProperty(propertyId)
    if existingLease and (existingLease.leaseStatus == 'active' or existingLease.leaseStatus == 'grace_period') then
        return false, "PROPERTY_ALREADY_LEASED"
    end

    -- Permission verification
    local signerCitizenId = player.citizenId
    local payerAccountId = nil

    if cleanPayload.lesseeType == "faction" then
        local factionId = cleanPayload.lesseeId
        local hasPermission = false

        if exports['nyx_factions'] and exports['nyx_factions'].HasPermission then
            hasPermission = exports['nyx_factions']:HasPermission(factionId, signerCitizenId, "property:manage")
                or exports['nyx_factions']:HasPermission(factionId, signerCitizenId, "*")
        else
            hasPermission = true
        end

        if not hasPermission then
            return false, "INSUFFICIENT_FACTION_PERMISSIONS"
        end

        payerAccountId = "faction:" .. factionId
    else
        payerAccountId = "citizen:" .. signerCitizenId
    end

    -- Financial calculations (Zero-cent economic conservation)
    local baseRent = cleanPayload.cycleRent
    local rentalTaxRate = Nyx.CommercialLeases.DefaultRentalTaxRate
    local costs = Nyx.CommercialLeases.CalculateLeaseInitialCosts(baseRent, 1, rentalTaxRate)

    local totalRequired = costs.totalUpfrontRequired
    local payerBalance = exports['nyx_treasury']:GetAccountBalance(payerAccountId) or 0.00

    if payerBalance < totalRequired then
        return false, string.format("INSUFFICIENT_FUNDS_REQUIRED_%.2f", totalRequired)
    end

    local lessorAccountId = (prop.ownerCitizenId and prop.ownerCitizenId ~= "")
        and ("citizen:" .. prop.ownerCitizenId)
        or "gov:city:master"
    local lessorType = (prop.ownerCitizenId and prop.ownerCitizenId ~= "") and "private_citizen" or "municipal"
    local escrowAccountId = "pool:property:lease_escrow"
    local municipalTaxAccountId = "gov:city:master"

    -- Ensure escrow and treasury accounts exist
    if exports['nyx_treasury'] and exports['nyx_treasury'].EnsureAccount then
        exports['nyx_treasury']:EnsureAccount(escrowAccountId, "Municipal Commercial Lease Security Deposit Escrow Pool", "grant_pool", 0.00)
        exports['nyx_treasury']:EnsureAccount(lessorAccountId, "Lessor Operating Account", "department", 0.00)
    end

    -- Transaction Step 1: Security Deposit Escrow Transfer
    local txUuidDeposit = generateTxUuid()
    local okDeposit, errDeposit = exports['nyx_treasury']:ExecuteTransfer(
        payerAccountId,
        escrowAccountId,
        costs.securityDeposit,
        "lease_security_deposit",
        payerAccountId,
        string.format("Security Deposit for Lease at %s (#%d)", prop.label, propertyId),
        0.0
    )
    if not okDeposit then
        return false, "SECURITY_DEPOSIT_TRANSFER_FAILED: " .. tostring(errDeposit)
    end

    -- Transaction Step 2: First Cycle Rent Transfer (with statutory municipal tax split)
    local txUuidRent = generateTxUuid()
    local okRent, errRent = exports['nyx_treasury']:ExecuteTransfer(
        payerAccountId,
        lessorAccountId,
        costs.netToLessor,
        "commercial_rent",
        payerAccountId,
        string.format("Initial Commercial Rent for %s (#%d)", prop.label, propertyId),
        0.0
    )
    if not okRent then
        -- Rollback deposit
        exports['nyx_treasury']:ExecuteTransfer(escrowAccountId, payerAccountId, costs.securityDeposit, "refund", escrowAccountId, "Rollback", 0.0)
        return false, "RENT_TRANSFER_FAILED: " .. tostring(errRent)
    end

    -- Remit statutory municipal rental tax if lessor is not municipal master
    if costs.municipalTax > 0 and lessorAccountId ~= municipalTaxAccountId then
        exports['nyx_treasury']:ExecuteTransfer(
            payerAccountId,
            municipalTaxAccountId,
            costs.municipalTax,
            "commercial_lease_tax",
            payerAccountId,
            string.format("Municipal Commercial Lease Tax (5%%) for %s (#%d)", prop.label, propertyId),
            0.0
        )
    elseif costs.municipalTax > 0 and lessorAccountId == municipalTaxAccountId then
        -- Rent to city master already includes net + tax
    end

    -- Generate lease identifiers
    local leaseId = Nyx.CommercialLeases.GenerateLeaseId(prop.code or propertyId, cleanPayload.lesseeId)
    local leaseUuid = Nyx.CommercialLeases.GenerateLeaseUuid()
    local billingIntervalSec = Nyx.CommercialLeases.DefaultBillingIntervalSeconds

    -- Persist lease into database
    local okInsert = MySQL.prepare.await([[
        INSERT INTO `nyx_property_commercial_leases`
            (`lease_id`, `lease_uuid`, `property_id`, `lessor_type`, `lessor_account_id`,
             `lessee_type`, `lessee_id`, `lessee_account_id`, `authorized_signer_citizen_id`,
             `zoning_usage`, `cycle_rent`, `security_deposit_held`, `rental_tax_rate`,
             `lease_term_cycles`, `cycles_completed`, `consecutive_missed_cycles`,
             `delinquency_tier`, `arrears_balance`, `late_penalty_rate`, `lease_status`,
             `next_billing_due_at`, `last_billed_at`, `escrow_deposit_tx_id`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 0, 0, 0.00, ?, 'active',
                DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND), CURRENT_TIMESTAMP, ?)
        ON DUPLICATE KEY UPDATE
            `lease_uuid` = VALUES(`lease_uuid`),
            `lessor_type` = VALUES(`lessor_type`),
            `lessor_account_id` = VALUES(`lessor_account_id`),
            `lessee_type` = VALUES(`lessee_type`),
            `lessee_id` = VALUES(`lessee_id`),
            `lessee_account_id` = VALUES(`lessee_account_id`),
            `authorized_signer_citizen_id` = VALUES(`authorized_signer_citizen_id`),
            `zoning_usage` = VALUES(`zoning_usage`),
            `cycle_rent` = VALUES(`cycle_rent`),
            `security_deposit_held` = VALUES(`security_deposit_held`),
            `rental_tax_rate` = VALUES(`rental_tax_rate`),
            `lease_term_cycles` = VALUES(`lease_term_cycles`),
            `cycles_completed` = 1,
            `consecutive_missed_cycles` = 0,
            `delinquency_tier` = 0,
            `arrears_balance` = 0.00,
            `lease_status` = 'active',
            `next_billing_due_at` = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND),
            `last_billed_at` = CURRENT_TIMESTAMP,
            `escrow_deposit_tx_id` = VALUES(`escrow_deposit_tx_id`)
    ]], {
        leaseId, leaseUuid, propertyId, lessorType, lessorAccountId,
        cleanPayload.lesseeType, cleanPayload.lesseeId, payerAccountId, signerCitizenId,
        cleanPayload.zoningUsage, costs.cycleRent, costs.securityDeposit, costs.taxRate,
        cleanPayload.leaseTermCycles, costs.penaltyRate or 0.10, billingIntervalSec, txUuidDeposit,
        billingIntervalSec
    })

    if not okInsert then
        return false, "DATABASE_INSERT_FAILED"
    end

    -- Update property table state
    MySQL.prepare.await([[
        UPDATE `nyx_properties`
        SET `is_leased` = 1,
            `active_lease_id` = ?,
            `commercial_zoning` = ?,
            `base_rental_rate` = ?,
            `lease_status` = 'leased_active'
        WHERE `property_id` = ?
    ]], { leaseId, cleanPayload.zoningUsage, costs.cycleRent, propertyId })

    -- Persist audit trail
    local auditUuid = generateTxUuid()
    MySQL.prepare.await([[
        INSERT INTO `nyx_property_lease_audits`
            (`audit_uuid`, `lease_id`, `property_id`, `action`, `actor_citizen_id`, `amount`, `tax_amount`, `treasury_tx_uuid`, `notes`)
        VALUES (?, ?, ?, 'LEASE_SIGNED', ?, ?, ?, ?, ?)
    ]], {
        auditUuid, leaseId, propertyId, signerCitizenId,
        costs.totalUpfrontRequired, costs.municipalTax, txUuidRent,
        string.format("Lease executed by %s for %s (%s)", signerCitizenId, cleanPayload.lesseeId, cleanPayload.zoningUsage)
    })

    -- Update in-memory structures
    prop.isLeased = true
    prop.activeLeaseId = leaseId
    prop.commercialZoning = cleanPayload.zoningUsage
    prop.baseRentalRate = costs.cycleRent
    prop.leaseStatus = 'leased_active'

    local leaseRecord = {
        leaseId = leaseId,
        leaseUuid = leaseUuid,
        propertyId = propertyId,
        propertyCode = prop.code,
        propertyLabel = prop.label,
        lessorType = lessorType,
        lessorAccountId = lessorAccountId,
        lesseeType = cleanPayload.lesseeType,
        lesseeId = cleanPayload.lesseeId,
        lesseeAccountId = payerAccountId,
        authorizedSignerCitizenId = signerCitizenId,
        zoningUsage = cleanPayload.zoningUsage,
        cycleRent = costs.cycleRent,
        securityDepositHeld = costs.securityDeposit,
        rentalTaxRate = costs.taxRate,
        leaseTermCycles = cleanPayload.leaseTermCycles,
        cyclesCompleted = 1,
        consecutiveMissedCycles = 0,
        delinquencyTier = 0,
        arrearsBalance = 0.00,
        latePenaltyRate = 0.1000,
        leaseStatus = "active",
        escrowDepositTxId = txUuidDeposit,
        createdAt = os.time()
    }
    Nyx.Properties.CommercialLeases[leaseId] = leaseRecord

    -- Inform faction subsystem if corporate lease
    if cleanPayload.lesseeType == "faction" then
        TriggerEvent("nyx:factions:propertyLeased", cleanPayload.lesseeId, propertyId, leaseId)
    end

    -- Broadcast update to clients
    TriggerClientEvent("nyx:properties:client:leaseUpdated", -1, {
        propertyId = propertyId,
        leaseId = leaseId,
        leaseStatus = "leased_active",
        lesseeId = cleanPayload.lesseeId,
        zoningUsage = cleanPayload.zoningUsage
    })

    return true, leaseRecord
end

-- ----------------------------------------------------------------------------
-- 4. Automated Recurring Lease Rent Sweeper & Delinquency Enforcement
-- ----------------------------------------------------------------------------
function Nyx.Properties.ProcessLeaseBillingCycles()
    local dueLeases = MySQL.query.await([[
        SELECT l.*, p.`label` AS `prop_label`
        FROM `nyx_property_commercial_leases` l
        LEFT JOIN `nyx_properties` p ON l.`property_id` = p.`property_id`
        WHERE l.`lease_status` IN ('active', 'grace_period', 'lapsed')
          AND l.`next_billing_due_at` <= CURRENT_TIMESTAMP
    ]]) or {}

    local processedCount = 0
    local lapsedCount = 0
    local evictedCount = 0

    local billingIntervalSec = Nyx.CommercialLeases.DefaultBillingIntervalSeconds

    for _, r in ipairs(dueLeases) do
        local leaseId = r.lease_id
        local propertyId = tonumber(r.property_id)
        local cycleRent = tonumber(r.cycle_rent) or 0.00
        local taxRate = tonumber(r.rental_tax_rate) or Nyx.CommercialLeases.DefaultRentalTaxRate
        local lesseeAcc = r.lessee_account_id
        local lessorAcc = r.lessor_account_id or "gov:city:master"
        local municipalTaxAcc = "gov:city:master"
        local propLabel = r.prop_label or string.format("Property #%d", propertyId)

        local currentBal = exports['nyx_treasury']:GetAccountBalance(lesseeAcc) or 0.00
        local splits = Nyx.CommercialLeases.CalculateRecurringRentSplit(cycleRent, taxRate)

        if currentBal >= cycleRent then
            -- Successful auto-debit
            local txUuid = generateTxUuid()
            local okDebit, errDebit = exports['nyx_treasury']:ExecuteTransfer(
                lesseeAcc,
                lessorAcc,
                splits.netToLessor,
                "commercial_rent",
                lesseeAcc,
                string.format("Recurring rent for %s (#%d)", propLabel, propertyId),
                0.0
            )

            if okDebit then
                if splits.municipalTax > 0 and lessorAcc ~= municipalTaxAcc then
                    exports['nyx_treasury']:ExecuteTransfer(
                        lesseeAcc,
                        municipalTaxAcc,
                        splits.municipalTax,
                        "commercial_lease_tax",
                        lesseeAcc,
                        string.format("Municipal Commercial Lease Tax for %s (#%d)", propLabel, propertyId),
                        0.0
                    )
                end

                MySQL.prepare.await([[
                    UPDATE `nyx_property_commercial_leases`
                    SET `cycles_completed` = `cycles_completed` + 1,
                        `consecutive_missed_cycles` = 0,
                        `delinquency_tier` = 0,
                        `arrears_balance` = 0.00,
                        `lease_status` = 'active',
                        `next_billing_due_at` = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND),
                        `last_billed_at` = CURRENT_TIMESTAMP,
                        `last_settled_at` = CURRENT_TIMESTAMP
                    WHERE `lease_id` = ?
                ]], { billingIntervalSec, leaseId })

                -- Log audit
                MySQL.prepare.await([[
                    INSERT INTO `nyx_property_lease_audits`
                        (`audit_uuid`, `lease_id`, `property_id`, `action`, `actor_citizen_id`, `amount`, `tax_amount`, `treasury_tx_uuid`, `notes`)
                    VALUES (?, ?, ?, 'RENT_DEBITED', 'SYSTEM_BILLING', ?, ?, ?, ?)
                ]], {
                    generateTxUuid(), leaseId, propertyId,
                    cycleRent, splits.municipalTax, txUuid,
                    "Automated recurring lease rent successfully settled"
                })

                -- Update memory
                local mem = Nyx.Properties.CommercialLeases[leaseId]
                if mem then
                    mem.cyclesCompleted = (mem.cyclesCompleted or 0) + 1
                    mem.consecutiveMissedCycles = 0
                    mem.delinquencyTier = 0
                    mem.arrearsBalance = 0.00
                    mem.leaseStatus = 'active'
                end
                processedCount = processedCount + 1
            end
        else
            -- Insufficient funds: Delinquency escalation
            local newMissed = (tonumber(r.consecutive_missed_cycles) or 0) + 1
            local newArrears = (tonumber(r.arrears_balance) or 0.00) + cycleRent

            local delinq = Nyx.CommercialLeases.EvaluateDelinquencyState(newMissed, newArrears, nil, nil, os.time())

            if delinq.tier >= 4 then
                -- Eviction & forfeiture of security deposit
                local heldDeposit = tonumber(r.security_deposit_held) or 0.00
                local escrowAcc = "pool:property:lease_escrow"

                if heldDeposit > 0 then
                    local depositSplit = Nyx.CommercialLeases.CalculateRecurringRentSplit(heldDeposit, taxRate)
                    pcall(function()
                        exports['nyx_treasury']:ExecuteTransfer(
                            escrowAcc,
                            lessorAcc,
                            depositSplit.netToLessor,
                            "forfeited_deposit_restitution",
                            escrowAcc,
                            string.format("Security Deposit Forfeited due to Eviction (#%d)", propertyId),
                            0.0
                        )
                    end)
                end

                MySQL.prepare.await([[
                    UPDATE `nyx_property_commercial_leases`
                    SET `lease_status` = 'evicted',
                        `delinquency_tier` = 4,
                        `consecutive_missed_cycles` = ?,
                        `arrears_balance` = ?
                    WHERE `lease_id` = ?
                ]], { newMissed, newArrears, leaseId })

                -- Relist property in public storefront cycle
                MySQL.prepare.await([[
                    UPDATE `nyx_properties`
                    SET `is_leased` = 0,
                        `active_lease_id` = NULL,
                        `lease_status` = 'available_for_lease'
                    WHERE `property_id` = ?
                ]], { propertyId })

                MySQL.prepare.await([[
                    INSERT INTO `nyx_property_lease_audits`
                        (`audit_uuid`, `lease_id`, `property_id`, `action`, `actor_citizen_id`, `amount`, `notes`)
                    VALUES (?, ?, ?, 'EVICTION_EXECUTED', 'MUNICIPAL_SHERIFF', ?, ?)
                ]], {
                    generateTxUuid(), leaseId, propertyId, newArrears,
                    "Commercial lease terminated due to default; property relisted for public lease cycle"
                })

                local mem = Nyx.Properties.CommercialLeases[leaseId]
                if mem then
                    mem.leaseStatus = 'evicted'
                    mem.delinquencyTier = 4
                end
                local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[propertyId]
                if prop then
                    prop.isLeased = false
                    prop.activeLeaseId = nil
                    prop.leaseStatus = 'available_for_lease'
                end
                evictedCount = evictedCount + 1
            elseif delinq.tier >= 2 then
                -- Lapsed & Doorlock Lockout
                MySQL.prepare.await([[
                    UPDATE `nyx_property_commercial_leases`
                    SET `lease_status` = 'lapsed',
                        `delinquency_tier` = ?,
                        `consecutive_missed_cycles` = ?,
                        `arrears_balance` = ?,
                        `eviction_deadline_at` = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 72 HOUR)
                    WHERE `lease_id` = ?
                ]], { delinq.tier, newMissed, newArrears, leaseId })

                MySQL.prepare.await([[
                    UPDATE `nyx_properties`
                    SET `lease_status` = 'lease_lapsed', `is_locked` = 1
                    WHERE `property_id` = ?
                ]], { propertyId })

                MySQL.prepare.await([[
                    INSERT INTO `nyx_property_lease_audits`
                        (`audit_uuid`, `lease_id`, `property_id`, `action`, `actor_citizen_id`, `amount`, `notes`)
                    VALUES (?, ?, ?, 'LEASE_LAPSED_LOCKOUT', 'SYSTEM_BILLING', ?, ?)
                ]], {
                    generateTxUuid(), leaseId, propertyId, newArrears,
                    "Lease lapsed due to consecutive unpaid rent; doors locked out and registers suspended"
                })

                local mem = Nyx.Properties.CommercialLeases[leaseId]
                if mem then
                    mem.leaseStatus = 'lapsed'
                    mem.delinquencyTier = delinq.tier
                    mem.arrearsBalance = newArrears
                end
                local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[propertyId]
                if prop then
                    prop.leaseStatus = 'lease_lapsed'
                    prop.isLocked = true
                end
                lapsedCount = lapsedCount + 1
            else
                -- Tier 1 Grace Period
                MySQL.prepare.await([[
                    UPDATE `nyx_property_commercial_leases`
                    SET `lease_status` = 'grace_period',
                        `delinquency_tier` = 1,
                        `consecutive_missed_cycles` = ?,
                        `arrears_balance` = ?,
                        `grace_period_expires_at` = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 48 HOUR)
                    WHERE `lease_id` = ?
                ]], { newMissed, newArrears, leaseId })

                MySQL.prepare.await([[
                    UPDATE `nyx_properties`
                    SET `lease_status` = 'in_grace_period'
                    WHERE `property_id` = ?
                ]], { propertyId })

                MySQL.prepare.await([[
                    INSERT INTO `nyx_property_lease_audits`
                        (`audit_uuid`, `lease_id`, `property_id`, `action`, `actor_citizen_id`, `amount`, `notes`)
                    VALUES (?, ?, ?, 'GRACE_ENTERED', 'SYSTEM_BILLING', ?, ?)
                ]], {
                    generateTxUuid(), leaseId, propertyId, newArrears,
                    "Lease entered 48h grace period due to unpaid rent billing cycle"
                })

                local mem = Nyx.Properties.CommercialLeases[leaseId]
                if mem then
                    mem.leaseStatus = 'grace_period'
                    mem.delinquencyTier = 1
                    mem.arrearsBalance = newArrears
                end
                local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[propertyId]
                if prop then
                    prop.leaseStatus = 'in_grace_period'
                end
            end
        end
    end

    return {
        processedCount = processedCount,
        lapsedCount = lapsedCount,
        evictedCount = evictedCount
    }
end

-- ----------------------------------------------------------------------------
-- 5. Manual Arrears Settlement Pipeline
-- ----------------------------------------------------------------------------
function Nyx.Properties.PayLeaseRentManual(src, leaseId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local lease = Nyx.Properties.GetCommercialLease(leaseId)
    if not lease then return false, "LEASE_NOT_FOUND" end

    if lease.leaseStatus == "evicted" or lease.leaseStatus == "terminated" then
        return false, "LEASE_NO_LONGER_ACTIVE"
    end

    local arrears = lease.arrearsBalance or 0.00
    local cycleRent = lease.cycleRent or 0.00
    local totalDue = (arrears > 0) and arrears or cycleRent

    local settlement = Nyx.CommercialLeases.CalculateArrearsSettlement(totalDue, lease.latePenaltyRate or 0.10)
    local totalRequired = settlement.totalSettlementDue

    local payerAcc = lease.lesseeAccountId or ("citizen:" .. player.citizenId)
    local payerBal = exports['nyx_treasury']:GetAccountBalance(payerAcc) or 0.00

    if payerBal < totalRequired then
        return false, string.format("INSUFFICIENT_FUNDS_REQUIRED_%.2f", totalRequired)
    end

    local lessorAcc = lease.lessorAccountId or "gov:city:master"
    local municipalTaxAcc = "gov:city:master"
    local splits = Nyx.CommercialLeases.CalculateRecurringRentSplit(totalDue, lease.rentalTaxRate or 0.05)

    local txUuid = generateTxUuid()
    local okTransfer = exports['nyx_treasury']:ExecuteTransfer(
        payerAcc,
        lessorAcc,
        splits.netToLessor,
        "commercial_rent_settlement",
        payerAcc,
        string.format("Manual Lease Settlement: %s", leaseId),
        0.0
    )
    if not okTransfer then
        return false, "SETTLEMENT_TRANSFER_FAILED"
    end

    -- Remit municipal tax and penalty
    if splits.municipalTax + settlement.penaltyAmount > 0 and lessorAcc ~= municipalTaxAcc then
        exports['nyx_treasury']:ExecuteTransfer(
            payerAcc,
            municipalTaxAcc,
            splits.municipalTax + settlement.penaltyAmount,
            "commercial_lease_tax",
            payerAcc,
            string.format("Tax and Late Surcharge Settlement: %s", leaseId),
            0.0
        )
    end

    -- Update database
    local billingIntervalSec = Nyx.CommercialLeases.DefaultBillingIntervalSeconds
    MySQL.prepare.await([[
        UPDATE `nyx_property_commercial_leases`
        SET `arrears_balance` = 0.00,
            `delinquency_tier` = 0,
            `consecutive_missed_cycles` = 0,
            `lease_status` = 'active',
            `next_billing_due_at` = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND),
            `last_settled_at` = CURRENT_TIMESTAMP
        WHERE `lease_id` = ?
    ]], { billingIntervalSec, leaseId })

    -- Unlock property if was locked out
    MySQL.prepare.await([[
        UPDATE `nyx_properties`
        SET `lease_status` = 'leased_active'
        WHERE `property_id` = ?
    ]], { lease.propertyId })

    -- Audit trail
    MySQL.prepare.await([[
        INSERT INTO `nyx_property_lease_audits`
            (`audit_uuid`, `lease_id`, `property_id`, `action`, `actor_citizen_id`, `amount`, `tax_amount`, `treasury_tx_uuid`, `notes`)
        VALUES (?, ?, ?, 'ARREARS_SETTLED', ?, ?, ?, ?, ?)
    ]], {
        generateTxUuid(), leaseId, lease.propertyId, player.citizenId,
        totalRequired, splits.municipalTax + settlement.penaltyAmount, txUuid,
        string.format("Manual settlement paid in full by %s", player.citizenId)
    })

    -- Update memory
    lease.arrearsBalance = 0.00
    lease.delinquencyTier = 0
    lease.consecutiveMissedCycles = 0
    lease.leaseStatus = 'active'

    local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[lease.propertyId]
    if prop then
        prop.leaseStatus = 'leased_active'
    end

    TriggerClientEvent("nyx:properties:client:leaseUpdated", -1, {
        propertyId = lease.propertyId,
        leaseId = leaseId,
        leaseStatus = "leased_active"
    })

    return true, {
        leaseId = leaseId,
        amountPaid = totalRequired,
        arrearsSettled = totalDue,
        penaltyPaid = settlement.penaltyAmount
    }
end

-- ----------------------------------------------------------------------------
-- 6. Voluntary Lease Termination & Security Deposit Refund
-- ----------------------------------------------------------------------------
function Nyx.Properties.TerminateCommercialLease(src, leaseId, reason)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local lease = Nyx.Properties.GetCommercialLease(leaseId)
    if not lease then return false, "LEASE_NOT_FOUND" end

    -- Verify authorization: Signer or Faction Executive
    local isAuthorized = (player.citizenId == lease.authorizedSignerCitizenId)
    if not isAuthorized and lease.lesseeType == "faction" and exports['nyx_factions'] and exports['nyx_factions'].HasPermission then
        isAuthorized = exports['nyx_factions']:HasPermission(lease.lesseeId, player.citizenId, "property:manage")
            or exports['nyx_factions']:HasPermission(lease.lesseeId, player.citizenId, "*")
    end

    if not isAuthorized then
        return false, "UNAUTHORIZED"
    end

    if lease.leaseStatus == "terminated" or lease.leaseStatus == "evicted" then
        return false, "LEASE_ALREADY_CLOSED"
    end

    local deposit = lease.securityDepositHeld or 0.00
    local escrowAcc = "pool:property:lease_escrow"
    local refundAcc = lease.lesseeAccountId or ("citizen:" .. player.citizenId)
    local txUuid = generateTxUuid()

    -- Refund deposit if no unpaid arrears
    if deposit > 0 and (lease.arrearsBalance or 0) <= 0 then
        exports['nyx_treasury']:ExecuteTransfer(
            escrowAcc,
            refundAcc,
            deposit,
            "security_deposit_refund",
            escrowAcc,
            string.format("Security Deposit Refund for terminated lease: %s", leaseId),
            0.0
        )
    end

    MySQL.prepare.await([[
        UPDATE `nyx_property_commercial_leases`
        SET `lease_status` = 'terminated',
            `security_deposit_held` = 0.00
        WHERE `lease_id` = ?
    ]], { leaseId })

    -- Relist property in public storefront cycle
    MySQL.prepare.await([[
        UPDATE `nyx_properties`
        SET `is_leased` = 0,
            `active_lease_id` = NULL,
            `lease_status` = 'available_for_lease'
        WHERE `property_id` = ?
    ]], { lease.propertyId })

    MySQL.prepare.await([[
        INSERT INTO `nyx_property_lease_audits`
            (`audit_uuid`, `lease_id`, `property_id`, `action`, `actor_citizen_id`, `amount`, `treasury_tx_uuid`, `notes`)
        VALUES (?, ?, ?, 'DEPOSIT_REFUNDED', ?, ?, ?, ?)
    ]], {
        generateTxUuid(), leaseId, lease.propertyId, player.citizenId,
        deposit, txUuid,
        reason or "Voluntary lease termination; property relisted into public storefront cycle"
    })

    lease.leaseStatus = 'terminated'
    lease.securityDepositHeld = 0.00

    local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[lease.propertyId]
    if prop then
        prop.isLeased = false
        prop.activeLeaseId = nil
        prop.leaseStatus = 'available_for_lease'
    end

    TriggerClientEvent("nyx:properties:client:leaseUpdated", -1, {
        propertyId = lease.propertyId,
        leaseId = leaseId,
        leaseStatus = "available_for_lease"
    })

    return true, {
        leaseId = leaseId,
        status = "terminated",
        depositRefunded = deposit
    }
end

-- ----------------------------------------------------------------------------
-- 7. Background Periodic Sweeper Thread (Runs Every 60s)
-- ----------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(60000)
        pcall(function()
            Nyx.Properties.ProcessLeaseBillingCycles()
        end)
    end
end)
