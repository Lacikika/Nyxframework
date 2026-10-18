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

    local accountsSummary = {}
    for id, acc in pairs(Nyx.Treasury.Accounts) do
        accountsSummary[#accountsSummary + 1] = {
            id = acc.id,
            label = acc.label,
            balance = acc.balance,
            type = acc.type
        }
    end

    local conservation = Nyx.Treasury.AssertConservation()

    return {
        masterReserve = currentMaster,
        targetReserve = Config.TargetReserve or 5000000.00,
        criticalReserve = Config.CriticalReserve or 500000.00,
        fiscalStatus = status,
        wageMultiplier = multiplier,
        salesTaxRate = Nyx.Treasury.ActiveSalesTax,
        transferTaxRate = Nyx.Treasury.ActiveTransferTax,
        accounts = accountsSummary,
        conservation = conservation
    }
end)

-- Paginated Public Ledger Explorer RPC
Nyx.RPC.Register("treasury:getLedgerPage", function(src, page, pageSize, category)
    page = math.max(1, tonumber(page) or 1)
    pageSize = math.min(100, math.max(5, tonumber(pageSize) or 20))
    local offset = (page - 1) * pageSize

    local query = "SELECT * FROM `nyx_treasury_ledger`"
    local countQuery = "SELECT COUNT(*) FROM `nyx_treasury_ledger`"
    local params = {}
    local countParams = {}

    if category and category ~= "ALL" and #category > 0 then
        query = query .. " WHERE `category` = ?"
        countQuery = countQuery .. " WHERE `category` = ?"
        params[#params + 1] = category
        countParams[#countParams + 1] = category
    end

    query = query .. " ORDER BY `entry_id` DESC LIMIT ? OFFSET ?"
    params[#params + 1] = pageSize
    params[#params + 1] = offset

    local rows = MySQL.query.await(query, params) or {}
    local totalEntries = MySQL.scalar.await(countQuery, countParams) or 0

    return {
        page = page,
        pageSize = pageSize,
        totalEntries = totalEntries,
        totalPages = math.ceil(totalEntries / pageSize),
        entries = rows
    }
end)

-- Municipal Allocations Explorer RPC
Nyx.RPC.Register("treasury:getAllocations", function(src)
    local rows = MySQL.query.await([[
        SELECT a.*, acc.label, acc.balance 
        FROM `nyx_treasury_allocations` a
        LEFT JOIN `nyx_treasury_accounts` acc ON a.target_department = acc.account_id
    ]])
    return rows or {}
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
