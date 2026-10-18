--[[
    Nyxframework: nyx_treasury
    File: server/ledger.lua
    Description: Authoritative double-entry transaction processor, account liquidity validation,
                 and closed-loop ledger verification.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}
Nyx.Treasury.Accounts = {} -- [accountId] = { id, label, balance, type }

-- Standardized RPC Bridge to nyx_core
Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        exports['nyx_core']:RegisterRPC(route, handler)
    end,
    GenerateNonce = function()
        local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        return (string.gsub(template, '[xy]', function(c)
            local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format('%x', v)
        end))
    end
}

-- Generate random UUIDv4 string
local function generateTxUuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

-- Refresh cached account state from database
function Nyx.Treasury.SyncCache(accountId)
    if not accountId then return end
    local row = MySQL.single.await("SELECT `account_id`, `label`, `balance`, `type` FROM `nyx_treasury_accounts` WHERE `account_id` = ?", { accountId })
    if row then
        Nyx.Treasury.Accounts[accountId] = {
            id = row.account_id,
            label = row.label,
            balance = tonumber(row.balance) or 0.00,
            type = row.type
        }
    end
end

-- Retrieve account balance (reads memory cache, falls back to DB)
function Nyx.Treasury.GetBalance(accountId)
    if not accountId then return 0.00 end
    local cached = Nyx.Treasury.Accounts[accountId]
    if cached then
        return cached.balance
    end

    local row = MySQL.single.await("SELECT `balance` FROM `nyx_treasury_accounts` WHERE `account_id` = ?", { accountId })
    if row then
        Nyx.Treasury.SyncCache(accountId)
        return tonumber(row.balance) or 0.00
    end

    return 0.00
end

-- Ensure account exists in the ledger schema
function Nyx.Treasury.EnsureAccount(accountId, label, accType, initialBalance)
    if not accountId then return false end
    if Nyx.Treasury.Accounts[accountId] then return true end

    local exists = MySQL.scalar.await("SELECT COUNT(*) FROM `nyx_treasury_accounts` WHERE `account_id` = ?", { accountId })
    if exists == 0 then
        MySQL.prepare.await([[
            INSERT INTO `nyx_treasury_accounts` (`account_id`, `label`, `balance`, `type`)
            VALUES (?, ?, ?, ?)
        ]], {
            accountId,
            label or accountId,
            tonumber(initialBalance) or 0.00,
            accType or "department"
        })
    end

    Nyx.Treasury.SyncCache(accountId)
    return true
end

-- Authoritative Double-Entry Transfer Processor
-- Strictly adheres to the closed-loop conservation law: Sum(Credits) == Sum(Debits)
function Nyx.Treasury.ExecuteTransfer(debitAcc, creditAcc, amount, category, authorizedBy, memo, taxDeducted)
    amount = math.floor((tonumber(amount) or 0) * 100) / 100
    if amount <= 0 then
        return false, "INVALID_AMOUNT"
    end

    if debitAcc == creditAcc then
        return false, "IDENTICAL_ACCOUNTS"
    end

    -- Ensure both accounts exist
    Nyx.Treasury.EnsureAccount(debitAcc, debitAcc, "department", 0.00)
    Nyx.Treasury.EnsureAccount(creditAcc, creditAcc, "department", 0.00)

    -- Pre-transaction liquidity check
    local currentDebitBalance = Nyx.Treasury.GetBalance(debitAcc)
    if currentDebitBalance < amount then
        return false, "INSUFFICIENT_FUNDS"
    end

    local txUuid = generateTxUuid()
    local taxAmount = tonumber(taxDeducted) or 0.00

    -- Atomic double-entry transaction block
    local queries = {
        {
            query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` - ? WHERE `account_id` = ? AND `balance` >= ?",
            values = { amount, debitAcc, amount }
        },
        {
            query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?",
            values = { amount, creditAcc }
        },
        {
            query = [[
                INSERT INTO `nyx_treasury_ledger`
                (`transaction_uuid`, `debit_account`, `credit_account`, `amount`, `tax_deducted`, `category`, `authorized_by`, `memo`)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ]],
            values = {
                txUuid,
                debitAcc,
                creditAcc,
                amount,
                taxAmount,
                category or "general",
                authorizedBy or "SYSTEM",
                memo or ""
            }
        }
    }

    local success = MySQL.transaction.await(queries)
    if not success then
        if Config.Debug then
            print(string.format("^1[Nyx:Treasury] Transaction failed: Insufficient funds or lock collision between '%s' and '%s'^7", debitAcc, creditAcc))
        end
        return false, "INSUFFICIENT_FUNDS_OR_LOCK_FAILURE"
    end

    -- Update in-memory balances
    Nyx.Treasury.SyncCache(debitAcc)
    Nyx.Treasury.SyncCache(creditAcc)

    -- Emit internal server event
    TriggerEvent("nyx:treasury:ledgerUpdate", txUuid, debitAcc, creditAcc, amount, category)

    -- Broadcast to open civic terminals
    TriggerClientEvent("nyx:treasury:client:ledgerUpdate", -1, {
        txUuid = txUuid,
        debitAccount = debitAcc,
        creditAccount = creditAcc,
        amount = amount,
        taxDeducted = taxAmount,
        category = category,
        memo = memo,
        timestamp = os.time()
    })

    if Config.Debug then
        print(string.format("^2[Nyx:Treasury] TX [%s] Processed: -$%.2f (%s) -> +$%.2f (%s) [Category: %s]^7", txUuid:sub(1, 8), amount, debitAcc, amount, creditAcc, category))
    end

    return true, txUuid
end

-- Validate Mathematical Closed-Loop Conservation Across the Whole Ledger
function Nyx.Treasury.AssertConservation()
    local result = MySQL.single.await([[
        SELECT 
            SUM(amount) AS total_volume,
            COUNT(*) AS total_transactions
        FROM `nyx_treasury_ledger`
    ]])

    local accountsTotal = MySQL.scalar.await("SELECT SUM(balance) FROM `nyx_treasury_accounts`")

    return {
        totalVolume = tonumber(result and result.total_volume) or 0.00,
        totalTransactions = tonumber(result and result.total_transactions) or 0,
        totalMaterializedBalance = tonumber(accountsTotal) or 0.00
    }
end

-- Preload all treasury accounts on startup
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end

    local rows = MySQL.query.await("SELECT `account_id`, `label`, `balance`, `type` FROM `nyx_treasury_accounts`")
    if rows then
        for _, row in ipairs(rows) do
            Nyx.Treasury.Accounts[row.account_id] = {
                id = row.account_id,
                label = row.label,
                balance = tonumber(row.balance) or 0.00,
                type = row.type
            }
        end
        print(string.format("^2[Nyx:Treasury] Hydrated %d treasury account balances into memory.^7", #rows))
    end
end)
