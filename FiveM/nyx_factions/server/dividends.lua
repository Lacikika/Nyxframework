--[[
    Nyxframework: nyx_factions
    File: server/dividends.lua
    Description: Automated equity dividend calculation, retained earnings allocation,
                 and double-entry ledger disbursement via nyx_treasury.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}

-- 1. Preview dividend payout breakdown without executing transfers
function Nyx.Factions.PreviewDividends(factionId, declaredNetProfit, reinvestmentRate)
    local profit = tonumber(declaredNetProfit) or 0.00
    if profit <= 0.00 then
        return false, "INVALID_PROFIT_AMOUNT"
    end

    local faction = Nyx.Factions.GetFaction(factionId)
    if not faction then return false, "FACTION_NOT_FOUND" end

    local minR = Config.Dividends and Config.Dividends.MinReinvestmentRate or 0.10
    local maxR = Config.Dividends and Config.Dividends.MaxReinvestmentRate or 0.50
    local defR = Config.Dividends and Config.Dividends.DefaultReinvestmentRate or 0.20

    local rate = tonumber(reinvestmentRate) or defR
    if rate < minR then rate = minR end
    if rate > maxR then rate = maxR end

    -- Retained Earnings = NetProfits * (1 - r_reinvest)
    local retainedEarnings = profit * (1.00 - rate)
    local companyReservesRetained = profit * rate

    -- Query all equity shareholders
    local members = MySQL.query.await([[
        SELECT `citizen_id`, `role_title`, `equity_shares`
        FROM `nyx_factions_members`
        WHERE `faction_id` = ? AND `equity_shares` > 0.00
        ORDER BY `equity_shares` DESC
    ]], { factionId })

    if not members or #members == 0 then
        return false, "NO_EQUITY_SHAREHOLDERS"
    end

    local totalShares = 0.00
    for _, m in ipairs(members) do
        totalShares = totalShares + tonumber(m.equity_shares)
    end

    if totalShares <= 0.00 then
        return false, "ZERO_TOTAL_EQUITY"
    end

    local payouts = {}
    local totalDisbursed = 0.00

    for _, m in ipairs(members) do
        local shares = tonumber(m.equity_shares)
        local fraction = shares / totalShares
        -- Truncate to cents to prevent fractional money creation
        local payout = math.floor((retainedEarnings * fraction) * 100) / 100
        totalDisbursed = totalDisbursed + payout

        table.insert(payouts, {
            citizenId = m.citizen_id,
            roleTitle = m.role_title,
            equityShares = shares,
            fraction = fraction,
            payoutAmount = payout
        })
    end

    return true, {
        factionId = factionId,
        declaredProfit = profit,
        reinvestmentRate = rate,
        companyReservesRetained = companyReservesRetained,
        retainedEarningsAvailable = retainedEarnings,
        totalDisbursed = totalDisbursed,
        shareholders = payouts
    }
end

-- 2. Execute authoritative dividend disbursement
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

    for _, s in ipairs(preview.shareholders) do
        if s.payoutAmount > 0.00 then
            local targetAcc = "citizen:" .. s.citizenId
            local transferOk, txId = exports['nyx_treasury']:ExecuteTransfer(
                faction.treasury_account_id,
                targetAcc,
                s.payoutAmount,
                "dividend_payout",
                "DIVIDENDS:" .. factionId,
                string.format("Dividend payout from %s (%.2f%% equity)", faction.legal_name, s.equityShares),
                0.0
            )

            if transferOk then
                successCount = successCount + 1
                table.insert(executedPayouts, {
                    citizenId = s.citizenId,
                    amount = s.payoutAmount,
                    txId = txId
                })

                -- Push notification if member is online
                local targetPlayer = Nyx.GetPlayerByCitizenId(s.citizenId)
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

    if Config.Debug then
        print(string.format("^2[Nyx:Factions]^7 Disbursed $%.2f in dividends across %d shareholders for %s^7",
            preview.totalDisbursed, successCount, factionId))
    end

    return true, {
        factionId = factionId,
        totalDisbursed = preview.totalDisbursed,
        successfulTransfers = successCount,
        payouts = executedPayouts
    }
end
