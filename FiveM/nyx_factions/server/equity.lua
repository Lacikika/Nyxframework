--[[
    Nyxframework: nyx_factions
    File: server/equity.lua
    Description: Authoritative server subsystem for corporate equity public offerings (IPO),
                 outside investor capital raising, cap table management, and purchase settlements
                 via double-entry treasury transfers.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}
Nyx.Factions.EquityOfferings = {} -- [offeringId] = offeringData

local function generateUuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return (string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end))
end

-- ----------------------------------------------------------------------------
-- 1. In-Memory Cache Hydration & Startup Sweeper
-- ----------------------------------------------------------------------------
function Nyx.Factions.HydrateEquityOfferings()
    local rows = MySQL.query.await([[
        SELECT o.*, f.`legal_name` as `faction_name`, UNIX_TIMESTAMP(o.`expires_at`) as `expires_at_unix`
        FROM `nyx_factions_equity_offerings` o
        JOIN `nyx_factions_registry` f ON o.`faction_id` = f.`faction_id`
        WHERE o.`status` = 'active'
    ]]) or {}

    Nyx.Factions.EquityOfferings = {}
    local now = os.time()

    for _, row in ipairs(rows) do
        -- Check for expiration during hydration
        if row.expires_at_unix and row.expires_at_unix < now then
            MySQL.prepare.await([[
                UPDATE `nyx_factions_equity_offerings`
                SET `status` = 'expired'
                WHERE `offering_id` = ?
            ]], { row.offering_id })
        else
            Nyx.Factions.EquityOfferings[row.offering_id] = {
                offeringId = row.offering_id,
                factionId = row.faction_id,
                factionName = row.faction_name,
                title = row.title,
                prospectus = row.prospectus,
                totalSharesOffered = tonumber(row.total_shares_offered) or 0.00,
                sharesAvailable = tonumber(row.shares_available) or 0.00,
                sharesSold = tonumber(row.shares_sold) or 0.00,
                pricePerShare = tonumber(row.price_per_share) or 0.00,
                minPurchase = tonumber(row.min_purchase) or 0.10,
                maxPurchase = tonumber(row.max_purchase) or 50.00,
                targetCapital = tonumber(row.target_capital) or 0.00,
                capitalRaised = tonumber(row.capital_raised) or 0.00,
                status = row.status,
                createdBy = row.created_by_citizen_id,
                expiresAtUnix = row.expires_at_unix
            }
        end
    end

    if Config.Debug then
        print(string.format("^2[Nyx:Factions]^7 Hydrated %d active equity offerings into cache.^7", #rows))
    end
end

CreateThread(function()
    Wait(500)
    Nyx.Factions.HydrateEquityOfferings()
end)

-- ----------------------------------------------------------------------------
-- 2. Query Total Issued Equity (Members + Outside Shareholders + Active Offerings)
-- ----------------------------------------------------------------------------
function Nyx.Factions.GetTotalCommittedEquity(factionId)
    local memberEquity = MySQL.scalar.await([[
        SELECT COALESCE(SUM(`equity_shares`), 0.00)
        FROM `nyx_factions_members`
        WHERE `faction_id` = ?
    ]], { factionId }) or 0.00

    local outsideEquity = MySQL.scalar.await([[
        SELECT COALESCE(SUM(`equity_shares`), 0.00)
        FROM `nyx_factions_equity_shareholders`
        WHERE `faction_id` = ? AND `is_external_investor` = 1
    ]], { factionId }) or 0.00

    local activeOfferingEquity = MySQL.scalar.await([[
        SELECT COALESCE(SUM(`shares_available`), 0.00)
        FROM `nyx_factions_equity_offerings`
        WHERE `faction_id` = ? AND `status` = 'active'
    ]], { factionId }) or 0.00

    return (tonumber(memberEquity) or 0.00) + (tonumber(outsideEquity) or 0.00) + (tonumber(activeOfferingEquity) or 0.00)
end

-- ----------------------------------------------------------------------------
-- 3. Create Public Equity Offering (IPO / Capital Raising)
-- ----------------------------------------------------------------------------
function Nyx.Factions.CreatePublicOffering(actorCitizenId, factionId, data)
    if actorCitizenId ~= "SYSTEM" and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "treasury:withdraw_high")
        and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "roster:promote") then
        return false, "INSUFFICIENT_PERMISSIONS_CREATE_OFFERING"
    end

    local faction = Nyx.Factions.GetFaction(factionId)
    if not faction then return false, "FACTION_NOT_FOUND" end

    local currentCommitted = Nyx.Factions.GetTotalCommittedEquity(factionId)
    local ok, cleanData = Nyx.Equity.ValidateOfferingCreation(faction, data, currentCommitted)
    if not ok then return false, cleanData end

    local offeringId = "offering_" .. string.sub(generateUuid(), 1, 13)

    local success = MySQL.prepare.await([[
        INSERT INTO `nyx_factions_equity_offerings`
            (`offering_id`, `faction_id`, `title`, `prospectus`, `total_shares_offered`,
             `shares_available`, `shares_sold`, `price_per_share`, `min_purchase`, `max_purchase`,
             `target_capital`, `capital_raised`, `status`, `created_by_citizen_id`, `expires_at`)
        VALUES (?, ?, ?, ?, ?, ?, 0.00, ?, ?, ?, ?, 0.00, 'active', ?, NOW() + INTERVAL ? HOUR)
    ]], {
        offeringId,
        factionId,
        cleanData.title,
        cleanData.prospectus,
        cleanData.totalSharesOffered,
        cleanData.sharesAvailable,
        cleanData.pricePerShare,
        cleanData.minPurchase,
        cleanData.maxPurchase,
        cleanData.targetCapital,
        actorCitizenId,
        cleanData.durationHours
    })

    if not success then
        return false, "DATABASE_ERROR_CREATING_OFFERING"
    end

    -- Update memory cache
    Nyx.Factions.EquityOfferings[offeringId] = {
        offeringId = offeringId,
        factionId = factionId,
        factionName = faction.legal_name,
        title = cleanData.title,
        prospectus = cleanData.prospectus,
        totalSharesOffered = cleanData.totalSharesOffered,
        sharesAvailable = cleanData.sharesAvailable,
        sharesSold = 0.00,
        pricePerShare = cleanData.pricePerShare,
        minPurchase = cleanData.minPurchase,
        maxPurchase = cleanData.maxPurchase,
        targetCapital = cleanData.targetCapital,
        capitalRaised = 0.00,
        status = 'active',
        createdBy = actorCitizenId,
        expiresAtUnix = os.time() + (cleanData.durationHours * 3600)
    }

    -- Log RBAC audit action
    if Nyx.Factions.LogRBACAction then
        Nyx.Factions.LogRBACAction(factionId, actorCitizenId, "MARKET", "CREATE_EQUITY_OFFERING", nil, {
            offeringId = offeringId,
            sharesOffered = cleanData.totalSharesOffered,
            pricePerShare = cleanData.pricePerShare,
            targetCapital = cleanData.targetCapital
        }, "Public equity offering issued to capital market")
    end

    print(string.format("^2[Nyx:Factions]^7 Created Equity Offering %s for %s: %.2f%% shares @ $%.2f (Target: $%.2f)^7",
        offeringId, faction.legal_name, cleanData.totalSharesOffered, cleanData.pricePerShare, cleanData.targetCapital))

    return true, Nyx.Factions.EquityOfferings[offeringId]
end

-- ----------------------------------------------------------------------------
-- 4. Purchase Equity Shares (Double-Entry Treasury Settlement)
-- ----------------------------------------------------------------------------
function Nyx.Factions.PurchaseEquityShares(investorCitizenId, offeringId, sharesRequested)
    if not investorCitizenId or not offeringId then
        return false, "INVALID_PURCHASE_ARGUMENTS"
    end

    local offeringRow = MySQL.single.await([[
        SELECT o.*, f.`legal_name` as `faction_name`, f.`treasury_account_id`,
               UNIX_TIMESTAMP(o.`expires_at`) as `expires_at_unix`
        FROM `nyx_factions_equity_offerings` o
        JOIN `nyx_factions_registry` f ON o.`faction_id` = f.`faction_id`
        WHERE o.`offering_id` = ?
    ]], { offeringId })

    if not offeringRow then
        return false, "OFFERING_NOT_FOUND"
    end

    local investorAccount = "citizen:" .. investorCitizenId
    local buyerBalance = exports['nyx_treasury']:GetAccountBalance(investorAccount) or 0.00

    local ok, purchaseDetails = Nyx.Equity.ValidatePurchaseRequest(
        offeringRow,
        investorCitizenId,
        sharesRequested,
        buyerBalance,
        os.time()
    )
    if not ok then return false, purchaseDetails end

    -- Authoritative double-entry capital transfer: Investor -> Corporation Treasury
    local memo = string.format("Equity share subscription in %s (%.2f%% shares @ $%.2f)",
        offeringRow.faction_name, purchaseDetails.shares, purchaseDetails.pricePerShare)

    local transferOk, txId = exports['nyx_treasury']:ExecuteTransfer(
        investorAccount,
        offeringRow.treasury_account_id,
        purchaseDetails.totalCost,
        "equity_capital_investment",
        "IPO:" .. offeringId,
        memo,
        0.00
    )

    if not transferOk then
        return false, string.format("TREASURY_TRANSFER_FAILED: %s", tostring(txId))
    end

    -- Determine new offering state
    local newSold = (tonumber(offeringRow.shares_sold) or 0.00) + purchaseDetails.shares
    local newAvail = purchaseDetails.remainingAvailable
    local newRaised = (tonumber(offeringRow.capital_raised) or 0.00) + purchaseDetails.totalCost
    local newStatus = (newAvail <= 0.001) and "completed" or "active"

    MySQL.prepare.await([[
        UPDATE `nyx_factions_equity_offerings`
        SET `shares_available` = ?,
            `shares_sold` = ?,
            `capital_raised` = ?,
            `status` = ?
        WHERE `offering_id` = ?
    ]], {
        newAvail,
        newSold,
        newRaised,
        newStatus,
        offeringId
    })

    -- Upsert into Cap Table: nyx_factions_equity_shareholders
    local existingHolding = MySQL.single.await([[
        SELECT `holding_id`, `equity_shares`, `total_invested`
        FROM `nyx_factions_equity_shareholders`
        WHERE `faction_id` = ? AND `citizen_id` = ?
    ]], { offeringRow.faction_id, investorCitizenId })

    if existingHolding then
        MySQL.prepare.await([[
            UPDATE `nyx_factions_equity_shareholders`
            SET `equity_shares` = `equity_shares` + ?,
                `total_invested` = `total_invested` + ?
            WHERE `holding_id` = ?
        ]], { purchaseDetails.shares, purchaseDetails.totalCost, existingHolding.holding_id })
    else
        MySQL.prepare.await([[
            INSERT INTO `nyx_factions_equity_shareholders`
                (`faction_id`, `citizen_id`, `equity_shares`, `is_external_investor`, `total_invested`)
            VALUES (?, ?, ?, 1, ?)
        ]], { offeringRow.faction_id, investorCitizenId, purchaseDetails.shares, purchaseDetails.totalCost })
    end

    -- Record immutable transaction in nyx_factions_equity_purchases
    local purchaseUuid = generateUuid()
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_equity_purchases`
            (`purchase_uuid`, `offering_id`, `faction_id`, `investor_citizen_id`,
             `shares_acquired`, `price_per_share`, `total_amount`, `treasury_tx_id`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        purchaseUuid,
        offeringId,
        offeringRow.faction_id,
        investorCitizenId,
        purchaseDetails.shares,
        purchaseDetails.pricePerShare,
        purchaseDetails.totalCost,
        txId
    })

    -- Physical bearer share certificate item generation in player inventory
    local targetPlayer = Nyx.GetPlayerByCitizenId and Nyx.GetPlayerByCitizenId(investorCitizenId)
    if targetPlayer and exports['nyx_inventory'] and exports['nyx_inventory'].AddItem then
        pcall(function()
            local invId = "citizen:" .. investorCitizenId
            local meta = {
                factionId = offeringRow.faction_id,
                companyName = offeringRow.faction_name,
                shares = purchaseDetails.shares,
                sharePrice = purchaseDetails.pricePerShare,
                offeringId = offeringId,
                issuedAt = os.time(),
                certificateUuid = string.format("EQ-%s-%06d",
                    string.upper(string.sub(offeringRow.faction_id, 1, 4)), math.random(100000, 999999))
            }
            exports['nyx_inventory']:AddItem(invId, 'equity_shares', 1, meta)
        end)
    end

    -- Update memory cache
    if Nyx.Factions.EquityOfferings[offeringId] then
        Nyx.Factions.EquityOfferings[offeringId].sharesAvailable = newAvail
        Nyx.Factions.EquityOfferings[offeringId].sharesSold = newSold
        Nyx.Factions.EquityOfferings[offeringId].capitalRaised = newRaised
        Nyx.Factions.EquityOfferings[offeringId].status = newStatus
    end

    -- Client Notification
    if targetPlayer then
        TriggerClientEvent("nyx:ui:notify", targetPlayer.source, {
            type = "success",
            title = "EQUITY PURCHASED",
            message = string.format("Acquired %.2f%% equity shares in %s for $%.2f.",
                purchaseDetails.shares, offeringRow.faction_name, purchaseDetails.totalCost)
        })
    end

    return true, {
        purchaseUuid = purchaseUuid,
        offeringId = offeringId,
        factionId = offeringRow.faction_id,
        factionName = offeringRow.faction_name,
        sharesAcquired = purchaseDetails.shares,
        pricePerShare = purchaseDetails.pricePerShare,
        totalCost = purchaseDetails.totalCost,
        treasuryTxId = txId,
        remainingSharesAvailable = newAvail,
        offeringStatus = newStatus
    }
end

-- ----------------------------------------------------------------------------
-- 5. Cancel Public Equity Offering
-- ----------------------------------------------------------------------------
function Nyx.Factions.CancelPublicOffering(actorCitizenId, offeringId, reason)
    local offering = MySQL.single.await([[
        SELECT `offering_id`, `faction_id`, `status`
        FROM `nyx_factions_equity_offerings`
        WHERE `offering_id` = ?
    ]], { offeringId })

    if not offering then return false, "OFFERING_NOT_FOUND" end
    if offering.status ~= "active" then return false, "OFFERING_NOT_ACTIVE" end

    if actorCitizenId ~= "SYSTEM" and not Nyx.Factions.HasPermission(actorCitizenId, offering.faction_id, "treasury:withdraw_high")
        and not Nyx.Factions.HasPermission(actorCitizenId, offering.faction_id, "roster:promote") then
        return false, "INSUFFICIENT_PERMISSIONS_CANCEL_OFFERING"
    end

    MySQL.prepare.await([[
        UPDATE `nyx_factions_equity_offerings`
        SET `status` = 'cancelled'
        WHERE `offering_id` = ?
    ]], { offeringId })

    if Nyx.Factions.EquityOfferings[offeringId] then
        Nyx.Factions.EquityOfferings[offeringId].status = 'cancelled'
    end

    if Nyx.Factions.LogRBACAction then
        Nyx.Factions.LogRBACAction(offering.faction_id, actorCitizenId, "MARKET", "CANCEL_EQUITY_OFFERING", nil, {
            offeringId = offeringId,
            reason = reason or "Offering cancelled by corporate officers"
        }, "Equity offering cancelled")
    end

    return true, { offeringId = offeringId, status = "cancelled" }
end

-- ----------------------------------------------------------------------------
-- 6. Cap Table, Portfolios & Offering Exploration Queries
-- ----------------------------------------------------------------------------

function Nyx.Factions.GetPublicOfferings(statusFilter)
    local query = [[
        SELECT o.*, f.`legal_name` as `faction_name`, UNIX_TIMESTAMP(o.`expires_at`) as `expires_at_unix`
        FROM `nyx_factions_equity_offerings` o
        JOIN `nyx_factions_registry` f ON o.`faction_id` = f.`faction_id`
    ]]
    local params = {}

    if statusFilter and statusFilter ~= "ALL" then
        query = query .. " WHERE o.`status` = ?"
        params[#params + 1] = statusFilter
    end

    query = query .. " ORDER BY o.`created_at` DESC"
    return MySQL.query.await(query, params) or {}
end

function Nyx.Factions.GetOfferingDetails(offeringId)
    if not offeringId then return nil end
    return MySQL.single.await([[
        SELECT o.*, f.`legal_name` as `faction_name`, f.`charter_type`,
               UNIX_TIMESTAMP(o.`expires_at`) as `expires_at_unix`
        FROM `nyx_factions_equity_offerings` o
        JOIN `nyx_factions_registry` f ON o.`faction_id` = f.`faction_id`
        WHERE o.`offering_id` = ?
    ]], { offeringId })
end

function Nyx.Factions.GetCitizenPortfolio(citizenId)
    if not citizenId then return {} end
    return MySQL.query.await([[
        SELECT s.*, f.`legal_name` as `faction_name`, f.`charter_type`
        FROM `nyx_factions_equity_shareholders` s
        JOIN `nyx_factions_registry` f ON s.`faction_id` = f.`faction_id`
        WHERE s.`citizen_id` = ? AND s.`equity_shares` > 0.00
        ORDER BY s.`equity_shares` DESC
    ]], { citizenId }) or {}
end

-- ----------------------------------------------------------------------------
-- 7. RPC Endpoints
-- ----------------------------------------------------------------------------
Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        exports['nyx_core']:RegisterRPC(route, handler)
    end
}

Nyx.RPC.Register("factions:getPublicOfferings", function(src, statusFilter)
    return Nyx.Factions.GetPublicOfferings(statusFilter)
end)

Nyx.RPC.Register("factions:getOfferingDetails", function(src, offeringId)
    return Nyx.Factions.GetOfferingDetails(offeringId)
end)

Nyx.RPC.Register("factions:createPublicOffering", function(src, payload)
    local player = Nyx.GetPlayer and Nyx.GetPlayer(src)
    local citizenId = player and player.citizenId or "CIT-UNKNOWN"
    local valOk, cleanPayload = Nyx.Equity.ValidateOfferingPayload(payload)
    if not valOk then return false, cleanPayload end

    return Nyx.Factions.CreatePublicOffering(citizenId, cleanPayload.factionId, cleanPayload)
end)

Nyx.RPC.Register("factions:purchaseEquityShares", function(src, payload)
    local player = Nyx.GetPlayer and Nyx.GetPlayer(src)
    local citizenId = player and player.citizenId or "CIT-UNKNOWN"
    local valOk, cleanPayload = Nyx.Equity.ValidatePurchasePayload(payload)
    if not valOk then return false, cleanPayload end

    return Nyx.Factions.PurchaseEquityShares(citizenId, cleanPayload.offeringId, cleanPayload.shares)
end)

Nyx.RPC.Register("factions:cancelPublicOffering", function(src, offeringId, reason)
    local player = Nyx.GetPlayer and Nyx.GetPlayer(src)
    local citizenId = player and player.citizenId or "CIT-UNKNOWN"
    return Nyx.Factions.CancelPublicOffering(citizenId, offeringId, reason)
end)

Nyx.RPC.Register("factions:getCitizenPortfolio", function(src, targetCitizenId)
    local player = Nyx.GetPlayer and Nyx.GetPlayer(src)
    local cid = targetCitizenId or (player and player.citizenId)
    return Nyx.Factions.GetCitizenPortfolio(cid)
end)

Nyx.RPC.Register("factions:getFactionCapTable", function(src, factionId)
    return Nyx.Factions.GetConsolidatedCapTable(factionId)
end)
