--[[
    Nyxframework: nyx_factions
    File: client/equity.lua
    Description: Client-side subsystem and interactive commands for corporate equity public offerings (IPO),
                 investor cap table explorer, stock purchasing, and automated dividend notifications.
]]

Nyx = Nyx or {}
Nyx.EquityClient = Nyx.EquityClient or {}

-- ----------------------------------------------------------------------------
-- 1. Helper RPC Invocation Wrapper
-- ----------------------------------------------------------------------------
local function callRPC(endpoint, ...)
    local promise = promise.new()
    exports['nyx_core']:CallRPC(endpoint, function(result, err)
        if result ~= nil then
            promise:resolve({ success = true, data = result })
        else
            promise:resolve({ success = false, error = err or "UNKNOWN_ERROR" })
        end
    end, ...)
    return Citizen.Await(promise)
end

-- ----------------------------------------------------------------------------
-- 2. Interactive Console & Chat Commands
-- ----------------------------------------------------------------------------

-- List active public equity offerings
RegisterCommand("stockmarket", function(source, args)
    local res = callRPC("factions:getPublicOfferings", "active")
    if not res.success or not res.data then
        TriggerEvent("chat:addMessage", {
            color = { 255, 80, 80 },
            multiline = true,
            args = { "[Stock Market]", "Failed to fetch corporate equity offerings from exchange." }
        })
        return
    end

    local offerings = res.data
    TriggerEvent("chat:addMessage", {
        color = { 80, 200, 120 },
        multiline = true,
        args = { "[Stock Market]", string.format("=== ACTIVE CORPORATE EQUITY OFFERINGS (%d) ===", #offerings) }
    })

    if #offerings == 0 then
        TriggerEvent("chat:addMessage", {
            color = { 200, 200, 200 },
            multiline = true,
            args = { "[Stock Market]", "No active IPO offerings on the market right now." }
        })
        return
    end

    for _, off in ipairs(offerings) do
        local msg = string.format("ID: ^3%s^7 | Corp: ^2%s^7 | Available: ^3%.2f%%^7 | Price: ^2$%.2f^7 per 1%% (Min: %.2f%%)",
            off.offering_id or off.offeringId,
            off.faction_name or off.factionName or off.faction_id,
            tonumber(off.shares_available or off.sharesAvailable) or 0.0,
            tonumber(off.price_per_share or off.pricePerShare) or 0.0,
            tonumber(off.min_purchase or off.minPurchase) or 0.1)
        TriggerEvent("chat:addMessage", {
            color = { 255, 255, 255 },
            multiline = true,
            args = { "[IPO]", msg }
        })
    end
end, false)

-- Purchase equity shares from an offering
RegisterCommand("buyequity", function(source, args)
    local offeringId = args[1]
    local shares = tonumber(args[2])

    if not offeringId or not shares or shares <= 0 then
        TriggerEvent("chat:addMessage", {
            color = { 255, 180, 50 },
            multiline = true,
            args = { "[Stock Market]", "Usage: /buyequity <offeringId> <sharesPercentage>" }
        })
        return
    end

    local res = callRPC("factions:purchaseEquityShares", {
        offeringId = offeringId,
        shares = shares
    })

    if not res.success or not res.data then
        local errMsg = res.error or (type(res.data) == "string" and res.data) or "Purchase failed"
        TriggerEvent("chat:addMessage", {
            color = { 255, 80, 80 },
            multiline = true,
            args = { "[Stock Market]", string.format("Transaction rejected: %s", tostring(errMsg)) }
        })
        return
    end

    local d = res.data
    TriggerEvent("chat:addMessage", {
        color = { 80, 220, 100 },
        multiline = true,
        args = { "[Stock Market]", string.format("Successfully purchased %.2f%% shares in %s for $%.2f (Tx: %s)",
            d.sharesAcquired, d.factionName or d.factionId, d.totalCost, string.sub(tostring(d.treasuryTxId), 1, 8)) }
    })
end, false)

-- View player's stock and equity portfolio
RegisterCommand("myportfolio", function(source, args)
    local res = callRPC("factions:getCitizenPortfolio")
    if not res.success or not res.data then
        TriggerEvent("chat:addMessage", {
            color = { 255, 80, 80 },
            multiline = true,
            args = { "[Portfolio]", "Failed to retrieve equity holdings." }
        })
        return
    end

    local holdings = res.data
    TriggerEvent("chat:addMessage", {
        color = { 60, 160, 255 },
        multiline = true,
        args = { "[Portfolio]", string.format("=== CITIZEN EQUITY PORTFOLIO (%d HOLDINGS) ===", #holdings) }
    })

    if #holdings == 0 then
        TriggerEvent("chat:addMessage", {
            color = { 200, 200, 200 },
            multiline = true,
            args = { "[Portfolio]", "You currently do not hold any corporate equity shares." }
        })
        return
    end

    for _, h in ipairs(holdings) do
        local msg = string.format("Corp: ^2%s^7 | Equity: ^3%.2f%%^7 | Total Invested: ^2$%.2f^7 | Dividends Earned: ^2$%.2f^7",
            h.faction_name or h.faction_id,
            tonumber(h.equity_shares) or 0.0,
            tonumber(h.total_invested) or 0.0,
            tonumber(h.total_dividends_collected) or 0.0)
        TriggerEvent("chat:addMessage", {
            color = { 255, 255, 255 },
            multiline = true,
            args = { "[Stock Holding]", msg }
        })
    end
end, false)

-- View corporate cap table
RegisterCommand("captable", function(source, args)
    local factionId = args[1]
    if not factionId then
        TriggerEvent("chat:addMessage", {
            color = { 255, 180, 50 },
            multiline = true,
            args = { "[Cap Table]", "Usage: /captable <factionId>" }
        })
        return
    end

    local res = callRPC("factions:getFactionCapTable", factionId)
    if not res.success or not res.data then
        TriggerEvent("chat:addMessage", {
            color = { 255, 80, 80 },
            multiline = true,
            args = { "[Cap Table]", "Failed to load corporate cap table." }
        })
        return
    end

    local list = res.data
    TriggerEvent("chat:addMessage", {
        color = { 220, 160, 60 },
        multiline = true,
        args = { "[Cap Table]", string.format("=== CAP TABLE: %s (%d SHAREHOLDERS) ===", factionId, #list) }
    })

    for _, s in ipairs(list) do
        local tag = s.isExternal and "[Investor]" or "[Member]"
        local msg = string.format("%s Citizen: ^3%s^7 | Role: ^2%s^7 | Equity: ^3%.2f%%^7",
            tag, s.citizenId, s.roleTitle, s.equityShares)
        TriggerEvent("chat:addMessage", {
            color = { 255, 255, 255 },
            multiline = true,
            args = { "[Shareholder]", msg }
        })
    end
end, false)

-- Manual corporate officer dividend declaration
RegisterCommand("distributedividends", function(source, args)
    local factionId = args[1]
    local netProfit = tonumber(args[2])
    local reinvestRate = tonumber(args[3]) or 0.20

    if not factionId or not netProfit or netProfit <= 0 then
        TriggerEvent("chat:addMessage", {
            color = { 255, 180, 50 },
            multiline = true,
            args = { "[Dividends]", "Usage: /distributedividends <factionId> <declaredNetProfit> [reinvestRate (0.10-0.50)]" }
        })
        return
    end

    local res = callRPC("factions:distributeDividends", {
        factionId = factionId,
        netProfit = netProfit,
        reinvestmentRate = reinvestRate
    })

    if not res.success or not res.data then
        local err = res.error or (type(res.data) == "string" and res.data) or "Distribution failed"
        TriggerEvent("chat:addMessage", {
            color = { 255, 80, 80 },
            multiline = true,
            args = { "[Dividends]", string.format("Failed to disburse dividends: %s", tostring(err)) }
        })
        return
    end

    local d = res.data
    TriggerEvent("chat:addMessage", {
        color = { 80, 220, 100 },
        multiline = true,
        args = { "[Dividends]", string.format("Disbursed $%.2f in dividends across %d shareholders (Retained: $%.2f).",
            d.totalDisbursed, d.successfulTransfers, d.retainedReserves or 0.0) }
    })
end, false)

-- ----------------------------------------------------------------------------
-- 3. Public Client Exports
-- ----------------------------------------------------------------------------
exports("GetPublicOfferings", function(statusFilter)
    return callRPC("factions:getPublicOfferings", statusFilter)
end)

exports("PurchaseEquityShares", function(offeringId, shares)
    return callRPC("factions:purchaseEquityShares", { offeringId = offeringId, shares = tonumber(shares) })
end)

exports("GetCitizenPortfolio", function(citizenId)
    return callRPC("factions:getCitizenPortfolio", citizenId)
end)

exports("GetCapTable", function(factionId)
    return callRPC("factions:getFactionCapTable", factionId)
end)

exports("PreviewDividends", function(factionId, netProfit, rate)
    return callRPC("factions:previewDividends", { factionId = factionId, netProfit = tonumber(netProfit), reinvestmentRate = tonumber(rate) })
end)

exports("DistributeDividends", function(factionId, netProfit, rate)
    return callRPC("factions:distributeDividends", { factionId = factionId, netProfit = tonumber(netProfit), reinvestmentRate = tonumber(rate) })
end)
