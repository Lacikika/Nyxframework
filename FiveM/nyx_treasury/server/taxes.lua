--[[
    Nyxframework: nyx_treasury
    File: server/taxes.lua
    Description: Dynamic point-of-sale tax interception, wire transfer duties,
                 and periodic municipal revenue redistribution.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}

Nyx.Treasury.ActiveSalesTax = Config.SalesTaxRate or 0.08
Nyx.Treasury.ActiveTransferTax = Config.TransferTaxRate or 0.02

-- Retrieve ratified tax rates
function Nyx.Treasury.GetTaxRate(taxType)
    if taxType == "transfer" then
        return Nyx.Treasury.ActiveTransferTax
    end
    return Nyx.Treasury.ActiveSalesTax
end

-- Update tax rate dynamically (can be triggered by parliamentary council votes)
function Nyx.Treasury.SetTaxRate(taxType, newRate, ratifiedBy)
    newRate = tonumber(newRate) or 0.00
    local maxRate = Config.MaxTaxRate or 0.15

    if newRate < 0.00 or newRate > maxRate then
        return false, "TAX_RATE_EXCEEDS_STATUTORY_BOUNDS"
    end

    if taxType == "transfer" then
        Nyx.Treasury.ActiveTransferTax = newRate
    else
        Nyx.Treasury.ActiveSalesTax = newRate
    end

    print(string.format("^3[Nyx:Treasury] Tax rate '%s' adjusted to %.2f%% by %s^7", taxType or "sales", newRate * 100, ratifiedBy or "EXECUTIVE"))
    return true
end

-- Calculate net and tax amounts (with optional localized zone surcharge)
function Nyx.Treasury.CalculateTaxSplit(grossAmount, rate, zoneId)
    grossAmount = math.floor((tonumber(grossAmount) or 0) * 100) / 100
    local r = rate or Nyx.Treasury.ActiveSalesTax

    -- Check if localized zone tax surcharge applies
    local zoneSurcharge = 0.0
    if zoneId then
        local ok, zone = pcall(function()
            return exports['nyx_logistics']:GetZone(zoneId)
        end)
        if ok and zone and zone.taxSurcharge then
            zoneSurcharge = tonumber(zone.taxSurcharge) or 0.0
        elseif Config.ZoneTaxSurcharges and Config.ZoneTaxSurcharges[zoneId] then
            zoneSurcharge = tonumber(Config.ZoneTaxSurcharges[zoneId]) or 0.0
        end
    end

    local maxRate = Config.MaxTaxRate or 0.15
    local effectiveRate = math.min(maxRate, math.max(0.0, r + zoneSurcharge))

    local taxAmount = math.floor((grossAmount * effectiveRate) * 100) / 100
    local netAmount = grossAmount - taxAmount
    return netAmount, taxAmount, effectiveRate, zoneSurcharge
end

-- Retrieve combined statutory and localized zone tax rate
function Nyx.Treasury.GetZoneTaxRate(zoneId)
    local baseRate = Nyx.Treasury.ActiveSalesTax or 0.08
    local zoneSurcharge = 0.0
    if zoneId then
        local ok, zone = pcall(function()
            return exports['nyx_logistics']:GetZone(zoneId)
        end)
        if ok and zone and zone.taxSurcharge then
            zoneSurcharge = tonumber(zone.taxSurcharge) or 0.0
        elseif Config.ZoneTaxSurcharges and Config.ZoneTaxSurcharges[zoneId] then
            zoneSurcharge = tonumber(Config.ZoneTaxSurcharges[zoneId]) or 0.0
        end
    end
    local maxRate = Config.MaxTaxRate or 0.15
    return math.min(maxRate, baseRate + zoneSurcharge)
end

-- Point-of-Sale (POS) Transaction Interceptor
-- Atomic Split: Buyer pays Gross -> Seller receives Net -> Municipal Tax Pool receives Tax
function Nyx.Treasury.ProcessPOSTransaction(buyerAcc, sellerAcc, grossAmount, memo, zoneId)
    grossAmount = math.floor((tonumber(grossAmount) or 0) * 100) / 100
    if grossAmount <= 0 then return false, "INVALID_GROSS_AMOUNT" end

    local netAmount, taxAmount, appliedRate, zoneSurcharge = Nyx.Treasury.CalculateTaxSplit(grossAmount, Nyx.Treasury.ActiveSalesTax, zoneId)
    local taxAcc = Config.Accounts.Tax or "gov:city:tax"

    Nyx.Treasury.EnsureAccount(buyerAcc, buyerAcc, "department", 0.00)
    Nyx.Treasury.EnsureAccount(sellerAcc, sellerAcc, "department", 0.00)
    Nyx.Treasury.EnsureAccount(taxAcc, "Consolidated Tax Pool", "tax_pool", 0.00)

    -- Pre-transaction liquidity check
    local buyerBal = Nyx.Treasury.GetBalance(buyerAcc)
    if buyerBal < grossAmount then
        return false, "INSUFFICIENT_BUYER_FUNDS"
    end

    local txNetUuid = Nyx.RPC.GenerateNonce()
    local txTaxUuid = Nyx.RPC.GenerateNonce()

    -- Atomic 3-Leg Transaction
    local queries = {
        {
            query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` - ? WHERE `account_id` = ? AND `balance` >= ?",
            values = { grossAmount, buyerAcc, grossAmount }
        },
        {
            query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?",
            values = { netAmount, sellerAcc }
        },
        {
            query = [[
                INSERT INTO `nyx_treasury_ledger`
                (`transaction_uuid`, `debit_account`, `credit_account`, `amount`, `tax_deducted`, `category`, `authorized_by`, `memo`)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ]],
            values = {
                txNetUuid,
                buyerAcc,
                sellerAcc,
                netAmount,
                taxAmount,
                "pos_sale",
                "MERCHANT_SYSTEM",
                memo or "Point-of-sale commerce settlement"
            }
        }
    }

    if taxAmount > 0 then
        queries[#queries + 1] = {
            query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?",
            values = { taxAmount, taxAcc }
        }
        queries[#queries + 1] = {
            query = [[
                INSERT INTO `nyx_treasury_ledger`
                (`transaction_uuid`, `debit_account`, `credit_account`, `amount`, `tax_deducted`, `category`, `authorized_by`, `memo`)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ]],
            values = {
                txTaxUuid,
                buyerAcc,
                taxAcc,
                taxAmount,
                0.00,
                "pos_tax",
                "TAX_INTERCEPTOR",
                string.format("Sales tax (%.1f%%%s) on POS TX #%s",
                    appliedRate * 100,
                    (zoneSurcharge > 0 and string.format(", incl. %.2f%% zone surcharge", zoneSurcharge * 100) or ""),
                    txNetUuid:sub(1, 8))
            }
        }
    end

    local success = MySQL.transaction.await(queries)
    if not success then
        return false, "INSUFFICIENT_FUNDS_OR_LOCK_FAILURE"
    end

    Nyx.Treasury.SyncCache(buyerAcc)
    Nyx.Treasury.SyncCache(sellerAcc)
    if taxAmount > 0 then
        Nyx.Treasury.SyncCache(taxAcc)
    end

    TriggerEvent("nyx:treasury:ledgerUpdate", txNetUuid, buyerAcc, sellerAcc, netAmount, "pos_sale")

    return true, {
        gross = grossAmount,
        net = netAmount,
        tax = taxAmount,
        rate = appliedRate,
        zoneSurcharge = zoneSurcharge,
        zoneId = zoneId,
        txUuid = txNetUuid
    }
end

-- P2P Bank Wire Transfer with Electronic Duty Interception
function Nyx.Treasury.ProcessP2PTransfer(senderCitizenId, receiverCitizenId, grossAmount, memo)
    grossAmount = math.floor((tonumber(grossAmount) or 0) * 100) / 100
    if grossAmount <= 0 then return false, "INVALID_TRANSFER_AMOUNT" end
    if senderCitizenId == receiverCitizenId then return false, "CANNOT_TRANSFER_TO_SELF" end

    local senderAcc = string.format("char:%s:bank", senderCitizenId)
    local receiverAcc = string.format("char:%s:bank", receiverCitizenId)
    local taxAcc = Config.Accounts.Tax or "gov:city:tax"

    local netAmount, taxAmount, appliedRate = Nyx.Treasury.CalculateTaxSplit(grossAmount, Nyx.Treasury.ActiveTransferTax)

    -- If sender is online, interact with authoritative PlayerObject
    local senderPlayer = exports['nyx_core']:GetPlayerByCitizenId(senderCitizenId)
    if senderPlayer then
        local currentBank = senderPlayer:getWallet("bank") or 0
        if currentBank < grossAmount then
            return false, "INSUFFICIENT_FUNDS"
        end
        senderPlayer:removeMoney("bank", grossAmount, memo or "P2P Wire Transfer")
    else
        local okDebit = MySQL.query.await("UPDATE `nyx_characters` SET `wallets` = JSON_SET(`wallets`, '$.bank', JSON_EXTRACT(`wallets`, '$.bank') - ?) WHERE `citizen_id` = ? AND JSON_EXTRACT(`wallets`, '$.bank') >= ?", {
            grossAmount,
            senderCitizenId,
            grossAmount
        })
        if not okDebit or okDebit.affectedRows == 0 then
            return false, "INSUFFICIENT_FUNDS"
        end
    end

    -- Credit receiver bank account
    local receiverPlayer = exports['nyx_core']:GetPlayerByCitizenId(receiverCitizenId)
    if receiverPlayer then
        receiverPlayer:addMoney("bank", netAmount, memo or "Received Wire Transfer")
    else
        MySQL.query.await("UPDATE `nyx_characters` SET `wallets` = JSON_SET(`wallets`, '$.bank', JSON_EXTRACT(`wallets`, '$.bank') + ?) WHERE `citizen_id` = ?", {
            netAmount,
            receiverCitizenId
        })
    end

    local txTransferUuid = Nyx.RPC.GenerateNonce()
    local txDutyUuid = Nyx.RPC.GenerateNonce()

    -- Atomic Treasury Ledger Trail ensuring Sum(Debits) == Sum(Credits)
    local ledgerQueries = {
        {
            query = [[
                INSERT INTO `nyx_treasury_ledger`
                (`transaction_uuid`, `debit_account`, `credit_account`, `amount`, `tax_deducted`, `category`, `authorized_by`, `memo`)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ]],
            values = {
                txTransferUuid,
                senderAcc,
                receiverAcc,
                netAmount,
                taxAmount,
                "transfer_p2p",
                senderCitizenId,
                memo or "Peer-to-peer wire transfer"
            }
        }
    }

    if taxAmount > 0 then
        Nyx.Treasury.EnsureAccount(taxAcc, "Consolidated Tax Pool", "tax_pool", 0.00)
        ledgerQueries[#ledgerQueries + 1] = {
            query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?",
            values = { taxAmount, taxAcc }
        }
        ledgerQueries[#ledgerQueries + 1] = {
            query = [[
                INSERT INTO `nyx_treasury_ledger`
                (`transaction_uuid`, `debit_account`, `credit_account`, `amount`, `tax_deducted`, `category`, `authorized_by`, `memo`)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ]],
            values = {
                txDutyUuid,
                senderAcc,
                taxAcc,
                taxAmount,
                0.00,
                "transfer_duty",
                "TAX_INTERCEPTOR",
                string.format("Transfer duty (%.1f%%) on wire transfer #%s", appliedRate * 100, txTransferUuid:sub(1, 8))
            }
        }
    end

    MySQL.transaction.await(ledgerQueries)
    if taxAmount > 0 then
        Nyx.Treasury.SyncCache(taxAcc)
    end

    return true, txTransferUuid
end

-- Periodic Municipal Revenue Redistribution Sweep
-- Traverses nyx_treasury_allocations, executes statutory percentage splits with cap overflow protection,
-- records immutable audit log in nyx_treasury_revenue_sweeps, and broadcasts telemetry to clients.
function Nyx.Treasury.SweepTaxes(executedBy)
    executedBy = executedBy or "REVENUE_SWEEP_DAEMON"
    local taxAcc = Config.Accounts.Tax or "gov:city:tax"
    local masterAcc = Config.Accounts.Master or "gov:city:master"
    local collected = Nyx.Treasury.GetBalance(taxAcc)

    if collected < 10.00 then
        return { success = false, reason = "INSUFFICIENT_POOL_BALANCE", collected = collected }
    end

    local allocations = MySQL.query.await("SELECT * FROM `nyx_treasury_allocations`")
    if not allocations or #allocations == 0 then
        -- Default fallback: Route 100% to municipal master reserve
        local ok, res = Nyx.Treasury.ExecuteTransfer(
            taxAcc,
            masterAcc,
            collected,
            "allocation",
            executedBy,
            "Default unallocated tax sweep to master reserve"
        )
        return { success = ok, collected = collected, fallback = true }
    end

    -- Hydrate current department balances for cap headroom evaluation
    local currentBalances = {}
    for _, alloc in ipairs(allocations) do
        local dept = alloc.target_department
        currentBalances[dept] = Nyx.Treasury.GetBalance(dept)
    end

    local sweepResult = Nyx.PublicLedger.CalculateSweepSplits(collected, allocations, currentBalances)
    if not sweepResult or not sweepResult.success then
        return sweepResult or { success = false }
    end

    print(string.format("^4[Nyx:Treasury]^7 Executing statutory revenue sweep: Collected $%.2f | Allocated $%.2f | Retained Surplus $%.2f^7",
        collected, sweepResult.totalAllocated, sweepResult.masterSurplusRetained))

    local sweepUuid = Nyx.RPC.GenerateNonce()
    local fiscalState = Nyx.Treasury.GetFiscalState()

    -- 1. Transfer departmental shares
    for _, split in ipairs(sweepResult.splits or {}) do
        if split.effectiveShare and split.effectiveShare > 0 then
            Nyx.Treasury.EnsureAccount(split.targetDepartment, split.departmentLabel, "department", 0.00)
            local memo = string.format("Automated statutory tax allocation (%.1f%%) [%s]", split.percentageSplit, split.allocationCategory)
            Nyx.Treasury.ExecuteTransfer(
                taxAcc,
                split.targetDepartment,
                split.effectiveShare,
                "allocation",
                executedBy,
                memo
            )

            pcall(function()
                MySQL.prepare.await([[
                    UPDATE `nyx_treasury_allocations`
                    SET `last_allocated_amount` = ?, `last_allocated_at` = CURRENT_TIMESTAMP
                    WHERE `target_department` = ?
                ]], { split.effectiveShare, split.targetDepartment })
            end)
        end
    end

    -- 2. Transfer master retained surplus (cap overflows & cent dust) if present
    if sweepResult.masterSurplusRetained and sweepResult.masterSurplusRetained > 0 then
        Nyx.Treasury.EnsureAccount(masterAcc, "Municipal Master Reserve", "public_master", 0.00)
        Nyx.Treasury.ExecuteTransfer(
            taxAcc,
            masterAcc,
            sweepResult.masterSurplusRetained,
            "allocation",
            executedBy,
            "Cap overflow surplus retained in Municipal Master Reserve"
        )
    end

    -- 3. Record immutable audit record in nyx_treasury_revenue_sweeps
    pcall(function()
        MySQL.prepare.await([[
            INSERT INTO `nyx_treasury_revenue_sweeps`
            (`sweep_uuid`, `tax_pool_balance_before`, `total_swept`, `master_surplus_retained`, `allocations_count`, `allocations_json`, `fiscal_state`, `executed_by`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            sweepUuid,
            collected,
            sweepResult.totalSwept,
            sweepResult.masterSurplusRetained,
            #sweepResult.splits,
            json.encode(sweepResult.splits),
            fiscalState,
            executedBy
        })
    end)

    -- 4. Broadcast event across server & clients
    TriggerEvent("nyx:treasury:revenueSweepExecuted", sweepUuid, sweepResult)
    TriggerClientEvent("nyx:treasury:client:sweepExecuted", -1, {
        sweepUuid = sweepUuid,
        collected = collected,
        totalSwept = sweepResult.totalSwept,
        splits = sweepResult.splits,
        fiscalState = fiscalState,
        timestamp = os.time()
    })

    return {
        success = true,
        sweepUuid = sweepUuid,
        sweepResult = sweepResult
    }
end

-- Revenue Sweep Background Thread
CreateThread(function()
    local sweepIntervalMs = (Config.TaxSweepInterval or 1800) * 1000
    while true do
        Wait(sweepIntervalMs)
        Nyx.Treasury.SweepTaxes()
    end
end)
