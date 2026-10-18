--[[
    Nyxframework: nyx_properties
    File: server/taxation.lua
    Description: Authoritative Property Taxation, Exponential Holding Multiplier Assessment,
                 Dynamic Land Footprint Collection, Delinquency Escalation & Revenue Splits.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}

local function generateTxUuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

-- 1. Count Total Properties Owned by a Citizen (Excluding Forfeited / Reclaimed)
function Nyx.Properties.CountCitizenProperties(citizenId)
    if not citizenId then return 1 end

    local count = 0
    if Nyx.Properties.Loaded then
        for _, p in pairs(Nyx.Properties.Loaded) do
            if p.ownerCitizenId == citizenId and not p.reclaimedForAuction then
                count = count + 1
            end
        end
    end

    if count > 0 then
        return count
    end

    local dbCount = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_properties`
        WHERE `owner_citizen_id` = ? AND `reclaimed_for_auction` = 0
    ]], { citizenId })

    return math.max(1, tonumber(dbCount) or 1)
end

-- 2. Get Structured Assessment for Property
function Nyx.Properties.GetAssessmentForProperty(propertyId)
    propertyId = tonumber(propertyId)
    local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[propertyId]
    if not prop then return nil end

    local propertiesOwned = 1
    if prop.ownerCitizenId then
        propertiesOwned = Nyx.Properties.CountCitizenProperties(prop.ownerCitizenId)
    end

    return Nyx.Taxation.CalculateTotalAssessment({
        price = prop.price,
        baseMillageRate = prop.millageRate,
        propertiesOwned = propertiesOwned,
        landAreaSqm = prop.landAreaSqm or 150.00,
        propertyType = prop.type or "residential",
        zoneId = prop.zoneId or "zone_ls_metro",
        condition = prop.maintenanceCondition or 100.00,
        overdueArrears = prop.delinquentAmount or 0.00,
        missedCycles = prop.consecutiveMissedCycles or 0
    })
end

-- 3. Execute Closed-Loop Tax Assessment & Collection
function Nyx.Properties.ExecuteTaxCollection(propertyId)
    propertyId = tonumber(propertyId)
    local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[propertyId]
    if not prop or not prop.ownerCitizenId or prop.reclaimedForAuction then
        return false, "NOT_OWNED_OR_AUCTIONED"
    end

    local citizenId = prop.ownerCitizenId
    local assessment = Nyx.Properties.GetAssessmentForProperty(propertyId)
    if not assessment then
        return false, "ASSESSMENT_FAILED"
    end

    local totalDue = assessment.totalTaxDue
    if totalDue <= 0.00 then
        MySQL.prepare("UPDATE `nyx_properties` SET `last_tax_billed_at` = NOW() WHERE `property_id` = ?", { propertyId })
        return true, assessment
    end

    local ownerPlayer = exports['nyx_core']:GetPlayerByCitizenId(citizenId)
    local debitSuccess = false
    local paymentMethod = "online_bank"

    if ownerPlayer then
        local bankBal = ownerPlayer:getWallet("bank") or 0
        if bankBal >= totalDue then
            ownerPlayer:removeMoney("bank", totalDue, string.format("Városi Ingatlan- és Telekadó: %s", prop.label))
            debitSuccess = true
            paymentMethod = "online_bank"
        end
    else
        -- Offline citizen bank balance deduction
        local charRow = MySQL.single.await("SELECT `wallets`, `money` FROM `nyx_characters` WHERE `citizen_id` = ?", { citizenId })
        if charRow then
            local wallets = charRow.wallets and json.decode(charRow.wallets)
            local legacyMoney = charRow.money and json.decode(charRow.money)
            local currentBank = (wallets and tonumber(wallets.bank)) or (legacyMoney and tonumber(legacyMoney.bank)) or 0

            if currentBank >= totalDue then
                local newBank = currentBank - totalDue
                if wallets then
                    wallets.bank = newBank
                    MySQL.prepare("UPDATE `nyx_characters` SET `wallets` = ? WHERE `citizen_id` = ?", { json.encode(wallets), citizenId })
                elseif legacyMoney then
                    legacyMoney.bank = newBank
                    MySQL.prepare("UPDATE `nyx_characters` SET `money` = ? WHERE `citizen_id` = ?", { json.encode(legacyMoney), citizenId })
                end
                debitSuccess = true
                paymentMethod = "offline_bank"
            end
        end
    end

    local txUuid = generateTxUuid()

    if debitSuccess then
        -- 3.1 Closed-Loop Treasury Revenue Split (Tervek.md Section 1.1)
        local splits = Nyx.Taxation.CalculateRevenueDistribution(totalDue)
        local emergencyAcc = "gov:dept:police"
        local worksAcc = "gov:dept:works"
        local masterAcc = Config.Millage.TreasuryAccount or "gov:city:master"

        if exports['nyx_treasury'] and exports['nyx_treasury'].EnsureAccount then
            exports['nyx_treasury']:EnsureAccount(emergencyAcc, "Emergency Services Fund", "department", 0.00)
            exports['nyx_treasury']:EnsureAccount(worksAcc, "Public Works Infrastructure", "department", 0.00)
            exports['nyx_treasury']:EnsureAccount(masterAcc, "City Master Treasury", "department", 0.00)
        end

        local queries = {
            -- Credit Emergency Services Fund (40%)
            {
                query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?",
                values = { splits.emergency, emergencyAcc }
            },
            -- Credit Public Works Fund (45%)
            {
                query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?",
                values = { splits.works, worksAcc }
            },
            -- Credit City Master Reserve (15% + cent balance)
            {
                query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?",
                values = { splits.master, masterAcc }
            },
            -- Insert consolidated double-entry ledger record
            {
                query = [[
                    INSERT INTO `nyx_treasury_ledger`
                    (`transaction_uuid`, `debit_account`, `credit_account`, `amount`, `category`, `authorized_by`, `memo`)
                    VALUES (?, ?, ?, ?, 'property_tax', 'TAX_OFFICE', ?)
                ]],
                values = {
                    txUuid,
                    string.format("char:%s:bank", citizenId),
                    masterAcc,
                    totalDue,
                    string.format("Progressive millage & land tax (#%d %s - holding x%.2f)",
                        propertyId, prop.label, assessment.holdingMultiplier)
                }
            }
        }

        MySQL.transaction.await(queries)

        if exports['nyx_treasury'] and exports['nyx_treasury'].SyncCache then
            exports['nyx_treasury'].SyncCache(emergencyAcc)
            exports['nyx_treasury'].SyncCache(worksAcc)
            exports['nyx_treasury'].SyncCache(masterAcc)
        end

        -- Record tax assessment
        MySQL.prepare([[
            INSERT INTO `nyx_property_tax_assessments`
            (`property_id`, `owner_citizen_id`, `properties_owned_count`, `base_millage_rate`,
             `progressive_holding_multiplier`, `effective_millage_rate`, `millage_tax_amount`,
             `land_area_sqm`, `maintenance_tax_amount`, `penalty_amount`, `total_tax_due`,
             `status`, `treasury_tx_uuid`, `payment_method`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'paid', ?, ?)
        ]], {
            propertyId,
            citizenId,
            assessment.propertiesOwned,
            assessment.baseMillageRate,
            assessment.holdingMultiplier,
            assessment.effectiveMillageRate,
            assessment.millageTax,
            assessment.landAreaSqm,
            assessment.maintenanceTax,
            assessment.penalty,
            totalDue,
            txUuid,
            paymentMethod
        })

        -- Audit trail
        MySQL.prepare([[
            INSERT INTO `nyx_property_audit`
            (`property_id`, `action`, `actor_citizen_id`, `amount`, `treasury_tx_uuid`, `notes`)
            VALUES (?, 'MILLAGE_TAX_DEBIT', ?, ?, ?, ?)
        ]], {
            propertyId,
            citizenId,
            totalDue,
            txUuid,
            string.format("Tax settled: Millage $%.2f + Land $%.2f + Penalty $%.2f",
                assessment.millageTax, assessment.maintenanceTax, assessment.penalty)
        })

        -- Reset delinquency records
        prop.delinquencyTier = 0
        prop.delinquentAmount = 0.00
        prop.consecutiveMissedCycles = 0

        MySQL.prepare([[
            UPDATE `nyx_properties`
            SET `last_tax_billed_at` = NOW(),
                `delinquency_tier` = 0,
                `delinquent_amount` = 0.00,
                `consecutive_missed_cycles` = 0
            WHERE `property_id` = ?
        ]], { propertyId })

        if ownerPlayer then
            TriggerClientEvent("nyx:ui:notify", ownerPlayer.source, {
                type = "info",
                title = "ÉPÍTMÉNY- ÉS TELEKADÓ LEVONVA",
                message = string.format("Levonva: $%.2f adó a(z) %s után (Szorzó: %.2fx, %dm²).",
                    totalDue, prop.label, assessment.holdingMultiplier, math.floor(assessment.landAreaSqm))
            })
        end

        return true, assessment
    else
        -- 3.2 Delinquency Escalation & Sanctions
        prop.consecutiveMissedCycles = (prop.consecutiveMissedCycles or 0) + 1
        local newTier, tierLabel = Nyx.Taxation.EvaluateDelinquencyTier(prop.consecutiveMissedCycles)
        prop.delinquencyTier = newTier
        prop.delinquentAmount = (prop.delinquentAmount or 0.00) + totalDue

        MySQL.prepare([[
            INSERT INTO `nyx_property_tax_assessments`
            (`property_id`, `owner_citizen_id`, `properties_owned_count`, `base_millage_rate`,
             `progressive_holding_multiplier`, `effective_millage_rate`, `millage_tax_amount`,
             `land_area_sqm`, `maintenance_tax_amount`, `penalty_amount`, `total_tax_due`,
             `status`, `payment_method`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'delinquent', 'delinquency_ledger')
        ]], {
            propertyId,
            citizenId,
            assessment.propertiesOwned,
            assessment.baseMillageRate,
            assessment.holdingMultiplier,
            assessment.effectiveMillageRate,
            assessment.millageTax,
            assessment.landAreaSqm,
            assessment.maintenanceTax,
            assessment.penalty,
            totalDue
        })

        MySQL.prepare([[
            UPDATE `nyx_properties`
            SET `last_tax_billed_at` = NOW(),
                `delinquency_tier` = ?,
                `delinquent_amount` = ?,
                `consecutive_missed_cycles` = ?
            WHERE `property_id` = ?
        ]], {
            newTier,
            prop.delinquentAmount,
            prop.consecutiveMissedCycles,
            propertyId
        })

        -- Tier 3: Foreclosure Warning & Door Lockout Interlock
        if newTier == 3 then
            prop.isLocked = true
            MySQL.prepare("UPDATE `nyx_properties` SET `is_locked` = 1 WHERE `property_id` = ?", { propertyId })
            TriggerClientEvent("nyx:properties:client:lockUpdated", -1, propertyId, true)

            MySQL.prepare([[
                INSERT INTO `nyx_property_audit`
                (`property_id`, `action`, `actor_citizen_id`, `notes`)
                VALUES (?, 'LOCK_TOGGLE', 'MUNICIPAL_TAX_OFFICE', 'Door locked due to Tier 3 Tax Delinquency')
            ]], { propertyId })

            if ownerPlayer then
                TriggerClientEvent("nyx:ui:notify", ownerPlayer.source, {
                    type = "error",
                    title = "ADÓHÁTRALÉK MIATTI ZÁROLÁS",
                    message = string.format("A(z) %s ingatlan zárolva lett $%.2f hátralék miatt!",
                        prop.label, prop.delinquentAmount)
                })
            end
        end

        -- Tier 4: Asset Forfeiture & Public Blind Auction Reclamation
        if newTier >= 4 then
            if Nyx.Properties.ForfeitPropertyToAuction then
                Nyx.Properties.ForfeitPropertyToAuction(propertyId)
            end
        end

        return false, "DELINQUENT_INSUFFICIENT_FUNDS", assessment
    end
end

-- 4. RPC: Query Property Tax & Maintenance Assessment
exports['nyx_core']:RegisterRPC("properties:getTaxAssessment", function(src, propertyId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    propertyId = tonumber(propertyId)
    local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[propertyId]
    if not prop then return { success = false, error = "PROPERTY_NOT_FOUND" } end

    local assessment = Nyx.Properties.GetAssessmentForProperty(propertyId)
    if not assessment then
        return { success = false, error = "CALCULATION_FAILED" }
    end

    local repairCost, pointsNeeded = Nyx.Taxation.CalculateRepairCost(prop.landAreaSqm or 150.0, prop.maintenanceCondition or 100.0)

    return {
        success = true,
        propertyId = propertyId,
        label = prop.label,
        ownerCitizenId = prop.ownerCitizenId,
        isOwner = (prop.ownerCitizenId == player.citizenId),
        assessment = assessment,
        repairCost = repairCost,
        pointsNeeded = pointsNeeded,
        isReclaimed = (prop.reclaimedForAuction == true)
    }
end)

-- 5. RPC: Pay Delinquent Tax Arrears
exports['nyx_core']:RegisterRPC("properties:payDelinquentTaxes", function(src, propertyId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    propertyId = tonumber(propertyId)
    local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[propertyId]
    if not prop then return { success = false, error = "PROPERTY_NOT_FOUND" } end

    if prop.ownerCitizenId ~= player.citizenId then
        return { success = false, error = "NOT_PROPERTY_OWNER" }
    end

    local arrears = tonumber(prop.delinquentAmount) or 0.00
    if arrears <= 0.00 then
        return { success = false, error = "NO_DELINQUENT_ARREARS" }
    end

    local bankBal = player:getWallet("bank") or 0
    if bankBal < arrears then
        return { success = false, error = "INSUFFICIENT_FUNDS" }
    end

    player:removeMoney("bank", arrears, string.format("Adóhátralék Befizetése: %s", prop.label))

    local txUuid = generateTxUuid()
    local masterAcc = Config.Millage.TreasuryAccount or "gov:city:master"
    local emergencyAcc = "gov:dept:police"
    local worksAcc = "gov:dept:works"

    local splits = Nyx.Taxation.CalculateRevenueDistribution(arrears)

    MySQL.transaction.await({
        {
            query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?",
            values = { splits.emergency, emergencyAcc }
        },
        {
            query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?",
            values = { splits.works, worksAcc }
        },
        {
            query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?",
            values = { splits.master, masterAcc }
        },
        {
            query = [[
                INSERT INTO `nyx_treasury_ledger`
                (`transaction_uuid`, `debit_account`, `credit_account`, `amount`, `category`, `authorized_by`, `memo`)
                VALUES (?, ?, ?, ?, 'property_tax_arrears', ?, ?)
            ]],
            values = {
                txUuid,
                string.format("char:%s:bank", player.citizenId),
                masterAcc,
                arrears,
                player.citizenId,
                string.format("Delinquent property tax arrears paid (#%d %s)", propertyId, prop.label)
            }
        }
    })

    -- Reset arrears in memory and DB
    prop.delinquentAmount = 0.00
    prop.delinquencyTier = 0
    prop.consecutiveMissedCycles = 0

    MySQL.prepare([[
        UPDATE `nyx_properties`
        SET `delinquent_amount` = 0.00,
            `delinquency_tier` = 0,
            `consecutive_missed_cycles` = 0
        WHERE `property_id` = ?
    ]], { propertyId })

    -- Audit log
    MySQL.prepare([[
        INSERT INTO `nyx_property_audit`
        (`property_id`, `action`, `actor_citizen_id`, `amount`, `treasury_tx_uuid`, `notes`)
        VALUES (?, 'MILLAGE_TAX_DEBIT', ?, ?, ?, 'Delinquent arrears fully settled by owner')
    ]], { propertyId, player.citizenId, arrears, txUuid })

    return {
        success = true,
        propertyId = propertyId,
        amountPaid = arrears,
        delinquencyTier = 0
    }
end)

-- 6. RPC: Structural Repair of Property Condition
exports['nyx_core']:RegisterRPC("properties:repairCondition", function(src, propertyId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    propertyId = tonumber(propertyId)
    local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[propertyId]
    if not prop then return { success = false, error = "PROPERTY_NOT_FOUND" } end

    if prop.ownerCitizenId ~= player.citizenId then
        return { success = false, error = "NOT_PROPERTY_OWNER" }
    end

    local currentCond = prop.maintenanceCondition or 100.00
    if currentCond >= 100.00 then
        return { success = false, error = "ALREADY_PRISTINE_CONDITION" }
    end

    local repairCost, pointsNeeded = Nyx.Taxation.CalculateRepairCost(prop.landAreaSqm or 150.0, currentCond)
    if repairCost <= 0.00 then
        return { success = false, error = "ZERO_REPAIR_COST" }
    end

    local bankBal = player:getWallet("bank") or 0
    if bankBal < repairCost then
        return { success = false, error = "INSUFFICIENT_FUNDS" }
    end

    player:removeMoney("bank", repairCost, string.format("Ingatlan Felújítás & Karbantartás: %s", prop.label))

    -- Transfer fee directly to Public Works Fund (gov:dept:works)
    local worksAcc = "gov:dept:works"
    local txUuid = generateTxUuid()

    MySQL.transaction.await({
        {
            query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?",
            values = { repairCost, worksAcc }
        },
        {
            query = [[
                INSERT INTO `nyx_treasury_ledger`
                (`transaction_uuid`, `debit_account`, `credit_account`, `amount`, `category`, `authorized_by`, `memo`)
                VALUES (?, ?, ?, ?, 'property_maintenance', ?, ?)
            ]],
            values = {
                txUuid,
                string.format("char:%s:bank", player.citizenId),
                worksAcc,
                repairCost,
                player.citizenId,
                string.format("Structural repair (+%.1f%%) for #%d %s", pointsNeeded, propertyId, prop.label)
            }
        }
    })

    prop.maintenanceCondition = 100.00

    MySQL.prepare([[
        UPDATE `nyx_properties`
        SET `maintenance_condition` = 100.00,
            `last_maintenance_at` = NOW()
        WHERE `property_id` = ?
    ]], { propertyId })

    MySQL.prepare([[
        INSERT INTO `nyx_property_audit`
        (`property_id`, `action`, `actor_citizen_id`, `amount`, `treasury_tx_uuid`, `notes`)
        VALUES (?, 'LOCK_TOGGLE', ?, ?, ?, 'Property structural repair restored to 100%')
    ]], { propertyId, player.citizenId, repairCost, txUuid })

    return {
        success = true,
        propertyId = propertyId,
        newCondition = 100.00,
        costPaid = repairCost
    }
end)
