--[[
    Nyxframework: nyx_treasury
    File: server/main.lua
    Description: Treasury RPC endpoints, public transparency query routes, and lifecycle bindings.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}

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

-- Public Financial Overview RPC
Nyx.RPC.Register("treasury:getPublicOverview", function(src)
    local multiplier, status, currentMaster = Nyx.Treasury.GetWageMultiplier()

    -- Hydrate accounts summary from database/cache
    local dbAccounts = MySQL.query.await("SELECT `account_id`, `label`, `balance`, `type`, `circuit_exempt` FROM `nyx_treasury_accounts`") or {}
    local accountsSummary = {}
    for _, acc in ipairs(dbAccounts) do
        accountsSummary[#accountsSummary + 1] = {
            id = acc.account_id,
            account_id = acc.account_id,
            label = acc.label,
            balance = tonumber(acc.balance) or 0.00,
            type = acc.type,
            circuit_exempt = acc.circuit_exempt
        }
    end

    local balanceSheet = Nyx.PublicLedger.CalculateBalanceSheet(
        accountsSummary,
        Config.TargetReserve or 5000000.00,
        Config.CriticalReserve or 500000.00
    )

    local circuitTelemetry = Nyx.Treasury.GetCircuitTelemetry()
    local fiscalTelemetry = Nyx.PublicLedger.CalculateFiscalTelemetry(
        currentMaster,
        circuitTelemetry,
        Config.TargetReserve or 5000000.00,
        Config.CriticalReserve or 500000.00,
        Config.CautionReserve or 2500000.00
    )

    -- Fetch enriched statutory allocations
    local allocRows = MySQL.query.await([[
        SELECT a.*, acc.label, acc.balance 
        FROM `nyx_treasury_allocations` a
        LEFT JOIN `nyx_treasury_accounts` acc ON a.target_department = acc.account_id
    ]]) or {}

    local allocations = {}
    for _, alloc in ipairs(allocRows) do
        local catMeta = Nyx.PublicLedger.AllocationCategories[alloc.allocation_category] or Nyx.PublicLedger.AllocationCategories["general"]
        local bal = tonumber(alloc.balance) or 0.00
        local cap = tonumber(alloc.cap_limit)
        local progressPct = (cap and cap > 0) and math.min(100.0, (bal / cap) * 100.0) or 0.0

        allocations[#allocations + 1] = {
            targetDepartment = alloc.target_department,
            departmentLabel = alloc.department_label or alloc.label or alloc.target_department,
            allocationCategory = alloc.allocation_category or "general",
            categoryLabel = catMeta.label,
            statutoryPillar = catMeta.statutoryPillar,
            percentageSplit = tonumber(alloc.percentage_split) or 0.00,
            capLimit = cap,
            currentBalance = bal,
            progressPercentage = math.floor(progressPct * 10) / 10,
            ratifiedByBillId = alloc.ratified_by_bill_id,
            lastAllocatedAmount = tonumber(alloc.last_allocated_amount) or 0.00,
            lastAllocatedAt = alloc.last_allocated_at
        }
    end

    -- Recent transactions
    local recentTxs = MySQL.query.await([[
        SELECT * FROM `nyx_treasury_ledger`
        ORDER BY `entry_id` DESC LIMIT 15
    ]]) or {}

    -- Latest revenue sweep audit
    local lastSweep = MySQL.single.await([[
        SELECT * FROM `nyx_treasury_revenue_sweeps`
        ORDER BY `sweep_id` DESC LIMIT 1
    ]])

    local conservation = Nyx.Treasury.AssertConservation()

    return {
        success = true,
        masterReserve = currentMaster,
        targetReserve = Config.TargetReserve or 5000000.00,
        cautionReserve = Config.CautionReserve or 2500000.00,
        recoveryReserve = Config.RecoveryReserve or 1000000.00,
        criticalReserve = Config.CriticalReserve or 500000.00,
        fiscalStatus = status,
        fiscalState = Nyx.Treasury.GetFiscalState(),
        wageMultiplier = multiplier,
        salesTaxRate = Nyx.Treasury.ActiveSalesTax,
        transferTaxRate = Nyx.Treasury.ActiveTransferTax,
        balanceSheet = balanceSheet,
        fiscalTelemetry = fiscalTelemetry,
        accounts = balanceSheet.accounts,
        allocations = allocations,
        lastSweep = lastSweep,
        recentTransactions = recentTxs,
        conservation = conservation,
        circuitBreaker = circuitTelemetry,
        municipalDegraded = (Nyx.Treasury.GetFiscalState() == "CRITICAL_DEFICIT" or Nyx.Treasury.IsCircuitTripped())
    }
end)

-- Dedicated Open Municipal Balance Sheet RPC
Nyx.RPC.Register("treasury:getBalanceSheet", function(src)
    local dbAccounts = MySQL.query.await("SELECT `account_id`, `label`, `balance`, `type`, `circuit_exempt` FROM `nyx_treasury_accounts`") or {}
    local sheet = Nyx.PublicLedger.CalculateBalanceSheet(
        dbAccounts,
        Config.TargetReserve or 5000000.00,
        Config.CriticalReserve or 500000.00
    )
    return {
        success = true,
        balanceSheet = sheet
    }
end)

-- Paginated & Categorized Public Ledger Explorer RPC (Zero-Trust)
Nyx.RPC.Register("treasury:getLedgerPage", function(src, p1, p2, p3, p4)
    local rawParams = {}
    if type(p1) == "table" then
        rawParams = p1
    else
        rawParams = {
            page = p1,
            pageSize = p2,
            category = p3,
            search = p4
        }
    end

    local clean = Nyx.PublicLedger.SanitizeLedgerQuery(rawParams)

    local query = "SELECT * FROM `nyx_treasury_ledger` WHERE 1=1"
    local countQuery = "SELECT COUNT(*) FROM `nyx_treasury_ledger` WHERE 1=1"
    local params = {}
    local countParams = {}

    if clean.category and clean.category ~= "ALL" then
        query = query .. " AND `category` = ?"
        countQuery = countQuery .. " AND `category` = ?"
        params[#params + 1] = clean.category
        countParams[#countParams + 1] = clean.category
    end

    if clean.search and #clean.search > 0 then
        local pattern = "%" .. clean.search .. "%"
        query = query .. " AND (`debit_account` LIKE ? OR `credit_account` LIKE ? OR `memo` LIKE ? OR `transaction_uuid` LIKE ?)"
        countQuery = countQuery .. " AND (`debit_account` LIKE ? OR `credit_account` LIKE ? OR `memo` LIKE ? OR `transaction_uuid` LIKE ?)"
        for _ = 1, 4 do
            params[#params + 1] = pattern
            countParams[#countParams + 1] = pattern
        end
    end

    query = query .. " ORDER BY `entry_id` DESC LIMIT ? OFFSET ?"
    params[#params + 1] = clean.pageSize
    params[#params + 1] = clean.offset

    local rows = MySQL.query.await(query, params) or {}
    local totalEntries = MySQL.scalar.await(countQuery, countParams) or 0
    local totalPages = math.max(1, math.ceil(totalEntries / clean.pageSize))

    return {
        success = true,
        page = clean.page,
        pageSize = clean.pageSize,
        totalEntries = totalEntries,
        totalPages = totalPages,
        category = clean.category,
        search = clean.search,
        entries = rows,
        categories = Nyx.PublicLedger.TransactionCategories
    }
end)

-- Municipal Allocations Explorer RPC
Nyx.RPC.Register("treasury:getAllocations", function(src)
    local rows = MySQL.query.await([[
        SELECT a.*, acc.label, acc.balance 
        FROM `nyx_treasury_allocations` a
        LEFT JOIN `nyx_treasury_accounts` acc ON a.target_department = acc.account_id
    ]]) or {}

    local allocations = {}
    for _, alloc in ipairs(rows) do
        local catMeta = Nyx.PublicLedger.AllocationCategories[alloc.allocation_category] or Nyx.PublicLedger.AllocationCategories["general"]
        local bal = tonumber(alloc.balance) or 0.00
        local cap = tonumber(alloc.cap_limit)
        local progressPct = (cap and cap > 0) and math.min(100.0, (bal / cap) * 100.0) or 0.0

        allocations[#allocations + 1] = {
            targetDepartment = alloc.target_department,
            departmentLabel = alloc.department_label or alloc.label or alloc.target_department,
            allocationCategory = alloc.allocation_category or "general",
            categoryLabel = catMeta.label,
            statutoryPillar = catMeta.statutoryPillar,
            percentageSplit = tonumber(alloc.percentage_split) or 0.00,
            capLimit = cap,
            currentBalance = bal,
            progressPercentage = math.floor(progressPct * 10) / 10,
            ratifiedByBillId = alloc.ratified_by_bill_id,
            lastAllocatedAmount = tonumber(alloc.last_allocated_amount) or 0.00,
            lastAllocatedAt = alloc.last_allocated_at
        }
    end

    return allocations
end)

-- Dedicated Revenue Sweeps Audit History RPC
Nyx.RPC.Register("treasury:getRevenueSweeps", function(src, limit)
    limit = math.max(1, math.min(50, tonumber(limit) or 15))
    local rows = MySQL.query.await([[
        SELECT * FROM `nyx_treasury_revenue_sweeps`
        ORDER BY `sweep_id` DESC LIMIT ?
    ]], { limit }) or {}

    return {
        success = true,
        sweeps = rows
    }
end)

-- Commodity Market & Consumer Price Index Explorer RPC
Nyx.RPC.Register("treasury:getMarketIndex", function(src)
    local ok, summary = pcall(function()
        return exports['nyx_logistics']:GetMarketSummary()
    end)

    if ok and summary then
        return {
            success = true,
            citywideCpi = summary.citywideCpi,
            zones = summary.zones,
            salesTaxRate = Nyx.Treasury.ActiveSalesTax,
            transferTaxRate = Nyx.Treasury.ActiveTransferTax
        }
    end

    return {
        success = true,
        citywideCpi = 1.0,
        zones = {},
        salesTaxRate = Nyx.Treasury.ActiveSalesTax,
        transferTaxRate = Nyx.Treasury.ActiveTransferTax
    }
end)

-- Dedicated Fiscal Circuit Breaker Telemetry RPC
Nyx.RPC.Register("treasury:getCircuitStatus", function(src)
    return {
        success = true,
        telemetry = Nyx.Treasury.GetCircuitTelemetry()
    }
end)

-- Public Service Payroll History RPC
Nyx.RPC.Register("treasury:getPayrollHistory", function(src, limit)
    limit = math.min(50, math.max(1, tonumber(limit) or 10))
    local rows = MySQL.query.await("SELECT * FROM `nyx_treasury_payroll_runs` ORDER BY `run_id` DESC LIMIT ?", { limit })
    return {
        success = true,
        runs = rows or {}
    }
end)
