--[[
    Nyxframework: nyx_properties
    File: server/auction.lua
    Description: Municipal Foreclosure Reclamation Engine & Blind-Auction Settlement.
                 Handles asset forfeiture upon delinquency tier 4, escrowed bidding,
                 closed-loop outbid refunds, and automated deed transference.
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

-- 1. Forfeit Property to Municipal Blind Auction
function Nyx.Properties.ForfeitPropertyToAuction(propertyId)
    propertyId = tonumber(propertyId)
    local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[propertyId]
    if not prop then return false, "PROPERTY_NOT_FOUND" end

    local previousOwner = prop.ownerCitizenId
    local discount = (Config.Taxation and Config.Taxation.Auction and Config.Taxation.Auction.MinBidDiscountRate) or 0.50
    local minBid = math.floor((prop.price * discount) * 100) / 100
    if minBid <= 0.00 then minBid = 1000.00 end

    local durationHours = (Config.Taxation and Config.Taxation.Auction and Config.Taxation.Auction.DurationHours) or 48

    -- Revoke owner and all keys
    prop.ownerCitizenId = nil
    prop.reclaimedForAuction = true
    prop.isLocked = true

    MySQL.prepare([[
        UPDATE `nyx_properties`
        SET `owner_citizen_id` = NULL,
            `reclaimed_for_auction` = 1,
            `is_locked` = 1
        WHERE `property_id` = ?
    ]], { propertyId })

    MySQL.prepare("DELETE FROM `nyx_property_keys` WHERE `property_id` = ?", { propertyId })

    -- Insert active auction
    local auctionId = MySQL.insert.await([[
        INSERT INTO `nyx_property_auctions`
        (`property_id`, `previous_owner_citizen_id`, `minimum_bid`, `highest_bid`,
         `auction_status`, `started_at`, `ends_at`)
        VALUES (?, ?, ?, 0.00, 'active', NOW(), NOW() + INTERVAL ? HOUR)
    ]], { propertyId, previousOwner, minBid, durationHours })

    -- Audit log
    MySQL.prepare([[
        INSERT INTO `nyx_property_audit`
        (`property_id`, `action`, `actor_citizen_id`, `amount`, `notes`)
        VALUES (?, 'LOCK_TOGGLE', ?, ?, ?)
    ]], {
        propertyId,
        previousOwner or "TAX_OFFICE",
        minBid,
        string.format("Foreclosure forfeiture: Transferred to public auction #%s (Min bid $%.2f)",
            tostring(auctionId), minBid)
    })

    print(string.format("^1[Nyx:Properties:Auction] Property #%d (%s) forfeited to auction #%s (Min: $%.2f)^7",
        propertyId, prop.label, tostring(auctionId), minBid))

    -- Broadcast civic alert to all online players
    TriggerClientEvent("nyx:ui:notify", -1, {
        type = "warning",
        title = "INGATLAN ÁRVERÉS",
        message = string.format("A(z) %s ingatlan árverésre került! Kikiáltási ár: $%.2f", prop.label, minBid)
    })

    return true, auctionId
end

-- 2. Place Bid on Active Auction (Escrowed Funds & Outbid Refunds)
function Nyx.Properties.PlaceAuctionBid(citizenId, auctionId, bidAmount)
    auctionId = tonumber(auctionId)
    bidAmount = math.floor((tonumber(bidAmount) or 0.00) * 100) / 100

    local auction = MySQL.single.await([[
        SELECT * FROM `nyx_property_auctions`
        WHERE `auction_id` = ? AND `auction_status` = 'active' AND `ends_at` > NOW()
    ]], { auctionId })

    if not auction then
        return false, "AUCTION_NOT_ACTIVE_OR_EXPIRED"
    end

    local minBid = tonumber(auction.minimum_bid) or 0.00
    local highestBid = tonumber(auction.highest_bid) or 0.00

    if bidAmount < minBid then
        return false, "BID_BELOW_MINIMUM"
    end

    if bidAmount <= highestBid then
        return false, "BID_NOT_HIGHER_THAN_CURRENT"
    end

    -- Verify bidder liquidity
    local bidderPlayer = exports['nyx_core']:GetPlayerByCitizenId(citizenId)
    if not bidderPlayer then
        return false, "BIDDER_NOT_FOUND"
    end

    local bankBal = bidderPlayer:getWallet("bank") or 0
    if bankBal < bidAmount then
        return false, "INSUFFICIENT_FUNDS"
    end

    -- Debit new bidder (Escrowed)
    bidderPlayer:removeMoney("bank", bidAmount, string.format("Ingatlan Árverési Letét: Aukció #%d", auctionId))

    -- Refund previous highest bidder if one exists (Closed-Loop Escrow Conservation)
    if auction.highest_bidder_citizen_id and highestBid > 0.00 then
        local prevBidderId = auction.highest_bidder_citizen_id
        local prevPlayer = exports['nyx_core']:GetPlayerByCitizenId(prevBidderId)
        if prevPlayer then
            prevPlayer:addMoney("bank", highestBid, string.format("Visszatérítés (Túllicitált aukció #%d)", auctionId))
            TriggerClientEvent("nyx:ui:notify", prevPlayer.source, {
                type = "info",
                title = "AUKCIÓS VISSZATÉRÍTÉS",
                message = string.format("Túllicitáltak a(z) #%d árverésen! $%.2f letét visszatérítve.", auctionId, highestBid)
            })
        else
            -- Offline refund via database
            MySQL.query.await([[
                UPDATE `nyx_characters`
                SET `wallets` = JSON_SET(`wallets`, '$.bank', JSON_EXTRACT(`wallets`, '$.bank') + ?)
                WHERE `citizen_id` = ?
            ]], { highestBid, prevBidderId })
        end
    end

    -- Update auction record
    MySQL.prepare([[
        UPDATE `nyx_property_auctions`
        SET `highest_bid` = ?, `highest_bidder_citizen_id` = ?
        WHERE `auction_id` = ?
    ]], { bidAmount, citizenId, auctionId })

    local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[auction.property_id]
    local propLabel = prop and prop.label or string.format("Property #%d", auction.property_id)

    MySQL.prepare([[
        INSERT INTO `nyx_property_audit`
        (`property_id`, `action`, `actor_citizen_id`, `amount`, `notes`)
        VALUES (?, 'LOCK_TOGGLE', ?, ?, ?)
    ]], {
        auction.property_id,
        citizenId,
        bidAmount,
        string.format("New highest bid of $%.2f placed on auction #%d by %s", bidAmount, auctionId, citizenId)
    })

    return true, {
        auctionId = auctionId,
        bidAmount = bidAmount,
        propertyLabel = propLabel
    }
end

-- 3. Settle Expired Auction
function Nyx.Properties.SettleAuction(auctionId)
    auctionId = tonumber(auctionId)
    local auction = MySQL.single.await([[
        SELECT * FROM `nyx_property_auctions`
        WHERE `auction_id` = ? AND `auction_status` = 'active'
    ]], { auctionId })

    if not auction then return false, "AUCTION_NOT_FOUND" end

    local propertyId = auction.property_id
    local prop = Nyx.Properties.Loaded and Nyx.Properties.Loaded[propertyId]
    local highestBid = tonumber(auction.highest_bid) or 0.00
    local winnerCitizenId = auction.highest_bidder_citizen_id

    if winnerCitizenId and highestBid > 0.00 then
        -- 3.1 Winner transfer deed
        local masterAcc = Config.Millage.TreasuryAccount or "gov:city:master"
        local txUuid = generateTxUuid()

        MySQL.transaction.await({
            -- Credit municipal treasury with auction proceeds
            {
                query = "UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?",
                values = { highestBid, masterAcc }
            },
            {
                query = [[
                    INSERT INTO `nyx_treasury_ledger`
                    (`transaction_uuid`, `debit_account`, `credit_account`, `amount`, `category`, `authorized_by`, `memo`)
                    VALUES (?, ?, ?, ?, 'property_auction_settlement', 'AUCTION_ENGINE', ?)
                ]],
                values = {
                    txUuid,
                    string.format("char:%s:bank", winnerCitizenId),
                    masterAcc,
                    highestBid,
                    string.format("Foreclosure auction settlement for property #%d", propertyId)
                }
            },
            -- Update property deed
            {
                query = [[
                    UPDATE `nyx_properties`
                    SET `owner_citizen_id` = ?,
                        `reclaimed_for_auction` = 0,
                        `delinquency_tier` = 0,
                        `delinquent_amount` = 0.00,
                        `consecutive_missed_cycles` = 0,
                        `maintenance_condition` = 100.00,
                        `last_tax_billed_at` = NOW()
                    WHERE `property_id` = ?
                ]],
                values = { winnerCitizenId, propertyId }
            },
            -- Issue Tier 4 key to new owner
            {
                query = [[
                    INSERT INTO `nyx_property_keys` (`property_id`, `citizen_id`, `tier`, `label`)
                    VALUES (?, ?, 4, 'Tulajdonosi Mesterkártya (Árverés)')
                    ON DUPLICATE KEY UPDATE `tier` = 4
                ]],
                values = { propertyId, winnerCitizenId }
            },
            -- Finalize auction
            {
                query = [[
                    UPDATE `nyx_property_auctions`
                    SET `auction_status` = 'completed', `settled_at` = NOW()
                    WHERE `auction_id` = ?
                ]],
                values = { auctionId }
            }
        })

        if prop then
            prop.ownerCitizenId = winnerCitizenId
            prop.reclaimedForAuction = false
            prop.delinquencyTier = 0
            prop.delinquentAmount = 0.00
            prop.consecutiveMissedCycles = 0
            prop.maintenanceCondition = 100.00
        end

        local winnerPlayer = exports['nyx_core']:GetPlayerByCitizenId(winnerCitizenId)
        if winnerPlayer then
            TriggerClientEvent("nyx:ui:notify", winnerPlayer.source, {
                type = "success",
                title = "SIKERES ÁRVERÉS",
                message = string.format("Megnyerted a(z) %s ingatlant $%.2f összegért!",
                    prop and prop.label or "ingatlan", highestBid)
            })
        end

        print(string.format("^2[Nyx:Properties:Auction] Auction #%d settled! Transferred property #%d to citizen %s for $%.2f^7",
            auctionId, propertyId, winnerCitizenId, highestBid))

        return true, "COMPLETED", winnerCitizenId
    else
        -- 3.2 No bids: Property remains unowned on standard open market
        MySQL.transaction.await({
            {
                query = [[
                    UPDATE `nyx_properties`
                    SET `reclaimed_for_auction` = 0,
                        `delinquency_tier` = 0,
                        `delinquent_amount` = 0.00,
                        `consecutive_missed_cycles` = 0
                    WHERE `property_id` = ?
                ]],
                values = { propertyId }
            },
            {
                query = [[
                    UPDATE `nyx_property_auctions`
                    SET `auction_status` = 'cancelled', `settled_at` = NOW()
                    WHERE `auction_id` = ?
                ]],
                values = { auctionId }
            }
        })

        if prop then
            prop.reclaimedForAuction = false
            prop.delinquencyTier = 0
            prop.delinquentAmount = 0.00
            prop.consecutiveMissedCycles = 0
        end

        print(string.format("^3[Nyx:Properties:Auction] Auction #%d concluded with zero bids. Restored property #%d to standard catalog.^7",
            auctionId, propertyId))

        return true, "NO_BIDS_CANCELLED", nil
    end
end

-- 4. Periodic Sweeper for Expired Auctions (Checks every 60 seconds)
CreateThread(function()
    while true do
        Wait(60000)
        local expired = MySQL.query.await([[
            SELECT `auction_id` FROM `nyx_property_auctions`
            WHERE `auction_status` = 'active' AND `ends_at` <= NOW()
        ]])

        if expired and #expired > 0 then
            for _, r in ipairs(expired) do
                Nyx.Properties.SettleAuction(r.auction_id)
            end
        end
    end
end)

-- 5. RPC: Query Active Public Auctions
exports['nyx_core']:RegisterRPC("properties:getActiveAuctions", function(src)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local rows = MySQL.query.await([[
        SELECT a.*, p.`label` as `property_label`, p.`property_code`, p.`price` as `property_price`,
               p.`land_area_sqm`, p.`type` as `property_type`, p.`zone_id`
        FROM `nyx_property_auctions` a
        JOIN `nyx_properties` p ON a.`property_id` = p.`property_id`
        WHERE a.`auction_status` = 'active' AND a.`ends_at` > NOW()
        ORDER BY a.`ends_at` ASC
    ]])

    return { success = true, auctions = rows or {} }
end)

-- 6. RPC: Place Bid on Auction
exports['nyx_core']:RegisterRPC("properties:bidAuction", function(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    local auctionId = payload and payload.auctionId
    local bidAmount = payload and payload.bidAmount

    return Nyx.Properties.PlaceAuctionBid(player.citizenId, auctionId, bidAmount)
end)
