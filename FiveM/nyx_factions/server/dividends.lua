--[[
    Nyxframework: nyx_factions
    File: server/dividends.lua
    Description: Automated equity dividend calculation, retained earnings allocation,
                 consolidated cap table distribution, and double-entry ledger disbursement
                 via nyx_treasury with periodic automated schedule cycles.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}

local function generateUuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return (string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end))
end

-- ----------------------------------------------------------------------------
-- 1. Query Consolidated Corporate Cap Table (Internal Members + Outside Investors)
-- ----------------------------------------------------------------------------
function Nyx.Factions.GetConsolidatedCapTable(factionId)
    if not factionId then return {} end

    -- Query internal corporate members
    local members = MySQL.query.await([[
        SELECT `citizen_id`, `role_title`, `equity_shares`
        FROM `nyx_factions_members`
        WHERE `faction_id` = ? AND `equity_shares` > 0.00
    ]], { factionId }) or {}

    -- Query external equity shareholders
    local investors = MySQL.query.await([[
        SELECT `citizen_id`, `equity_shares`, `is_external_investor`, `total_invested`, `total_dividends_collected`
        FROM `nyx_factions_equity_shareholders`
        WHERE `faction_id` = ? AND `equity_shares` > 0.00
    ]], { factionId }) or {}

    local capMap = {}

    -- Add internal member equity
    for _, m in ipairs(members) do
        local cid = m.citizen_id
        capMap[cid] = {
            citizenId = cid,
            roleTitle = m.role_title or "Founding Member",
            equityShares = tonumber(m.equity_shares) or 0.00,
            isExternal = false,
            totalInvested = 0.00,
            totalDividends = 0.00
        }
    end

    -- Add or merge outside investors
    for _, inv in ipairs(investors) do
        local cid = inv.citizen_id
        local shares = tonumber(inv.equity_shares) or 0.00
        if capMap[cid] then
            capMap[cid].equityShares = capMap[cid].equityShares + shares
            capMap[cid].totalInvested = (capMap[cid].totalInvested or 0.00) + (tonumber(inv.total_invested) or 0.00)
            capMap[cid].totalDividends = (capMap[cid].totalDividends or 0.00) + (tonumber(inv.total_dividends_collected) or 0.00)
        else
            capMap[cid] = {
                citizenId = cid,
                roleTitle = "Equity Shareholder",
                equityShares = shares,
                isExternal = true,
                totalInvested = tonumber(inv.total_invested) or 0.00,
                totalDividends = tonumber(inv.total_dividends_collected) or 0.00
            }
        end
    end

    local list = {}
    for _, item in pairs(capMap) do
        list[#list + 1] = item
    end

    table.sort(list, function(a, b)
        return a.equityShares > b.equityShares
    end)

    return list
end

-- ----------------------------------------------------------------------------
-- 2. Preview Dividend Payout Breakdown
-- ----------------------------------------------------------------------------
function Nyx.Factions.PreviewDividends(factionId, declaredNetProfit, reinvestmentRate)
    local profit = tonumber(declaredNetProfit) or 0.00
    if profit <= 0.00 then
        return false, "INVALID_PROFIT_AMOUNT"
    end

    local faction = Nyx.Factions.GetFaction(factionId)
    if not faction then return false, "FACTION_NOT_FOUND" end

    local minR = Config.Dividends and Config.Dividends.MinReinvestmentRate or Nyx.Equity.MinReinvestmentRate
    local maxR = Config.Dividends and Config.Dividends.MaxReinvestmentRate or Nyx.Equity.MaxReinvestmentRate
    local defR = Config.Dividends and Config.Dividends.DefaultReinvestmentRate or (faction.reinvestment_rate_target or Nyx.Equity.DefaultReinvestmentRate)

    local rate = tonumber(reinvestmentRate) or defR
    if rate < minR then rate = minR end
    if rate > maxR then rate = maxR end

    local capTable = Nyx.Factions.GetConsolidatedCapTable(factionId)
    if not capTable or #capTable == 0 then
        return false, "NO_EQUITY_SHAREHOLDERS"
    end

    local calcOk, dist = Nyx.Equity.CalculateDividendDistribution(profit, rate, capTable)
    if not calcOk then
        return false, dist
    end

    return true, {
        factionId = factionId,
        factionName = faction.legal_name,
        declaredProfit = dist.declaredNetProfit,
        reinvestmentRate = dist.reinvestmentRate,
        companyReservesRetained = dist.retainedReserves,
        retainedEarningsAvailable = dist.distributablePool,
        totalDisbursed = dist.totalDisbursed,
        subCentRemainder = dist.subCentRemainder,
        totalShares = dist.totalShares,
        shareholderCount = dist.shareholderCount,
        shareholders = dist.payouts
    }
end

-- ----------------------------------------------------------------------------
-- 3. Execute Authoritative Dividend Disbursement
-- ----------------------------------------------------------------------------
function Nyx.Factions.DistributeDividends(factionId, declaredNetProfit, reinvestmentRate, executingCitizenId)
    if executingCitizenId ~= "SYSTEM" and not Nyx.Factions.HasPermission(executingCitizenId, factionId, "treasury:withdraw_high") then
        return false, "INSUFFICIENT_PERMISSIONS_DIVIDENDS"
    end

    local ok, preview = Nyx.Factions.PreviewDividends(factionId, declaredNetProfit, reinvestmentRate)
    if not ok then return false, preview end

    local faction = Nyx.Factions.GetFaction(factionId)
    local currentBal = exports['nyx_treasury']:GetAccountBalance(faction.treasury_account_id) or 0.00

    if currentBal < preview.totalDisbursed then
        return false, string.format("INSUFFICIENT_FACTION_BALANCE_REQUIRED_%.2f", preview.totalDisbursed)
    end

    local executedPayouts = {}
    local successCount = 0
    local txIds = {}

    for _, s in ipairs(preview.shareholders) do
        if s.payoutAmount > 0.00 then
            local targetAcc = "citizen:" .. s.citizenId
            local memo = string.format("Dividend payout from %s (%.2f%% equity)", faction.legal_name, s.equityShares)

            local transferOk, txId = exports['nyx_treasury']:ExecuteTransfer(
                faction.treasury_account_id,
                targetAcc,
                s.payoutAmount,
                "dividend_payout",
                "DIVIDENDS:" .. factionId,
                memo,
                0.0
            )

            if transferOk then
                successCount = successCount + 1
                txIds[#txIds + 1] = txId

                table.insert(executedPayouts, {
                    citizenId = s.citizenId,
                    amount = s.payoutAmount,
                    txId = txId
                })

                -- Update shareholder collected statistics
                MySQL.prepare.await([[
                    UPDATE `nyx_factions_equity_shareholders`
                    SET `total_dividends_collected` = `total_dividends_collected` + ?,
                        `last_dividend_at` = NOW()
                    WHERE `faction_id` = ? AND `citizen_id` = ?
                ]], { s.payoutAmount, factionId, s.citizenId })

                -- Push notification if shareholder is online
                local targetPlayer = Nyx.GetPlayerByCitizenId and Nyx.GetPlayerByCitizenId(s.citizenId)
                if targetPlayer then
                    TriggerClientEvent("nyx:ui:notify", targetPlayer.source, {
                        type = "success",
                        title = "DIVIDEND RECEIVED",
                        message = string.format("Received $%.2f dividend distribution from %s.",
                            s.payoutAmount, faction.legal_name)
                    })
                end
            end
        end
    end

    -- Update faction last dividend timestamp in registry
    MySQL.prepare.await([[
        UPDATE `nyx_factions_registry`
        SET `last_dividend_run_at` = NOW()
        WHERE `faction_id` = ?
    ]], { factionId })

    -- Record immutable audit log in nyx_factions_dividend_runs
    local runUuid = generateUuid()
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_dividend_runs`
            (`run_uuid`, `faction_id`, `declared_net_profit`, `reinvestment_rate`,
             `retained_reserves_amount`, `total_disbursed`, `shareholder_count`,
             `treasury_tx_ids`, `executed_by_citizen_id`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'completed')
    ]], {
        runUuid,
        factionId,
        preview.declaredProfit,
        preview.reinvestmentRate,
        preview.companyReservesRetained,
        preview.totalDisbursed,
        successCount,
        json.encode(txIds),
        executingCitizenId or "SYSTEM"
    })

    if Config.Debug then
        print(string.format("^2[Nyx:Factions]^7 Disbursed $%.2f in dividends across %d shareholders for %s (Retained: $%.2f)^7",
            preview.totalDisbursed, successCount, factionId, preview.companyReservesRetained))
    end

    return true, {
        runUuid = runUuid,
        factionId = factionId,
        totalDisbursed = preview.totalDisbursed,
        retainedReserves = preview.companyReservesRetained,
        successfulTransfers = successCount,
        payouts = executedPayouts
    }
end

-- ----------------------------------------------------------------------------
-- 4. Automated Weekly Dividend Distribution Engine
-- ----------------------------------------------------------------------------
function Nyx.Factions.ProcessAutomatedDividendCycles()
    local corporations = MySQL.query.await([[
        SELECT `faction_id`, `legal_name`, `charter_type`, `treasury_account_id`,
               `dividend_frequency_days`, `auto_dividends_enabled`, `reinvestment_rate_target`,
               UNIX_TIMESTAMP(`last_dividend_run_at`) as `last_dividend_unix`
        FROM `nyx_factions_registry`
        WHERE `is_active` = 1 AND `auto_dividends_enabled` = 1
          AND `charter_type` IN ('corporation', 'private_enterprise', 'syndicate')
    ]]) or {}

    local processedCount = 0
    local totalDistributed = 0.00
    local now = os.time()

    for _, corp in ipairs(corporations) do
        local balance = exports['nyx_treasury']:GetAccountBalance(corp.treasury_account_id) or 0.00
        local isEligible, recommendedProfit, surplus = Nyx.Equity.EvaluateDividendEligibility(
            corp,
            balance,
            corp.last_dividend_unix,
            now,
            {
                reserveFloor = Nyx.Equity.OperationalReserveFloor,
                frequencyDays = corp.dividend_frequency_days or Nyx.Equity.DefaultDividendFrequencyDays,
                reinvestmentRate = corp.reinvestment_rate_target or Nyx.Equity.DefaultReinvestmentRate
            }
        )

        if isEligible and type(recommendedProfit) == "number" and recommendedProfit > 0 then
            local distOk, result = Nyx.Factions.DistributeDividends(
                corp.faction_id,
                recommendedProfit,
                corp.reinvestment_rate_target,
                "SYSTEM"
            )

            if distOk then
                processedCount = processedCount + 1
                totalDistributed = totalDistributed + (result.totalDisbursed or 0.00)
                print(string.format("^3[Nyx:Factions:Dividends]^7 Automated cycle executed for %s: $%.2f disbursed to shareholders.^7",
                    corp.legal_name, result.totalDisbursed or 0.00))
            end
        end
    end

    return processedCount, totalDistributed
end

-- Background Thread for Weekly Automated Dividend Sweeper
CreateThread(function()
    local intervalMs = (Config.EquityOfferings and Config.EquityOfferings.AutoDividendSweeperInterval or 300) * 1000
    while true do
        Wait(intervalMs)
        pcall(Nyx.Factions.ProcessAutomatedDividendCycles)
    end
end)

-- ----------------------------------------------------------------------------
-- 5. Dividend History Query
-- ----------------------------------------------------------------------------
function Nyx.Factions.GetDividendHistory(factionId, limit)
    limit = math.min(100, math.max(1, tonumber(limit) or 20))
    local query = [[
        SELECT r.*, f.`legal_name` as `faction_name`
        FROM `nyx_factions_dividend_runs` r
        JOIN `nyx_factions_registry` f ON r.`faction_id` = f.`faction_id`
    ]]
    local params = {}

    if factionId and factionId ~= "ALL" then
        query = query .. " WHERE r.`faction_id` = ?"
        params[#params + 1] = factionId
    end

    query = query .. " ORDER BY r.`created_at` DESC LIMIT ?"
    params[#params + 1] = limit

    return MySQL.query.await(query, params) or {}
end

-- ----------------------------------------------------------------------------
-- 6. RPC Endpoints
-- ----------------------------------------------------------------------------
Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        exports['nyx_core']:RegisterRPC(route, handler)
    end
}

Nyx.RPC.Register("factions:previewDividends", function(src, payload)
    local valOk, cleanPayload = Nyx.Equity.ValidateDividendPayload(payload)
    if not valOk then return false, cleanPayload end
    return Nyx.Factions.PreviewDividends(cleanPayload.factionId, cleanPayload.netProfit, cleanPayload.reinvestmentRate)
end)

Nyx.RPC.Register("factions:distributeDividends", function(src, payload)
    local player = Nyx.GetPlayer and Nyx.GetPlayer(src)
    local citizenId = player and player.citizenId or "CIT-UNKNOWN"
    local valOk, cleanPayload = Nyx.Equity.ValidateDividendPayload(payload)
    if not valOk then return false, cleanPayload end

    return Nyx.Factions.DistributeDividends(
        cleanPayload.factionId,
        cleanPayload.netProfit,
        cleanPayload.reinvestmentRate,
        citizenId
    )
end)

Nyx.RPC.Register("factions:getDividendHistory", function(src, factionId, limit)
    return Nyx.Factions.GetDividendHistory(factionId, limit)
end)

Nyx.RPC.Register("factions:processDividendCycle", function(src)
    local player = Nyx.GetPlayer and Nyx.GetPlayer(src)
    if not player or not player.hasPermission or not player.hasPermission("admin") then
        return false, "UNAUTHORIZED"
    end
    local count, total = Nyx.Factions.ProcessAutomatedDividendCycles()
    return true, { processedCount = count, totalDistributed = total }
end)
