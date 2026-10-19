--[[
    Nyxframework: nyx_press
    File: server/subscriptions.lua
    Description: Authoritative server subscription billing, delivery routing,
                 whistleblower bounty escrow management, and anonymous claim verification.
]]

Nyx = Nyx or {}
Nyx.Press = Nyx.Press or {}
Nyx.Press.Subscriptions = Nyx.Press.Subscriptions or {}
Nyx.Press.PlansCache = {}

local Sub = Nyx.Press.Subscriptions

-- ----------------------------------------------------------------------------
-- 1. Hydrate Subscription Plans Cache
-- ----------------------------------------------------------------------------
function Nyx.Press.HydratePlans()
    local plans = MySQL.query.await("SELECT * FROM `nyx_press_subscription_plans` WHERE `is_active` = 1")
    if plans then
        for _, p in ipairs(plans) do
            Nyx.Press.PlansCache[p.plan_id] = {
                planId = p.plan_id,
                outletId = p.outlet_id,
                name = p.name,
                planType = p.plan_type,
                billingPeriodSec = tonumber(p.billing_period_sec) or 604800,
                price = tonumber(p.price) or 25.00,
                publisherShareRatio = tonumber(p.publisher_share_ratio) or 0.7500,
                whistleblowerPoolRatio = tonumber(p.whistleblower_pool_ratio) or 0.1500,
                municipalTaxRatio = tonumber(p.municipal_tax_ratio) or 0.1000,
                isActive = (tonumber(p.is_active) == 1)
            }
        end
    end
    print(string.format("^2[Nyx:Press] Hydrated %d active press subscription plans.^7", plans and #plans or 0))
end

-- ----------------------------------------------------------------------------
-- 2. Subscribe Citizen / Faction to a Media Plan
-- ----------------------------------------------------------------------------
function Nyx.Press.Subscribe(src, planId, deliveryPropertyId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    if not planId or not Nyx.Press.PlansCache[planId] then
        return { success = false, error = "PLAN_NOT_FOUND" }
    end

    local plan = Nyx.Press.PlansCache[planId]
    local citizenId = player.citizenId

    -- Check if active subscription already exists for this outlet
    local existing = MySQL.single.await([[
        SELECT * FROM `nyx_press_subscriptions`
        WHERE `citizen_id` = ? AND `outlet_id` = ? AND `status` = 'active'
    ]], { citizenId, plan.outletId })

    if existing then
        return { success = false, error = "ALREADY_SUBSCRIBED_TO_OUTLET", subscriptionId = existing.subscription_id }
    end

    -- Calculate closed-loop double-entry revenue splits
    local pubShare, poolShare, taxShare, totalCost = Sub.CalculateSubscriptionSplit(
        plan.price,
        plan.publisherShareRatio,
        plan.whistleblowerPoolRatio,
        plan.municipalTaxRatio
    )

    local buyerAcc = "char:" .. citizenId .. ":bank"
    local bal = exports['nyx_treasury']:GetAccountBalance(buyerAcc) or 0.0

    if bal < totalCost then
        return { success = false, error = "INSUFFICIENT_FUNDS", required = totalCost, balance = bal }
    end

    local pubAcc = "faction:" .. plan.outletId
    local poolAcc = "pool:whistleblower:" .. plan.outletId
    local muniAcc = "gov:city:master"

    -- Leg 1: Transfer publisher share
    local okPub, txPub = exports['nyx_treasury']:ExecuteTransfer(
        buyerAcc,
        pubAcc,
        pubShare,
        "press_subscription",
        "sub:" .. planId,
        string.format("Press Subscription: %s (Publisher Share)", plan.name),
        0.0
    )

    -- Leg 2: Transfer whistleblower bounty escrow pool share
    local okPool, txPool = exports['nyx_treasury']:ExecuteTransfer(
        buyerAcc,
        poolAcc,
        poolShare,
        "press_whistleblower_escrow",
        "sub:" .. planId,
        string.format("Press Subscription: %s (Whistleblower Escrow Pool)", plan.name),
        0.0
    )

    -- Leg 3: Transfer municipal sales tax share
    local okTax, txTax = exports['nyx_treasury']:ExecuteTransfer(
        buyerAcc,
        muniAcc,
        taxShare,
        "press_subscription_tax",
        "sub:" .. planId,
        string.format("Municipal Press Subscription Tax: %s", plan.name),
        0.0
    )

    if not okPub or not okPool or not okTax then
        return { success = false, error = "TREASURY_SETTLEMENT_FAILED" }
    end

    local subUuid = Nyx.RPC.GenerateNonce()
    local subId = string.format("sub_%s_%s", plan.outletId:gsub("press:", ""):sub(1, 8), subUuid:sub(1, 8))
    local logUuid = Nyx.RPC.GenerateNonce()

    -- Insert into subscriptions table
    local inserted = MySQL.insert.await([[
        INSERT INTO `nyx_press_subscriptions`
            (`subscription_id`, `citizen_id`, `outlet_id`, `plan_id`, `delivery_property_id`,
             `status`, `auto_renew`, `current_period_start`, `current_period_end`, `last_billed_at`)
        VALUES (?, ?, ?, ?, ?, 'active', 1, CURRENT_TIMESTAMP, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND), CURRENT_TIMESTAMP)
    ]], {
        subId,
        citizenId,
        plan.outletId,
        planId,
        deliveryPropertyId or nil,
        plan.billingPeriodSec
    })

    if not inserted then
        return { success = false, error = "DATABASE_INSERTION_FAILED" }
    end

    -- Insert billing audit log
    MySQL.insert.await([[
        INSERT INTO `nyx_press_subscription_billing_logs`
            (`log_uuid`, `subscription_id`, `citizen_id`, `outlet_id`, `amount`,
             `publisher_share`, `whistleblower_escrow_share`, `municipal_tax_share`,
             `treasury_tx_id`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'success')
    ]], {
        logUuid,
        subId,
        citizenId,
        plan.outletId,
        totalCost,
        pubShare,
        poolShare,
        taxShare,
        txPub or txPool
    })

    print(string.format("^2[Nyx:Press] Citizen %s subscribed to '%s' [$%.2f] (Pub: $%.2f, Escrow: $%.2f, Tax: $%.2f)^7",
        citizenId, plan.name, totalCost, pubShare, poolShare, taxShare))

    return {
        success = true,
        subscriptionId = subId,
        planName = plan.name,
        price = totalCost,
        outletId = plan.outletId,
        planType = plan.planType,
        deliveryPropertyId = deliveryPropertyId
    }
end

-- ----------------------------------------------------------------------------
-- 3. Cancel Subscription Auto-Renew
-- ----------------------------------------------------------------------------
function Nyx.Press.CancelSubscription(src, subscriptionId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    local sub = MySQL.single.await([[
        SELECT * FROM `nyx_press_subscriptions` WHERE `subscription_id` = ?
    ]], { subscriptionId })

    if not sub then
        return { success = false, error = "SUBSCRIPTION_NOT_FOUND" }
    end

    if sub.citizen_id ~= player.citizenId and not (player.hasPermission and player.hasPermission("admin")) then
        return { success = false, error = "UNAUTHORIZED" }
    end

    MySQL.prepare.await([[
        UPDATE `nyx_press_subscriptions`
        SET `auto_renew` = 0,
            `status` = 'cancelled'
        WHERE `subscription_id` = ?
    ]], { subscriptionId })

    print(string.format("^3[Nyx:Press] Subscription %s cancelled by %s.^7", subscriptionId, player.citizenId))

    return {
        success = true,
        subscriptionId = subscriptionId,
        status = "cancelled",
        message = "Előfizetés sikeresen lemondva. A jelenlegi kifizetett időszak végéig aktív marad."
    }
end

-- ----------------------------------------------------------------------------
-- 4. Get Citizen Subscriptions
-- ----------------------------------------------------------------------------
function Nyx.Press.GetCitizenSubscriptions(citizenId)
    if not citizenId then return {} end

    local rows = MySQL.query.await([[
        SELECT s.*, p.`name` AS `plan_name`, p.`plan_type`, p.`price`, p.`billing_period_sec`
        FROM `nyx_press_subscriptions` s
        JOIN `nyx_press_subscription_plans` p ON s.`plan_id` = p.`plan_id`
        WHERE s.`citizen_id` = ?
        ORDER BY s.`created_at` DESC
    ]], { citizenId })

    return rows or {}
end

-- ----------------------------------------------------------------------------
-- 5. Award Whistleblower Bounty from Escrow Pool
-- ----------------------------------------------------------------------------
function Nyx.Press.AwardWhistleblowerBounty(src, leakId, amount)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    local isAccredited, accErr = Nyx.Press.CheckPlayerAccreditation(player.citizenId, nil)
    if not isAccredited then
        return { success = false, error = "PRESS_ACCREDITATION_REQUIRED", detail = accErr }
    end

    local leak = MySQL.single.await([[
        SELECT * FROM `nyx_press_leaks` WHERE `leak_id` = ?
    ]], { leakId })

    if not leak then
        return { success = false, error = "LEAK_NOT_FOUND" }
    end

    -- Determine awarding outlet
    local outletId = leak.target_outlet_id or "press:underground_post"
    local poolAcc = "pool:whistleblower:" .. outletId
    local escrowBal = exports['nyx_treasury']:GetAccountBalance(poolAcc) or 0.0

    local bountyAmt = tonumber(amount) or 0.0
    local isValid, errVal = Sub.ValidateBountyAward(bountyAmt, escrowBal, leak.status)
    if not isValid then
        return { success = false, error = errVal, escrowBalance = escrowBal }
    end

    -- Check if bounty already awarded for this leak
    local existingBounty = MySQL.single.await([[
        SELECT * FROM `nyx_press_whistleblower_bounties` WHERE `leak_id` = ?
    ]], { leakId })

    if existingBounty then
        return { success = false, error = "BOUNTY_ALREADY_AWARDED_FOR_LEAK", bountyId = existingBounty.bounty_id }
    end

    local bountyUuid = Nyx.RPC.GenerateNonce()
    local bountyId = string.format("bounty_%s", bountyUuid:sub(1, 10))

    local ok = MySQL.insert.await([[
        INSERT INTO `nyx_press_whistleblower_bounties`
            (`bounty_id`, `leak_id`, `outlet_id`, `awarded_by_journalist_id`,
             `source_hash`, `bounty_amount`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, 'escrowed')
    ]], {
        bountyId,
        leakId,
        outletId,
        player.citizenId,
        leak.source_hash,
        bountyAmt
    })

    if not ok then
        return { success = false, error = "DATABASE_INSERTION_FAILED" }
    end

    print(string.format("^2[Nyx:Press] Bounty of $%.2f awarded for leak %s [%s] from %s escrow by %s.^7",
        bountyAmt, leakId, bountyId, outletId, player.citizenId))

    -- Broadcast to dropboxes
    TriggerClientEvent("nyx:press:client:bountyAvailable", -1, {
        bountyId = bountyId,
        outletId = outletId,
        amount = bountyAmt,
        leakTitle = leak.title
    })

    return {
        success = true,
        bountyId = bountyId,
        leakId = leakId,
        amount = bountyAmt,
        sourceHash = leak.source_hash,
        outletId = outletId
    }
end

-- ----------------------------------------------------------------------------
-- 6. Claim Whistleblower Bounty at Dropbox with Cryptographic Proof
-- ----------------------------------------------------------------------------
function Nyx.Press.ClaimWhistleblowerBounty(src, bountyId, salt, nonce, dropboxId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    if not bountyId or not salt or not nonce then
        return { success = false, error = "INVALID_PROOF_PARAMETERS" }
    end

    local bounty = MySQL.single.await([[
        SELECT * FROM `nyx_press_whistleblower_bounties` WHERE `bounty_id` = ?
    ]], { bountyId })

    if not bounty then
        return { success = false, error = "BOUNTY_NOT_FOUND" }
    end

    if tonumber(bounty.is_claimed) == 1 or bounty.status ~= "escrowed" then
        return { success = false, error = "BOUNTY_ALREADY_CLAIMED_OR_RESOLVED", currentStatus = bounty.status }
    end

    -- Verify cryptographic proof-of-whistleblower source identity
    local isVerified = Sub.VerifyBountyClaim(bounty.source_hash, player.citizenId, salt, nonce)
    if not isVerified then
        return { success = false, error = "CRYPTOGRAPHIC_PROOF_VERIFICATION_FAILED" }
    end

    -- Execute double-entry transfer from whistleblower escrow pool directly to whistleblower
    local poolAcc = "pool:whistleblower:" .. bounty.outlet_id
    local recipientAcc = "char:" .. player.citizenId .. ":bank"
    local amt = tonumber(bounty.bounty_amount) or 0.0

    local okTx, txId = exports['nyx_treasury']:ExecuteTransfer(
        poolAcc,
        recipientAcc,
        amt,
        "whistleblower_bounty_payout",
        "bounty:" .. bountyId,
        string.format("Whistleblower Investigative Bounty Claim: %s", bountyId),
        0.0
    )

    if not okTx then
        return { success = false, error = "ESCROW_PAYOUT_TRANSFER_FAILED" }
    end

    -- Mark bounty claimed in database
    MySQL.prepare.await([[
        UPDATE `nyx_press_whistleblower_bounties`
        SET `is_claimed` = 1,
            `claimed_at` = CURRENT_TIMESTAMP,
            `claimed_dropbox_id` = ?,
            `claim_tx_id` = ?,
            `status` = 'claimed'
        WHERE `bounty_id` = ?
    ]], { dropboxId or "drop_metro_subway", txId, bountyId })

    print(string.format("^2[Nyx:Press] ANONYMOUS BOUNTY CLAIMED: $%.2f disbursed to verified source for bounty %s at %s.^7",
        amt, bountyId, dropboxId or "drop_metro_subway"))

    return {
        success = true,
        bountyId = bountyId,
        amount = amt,
        txId = txId,
        message = string.format("Kiszivárogtatói jutalék sikeresen felvéve! $%.2f átutalva a bankszámládra.", amt)
    }
end

-- ----------------------------------------------------------------------------
-- 7. Deliver Publication to Active Subscribers
-- ----------------------------------------------------------------------------
function Nyx.Press.DeliverPublicationToSubscribers(pubId)
    if not pubId then return end

    local pub = MySQL.single.await([[
        SELECT * FROM `nyx_press_publications` WHERE `publication_id` = ?
    ]], { pubId })

    if not pub then return end

    -- Query active subscribers for this outlet
    local subscribers = MySQL.query.await([[
        SELECT s.*, p.`plan_type`
        FROM `nyx_press_subscriptions` s
        JOIN `nyx_press_subscription_plans` p ON s.`plan_id` = p.`plan_id`
        WHERE s.`outlet_id` = ?
          AND s.`status` IN ('active', 'cancelled')
          AND s.`current_period_end` > CURRENT_TIMESTAMP
    ]], { pub.outlet_id })

    if not subscribers or #subscribers == 0 then return end

    for _, sub in ipairs(subscribers) do
        -- 1. Digital Dispatch
        if sub.plan_type == "digital" or sub.plan_type == "syndication" then
            local targetPlayer = exports['nyx_core']:GetPlayerByCitizenId(sub.citizen_id)
            if targetPlayer and targetPlayer.source then
                TriggerClientEvent("nyx:press:client:newPublicationAvailable", targetPlayer.source, {
                    pubId = pub.publication_id,
                    headline = pub.headline,
                    outletId = pub.outlet_id,
                    byline = pub.author_byline,
                    price = 0.00,
                    isSubscriberDelivery = true
                })
            end
        end

        -- 2. Physical Print Delivery to Property Stash
        if sub.plan_type == "print_delivery" and sub.delivery_property_id then
            local stashId = "property:" .. sub.delivery_property_id .. ":stash"
            if exports['nyx_inventory'] and exports['nyx_inventory'].AddItem then
                pcall(function()
                    exports['nyx_inventory']:AddItem(stashId, "press_newspaper", 1, {
                        publicationId = pub.publication_id,
                        headline = pub.headline,
                        byline = pub.author_byline,
                        outlet = pub.outlet_id,
                        edition = pub.edition_number,
                        isHomeDelivery = true
                    })
                end)
            end
        end
    end

    print(string.format("^2[Nyx:Press] Delivered publication '%s' to %d active subscribers.^7",
        pub.headline, #subscribers))
end

-- ----------------------------------------------------------------------------
-- 8. Recurring Subscription Billing Tick (Runs every 60 seconds)
-- ----------------------------------------------------------------------------
function Nyx.Press.ProcessRecurringBillingTick()
    local dueSubs = MySQL.query.await([[
        SELECT s.*, p.`price`, p.`billing_period_sec`, p.`publisher_share_ratio`,
               p.`whistleblower_pool_ratio`, p.`municipal_tax_ratio`, p.`name` AS `plan_name`
        FROM `nyx_press_subscriptions` s
        JOIN `nyx_press_subscription_plans` p ON s.`plan_id` = p.`plan_id`
        WHERE s.`status` = 'active'
          AND s.`auto_renew` = 1
          AND s.`current_period_end` <= CURRENT_TIMESTAMP
        LIMIT 50
    ]])

    if not dueSubs or #dueSubs == 0 then return end

    for _, sub in ipairs(dueSubs) do
        local citizenId = sub.citizen_id
        local buyerAcc = "char:" .. citizenId .. ":bank"
        local bal = exports['nyx_treasury']:GetAccountBalance(buyerAcc) or 0.0
        local price = tonumber(sub.price) or 25.00

        local pubShare, poolShare, taxShare = Sub.CalculateSubscriptionSplit(
            price,
            sub.publisher_share_ratio,
            sub.whistleblower_pool_ratio,
            sub.municipal_tax_ratio
        )

        if bal >= price then
            local pubAcc = "faction:" .. sub.outlet_id
            local poolAcc = "pool:whistleblower:" .. sub.outlet_id
            local muniAcc = "gov:city:master"

            local okPub, txPub = exports['nyx_treasury']:ExecuteTransfer(
                buyerAcc, pubAcc, pubShare, "press_subscription_renewal",
                "sub:" .. sub.subscription_id, string.format("Press Renewal: %s", sub.plan_name), 0.0
            )
            local okPool = exports['nyx_treasury']:ExecuteTransfer(
                buyerAcc, poolAcc, poolShare, "press_whistleblower_escrow",
                "sub:" .. sub.subscription_id, "Whistleblower Escrow Split", 0.0
            )
            local okTax = exports['nyx_treasury']:ExecuteTransfer(
                buyerAcc, muniAcc, taxShare, "press_subscription_tax",
                "sub:" .. sub.subscription_id, "Municipal Press Tax", 0.0
            )

            if okPub and okPool and okTax then
                -- Extend period
                MySQL.prepare.await([[
                    UPDATE `nyx_press_subscriptions`
                    SET `current_period_start` = CURRENT_TIMESTAMP,
                        `current_period_end` = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND),
                        `last_billed_at` = CURRENT_TIMESTAMP,
                        `consecutive_failures` = 0,
                        `status` = 'active'
                    WHERE `subscription_id` = ?
                ]], { sub.billing_period_sec, sub.subscription_id })

                local logUuid = Nyx.RPC.GenerateNonce()
                MySQL.insert.await([[
                    INSERT INTO `nyx_press_subscription_billing_logs`
                        (`log_uuid`, `subscription_id`, `citizen_id`, `outlet_id`, `amount`,
                         `publisher_share`, `whistleblower_escrow_share`, `municipal_tax_share`,
                         `treasury_tx_id`, `status`)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'success')
                ]], { logUuid, sub.subscription_id, citizenId, sub.outlet_id, price, pubShare, poolShare, taxShare, txPub })
            end
        else
            -- Insufficient funds: increment failure and handle delinquency
            local newFailures = (tonumber(sub.consecutive_failures) or 0) + 1
            local newStatus = (newFailures >= 3) and "expired" or "past_due"

            MySQL.prepare.await([[
                UPDATE `nyx_press_subscriptions`
                SET `consecutive_failures` = ?,
                    `status` = ?
                WHERE `subscription_id` = ?
            ]], { newFailures, newStatus, sub.subscription_id })

            local logUuid = Nyx.RPC.GenerateNonce()
            MySQL.insert.await([[
                INSERT INTO `nyx_press_subscription_billing_logs`
                    (`log_uuid`, `subscription_id`, `citizen_id`, `outlet_id`, `amount`,
                     `publisher_share`, `whistleblower_escrow_share`, `municipal_tax_share`,
                     `status`)
                VALUES (?, ?, ?, ?, ?, 0.0, 0.0, 0.0, 'failed_insufficient_funds')
            ]], { logUuid, sub.subscription_id, citizenId, sub.outlet_id, price })

            print(string.format("^3[Nyx:Press] Renewal failed for sub %s (Citizen: %s). Consecutive failures: %d (Status: %s)^7",
                sub.subscription_id, citizenId, newFailures, newStatus))
        end
    end
end

-- Background Billing Sweeper Thread (every 60 seconds)
CreateThread(function()
    Wait(10000) -- Initial warmup
    while true do
        Wait(60000)
        pcall(Nyx.Press.ProcessRecurringBillingTick)
    end
end)

-- ----------------------------------------------------------------------------
-- 9. RPC Endpoints for Subscriptions & Whistleblower Bounties
-- ----------------------------------------------------------------------------

Nyx.RPC.Register("press:getSubscriptionPlans", function(src, outletId)
    local query = "SELECT * FROM `nyx_press_subscription_plans` WHERE `is_active` = 1"
    local params = {}
    if outletId then
        query = query .. " AND `outlet_id` = ?"
        params[#params + 1] = outletId
    end
    return MySQL.query.await(query, params) or {}
end)

Nyx.RPC.Register("press:getMySubscriptions", function(src)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return {} end
    return Nyx.Press.GetCitizenSubscriptions(player.citizenId)
end)

Nyx.RPC.Register("press:subscribe", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end
    return Nyx.Press.Subscribe(src, payload.planId, payload.deliveryPropertyId)
end)

Nyx.RPC.Register("press:cancelSubscription", function(src, subscriptionId)
    return Nyx.Press.CancelSubscription(src, subscriptionId)
end)

Nyx.RPC.Register("press:awardBounty", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end
    return Nyx.Press.AwardWhistleblowerBounty(src, payload.leakId, payload.amount)
end)

Nyx.RPC.Register("press:claimBounty", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end
    return Nyx.Press.ClaimWhistleblowerBounty(src, payload.bountyId, payload.salt, payload.nonce, payload.dropboxId)
end)

Nyx.RPC.Register("press:getBountyPoolBalance", function(src, outletId)
    if not outletId then return 0.0 end
    local poolAcc = "pool:whistleblower:" .. outletId
    return exports['nyx_treasury']:GetAccountBalance(poolAcc) or 0.0
end)

Nyx.RPC.Register("press:getAvailableBounties", function(src)
    return MySQL.query.await([[
        SELECT b.`bounty_id`, b.`outlet_id`, b.`bounty_amount`, b.`status`, b.`awarded_at`,
               l.`title` AS `leak_title`, l.`leak_category`
        FROM `nyx_press_whistleblower_bounties` b
        JOIN `nyx_press_leaks` l ON b.`leak_id` = l.`leak_id`
        WHERE b.`status` = 'escrowed' AND b.`is_claimed` = 0
        ORDER BY b.`awarded_at` DESC
        LIMIT 20
    ]]) or {}
end)

-- Hook into Nyx.Press.HydrateWorldData
MySQL.ready(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end
    while not (exports['nyx_core'] and exports['nyx_core'].IsDatabaseReady and exports['nyx_core']:IsDatabaseReady()) do
        Wait(50)
    end
    Nyx.Press.HydratePlans()
end)
