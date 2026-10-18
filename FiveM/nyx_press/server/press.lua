--[[
    Nyxframework: nyx_press
    File: server/press.lua
    Description: Authoritative media publishing engine, double-entry circulation printing,
                 encrypted whistleblower dead-drops, and public newsstand distribution.
]]

Nyx = Nyx or {}
Nyx.Press = Nyx.Press or {}

-- 1. Helper: Check Player Media Accreditation
function Nyx.Press.CheckPlayerAccreditation(citizenId, outletId)
    if not citizenId then return false, "UNAUTHENTICATED" end

    -- Check Trade Union Membership (Press Guild)
    local unionMember = MySQL.single.await([[
        SELECT `union_id`, `role`, `standing`
        FROM `nyx_factions_union_members`
        WHERE `citizen_id` = ? AND `union_id` = ?
    ]], { citizenId, Config.Accreditation.RequiredUnionId or "union:press_guild" })

    -- Check Media Faction Charter Leadership
    local factionMember = nil
    if outletId and Nyx.Press.OutletsCache[outletId] then
        local targetFactionId = Nyx.Press.OutletsCache[outletId].factionId
        if targetFactionId then
            factionMember = MySQL.single.await([[
                SELECT `faction_id`, `role_title`
                FROM `nyx_factions_members`
                WHERE `citizen_id` = ? AND `faction_id` = ?
            ]], { citizenId, targetFactionId })
        end
    end

    local uTable = unionMember and {
        unionId = unionMember.union_id,
        role = unionMember.role,
        standing = unionMember.standing
    } or nil

    local fTable = factionMember and {
        factionId = factionMember.faction_id,
        roleTitle = factionMember.role_title,
        isLeader = (factionMember.role_title == "CEO" or factionMember.role_title == "Editor-in-Chief")
    } or nil

    local isAccredited, reason = Nyx.Press.EvaluateMediaAccreditation(uTable, fTable)
    return isAccredited, reason
end

-- 2. Publish New Article / Issue
function Nyx.Press.PublishArticle(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    if type(payload) ~= "table" then
        return { success = false, error = "INVALID_PAYLOAD" }
    end

    local isValid, valErr = Nyx.Press.ValidateArticle(payload)
    if not isValid then
        return { success = false, error = valErr }
    end

    local outletId = payload.outletId or "press:underground_post"
    local isAccredited, accErr = Nyx.Press.CheckPlayerAccreditation(player.citizenId, outletId)

    -- If unaccredited and trying to publish under official press outlet, reject
    if not isAccredited and outletId ~= "press:underground_post" then
        return { success = false, error = "PRESS_ACCREDITATION_REQUIRED", detail = accErr }
    end

    local pubUuid = Nyx.RPC.GenerateNonce()
    local pubId = string.format("pub_%s_%s", outletId:gsub("press:", ""):sub(1, 12), pubUuid:sub(1, 8))
    local price = math.max(Config.Newsstand.MinCoverPrice,
        math.min(Config.Newsstand.MaxCoverPrice, tonumber(payload.pricePerCopy) or 10.00))

    local inserted = MySQL.insert.await([[
        INSERT INTO `nyx_press_publications`
            (`publication_id`, `outlet_id`, `headline`, `subheading`, `author_citizen_id`,
             `author_byline`, `category`, `content`, `edition_number`, `price_per_copy`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        pubId,
        outletId,
        payload.headline,
        payload.subheading or "",
        player.citizenId,
        payload.authorByline,
        payload.category or "general",
        payload.content,
        tonumber(payload.editionNumber) or 1,
        price
    })

    if not inserted then
        return { success = false, error = "DATABASE_INSERTION_FAILED" }
    end

    print(string.format("^2[Nyx:Press] New article published '%s' [%s] by %s (Outlet: %s)^7",
        payload.headline, pubId, payload.authorByline, outletId))

    TriggerClientEvent("nyx:press:client:newPublicationAvailable", -1, {
        pubId = pubId,
        headline = payload.headline,
        outletId = outletId,
        byline = payload.authorByline,
        price = price
    })

    -- Dispatch subscriber delivery (digital alerts & property stash print deposits)
    if Nyx.Press.DeliverPublicationToSubscribers then
        pcall(Nyx.Press.DeliverPublicationToSubscribers, pubId)
    end

    return {
        success = true,
        publicationId = pubId,
        headline = payload.headline,
        pricePerCopy = price
    }
end

-- 3. Print Circulation Copies (Deducts Utility Supplies via Double-Entry Treasury)
function Nyx.Press.PrintCirculationCopies(src, pubId, copies, targetStandId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    local nCopies = math.floor(tonumber(copies) or 0)
    if nCopies < (Config.Printing.MinCirculation or 10) or nCopies > (Config.Printing.MaxCirculation or 2000) then
        return { success = false, error = "INVALID_CIRCULATION_COUNT" }
    end

    local pub = MySQL.single.await([[
        SELECT * FROM `nyx_press_publications` WHERE `publication_id` = ?
    ]], { pubId })

    if not pub then
        return { success = false, error = "PUBLICATION_NOT_FOUND" }
    end

    if tonumber(pub.is_retracted) == 1 then
        return { success = false, error = "PUBLICATION_RETRACTED_CANNOT_PRINT" }
    end

    local isAccredited, accErr = Nyx.Press.CheckPlayerAccreditation(player.citizenId, pub.outlet_id)
    if not isAccredited and pub.outlet_id ~= "press:underground_post" then
        return { success = false, error = "PRESS_ACCREDITATION_REQUIRED", detail = accErr }
    end

    -- Calculate total printing cost
    local totalCost, unitCost, tier = Nyx.Press.CalculatePrintingCost(
        nCopies,
        #pub.content,
        Config.Printing.BaseCostPerCopy,
        Config.Printing.PageFactor,
        Config.Printing.MachineOverhead
    )

    -- Resolve payer account
    local payerAcc = "char:" .. player.citizenId .. ":bank"
    local outlet = Nyx.Press.OutletsCache[pub.outlet_id]
    if outlet and outlet.factionId then
        payerAcc = "faction:" .. outlet.factionId
    end

    local supplyAcc = Config.Printing.SupplyAccount or "gov:dept:works"
    local payerBal = exports['nyx_treasury']:GetAccountBalance(payerAcc) or 0.0

    if payerBal < totalCost then
        -- Fall back to citizen bank if corporate account insufficient
        payerAcc = "char:" .. player.citizenId .. ":bank"
        payerBal = exports['nyx_treasury']:GetAccountBalance(payerAcc) or 0.0
        if payerBal < totalCost then
            return { success = false, error = "INSUFFICIENT_FUNDS_FOR_PRINTING", required = totalCost, balance = payerBal }
        end
    end

    -- Execute closed-loop double-entry transfer to municipal public works (supplies)
    local okTransfer, txId = exports['nyx_treasury']:ExecuteTransfer(
        payerAcc,
        supplyAcc,
        totalCost,
        "printing_supplies",
        "press:" .. pubId,
        string.format("Print Run (%d copies) of %s", nCopies, pub.headline),
        0.0
    )

    if not okTransfer then
        return { success = false, error = "TREASURY_TRANSFER_FAILED" }
    end

    -- Update publication circulation
    MySQL.prepare.await([[
        UPDATE `nyx_press_publications`
        SET `circulation_count` = `circulation_count` + ?
        WHERE `publication_id` = ?
    ]], { nCopies, pubId })

    -- If target newsstand is specified, route stock to newsstand
    if targetStandId and Nyx.Press.NewsstandsCache[targetStandId] then
        MySQL.prepare.await([[
            UPDATE `nyx_press_newsstands`
            SET `current_publication_id` = ?,
                `copies_inventory` = `copies_inventory` + ?
            WHERE `stand_id` = ?
        ]], { pubId, nCopies, targetStandId })

        local cachedStand = Nyx.Press.NewsstandsCache[targetStandId]
        cachedStand.currentPublicationId = pubId
        cachedStand.copiesInventory = cachedStand.copiesInventory + nCopies
    else
        -- Add physical items to player inventory
        if exports['nyx_inventory'] and exports['nyx_inventory'].AddItem then
            local invId = "char:" .. player.citizenId
            exports['nyx_inventory']:AddItem(invId, "press_newspaper", nCopies, {
                publicationId = pubId,
                headline = pub.headline,
                byline = pub.author_byline,
                outlet = pub.outlet_id,
                edition = pub.edition_number
            })
        end
    end

    print(string.format("^2[Nyx:Press] Printed %d copies of '%s' for $%.2f (Unit: $%.2f)^7",
        nCopies, pub.headline, totalCost, unitCost))

    return {
        success = true,
        publicationId = pubId,
        copiesPrinted = nCopies,
        totalCost = totalCost,
        unitCost = unitCost,
        txId = txId
    }
end

-- 4. Anonymous Whistleblower Leak Dead-Drop
function Nyx.Press.DepositWhistleblowerLeak(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    if type(payload) ~= "table" then
        return { success = false, error = "INVALID_PAYLOAD" }
    end

    local title = tostring(payload.title or "")
    if #title < 5 or #title > 255 then
        return { success = false, error = "INVALID_LEAK_TITLE" }
    end

    local cat = payload.category or "general_corruption"
    if not Config.Whistleblower.AllowedCategories[cat] then
        return { success = false, error = "INVALID_LEAK_CATEGORY" }
    end

    local content = tostring(payload.encryptedPayload or "")
    if #content < (Config.Whistleblower.MinPayloadLength or 20) then
        return { success = false, error = "PAYLOAD_TOO_SHORT" }
    end

    local dropboxId = payload.dropboxId or "drop_metro_subway"
    local leakUuid = Nyx.RPC.GenerateNonce()
    local leakId = string.format("leak_%s", leakUuid:sub(1, 12))

    -- Generate cryptographic zero-knowledge source hash with client/server salt
    local salt = Nyx.RPC.GenerateNonce():sub(1, 16)
    local nonce = Nyx.RPC.GenerateNonce():sub(1, 16)
    local sourceHash = Nyx.Press.GenerateSourceHash(player.citizenId, salt, nonce)

    local targetOutlet = payload.targetOutletId or nil
    local evidenceRef = payload.evidenceFingerprint or nil

    local ok = MySQL.insert.await([[
        INSERT INTO `nyx_press_leaks`
            (`leak_id`, `dropbox_id`, `target_outlet_id`, `title`, `leak_category`,
             `encrypted_payload`, `source_hash`, `evidence_fingerprint`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'unclaimed')
    ]], {
        leakId,
        dropboxId,
        targetOutlet,
        title,
        cat,
        content,
        sourceHash,
        evidenceRef
    })

    if not ok then
        return { success = false, error = "DATABASE_INSERTION_FAILED" }
    end

    print(string.format("^3[Nyx:Press] ANONYMOUS LEAK DEPOSITED: '%s' [%s] at dropbox %s (Source Hash: %s)^7",
        title, leakId, dropboxId, sourceHash:sub(1, 12) .. "..."))

    -- Notify accredited journalists
    TriggerClientEvent("nyx:press:client:newWhistleblowerLeak", -1, {
        leakId = leakId,
        title = title,
        category = cat,
        dropboxId = dropboxId,
        targetOutlet = targetOutlet
    })

    -- Return proof-of-whistleblower receipt for source
    return {
        success = true,
        leakId = leakId,
        sourceHash = sourceHash,
        salt = salt,
        nonce = nonce,
        message = "Encrypted whistleblower leak deposited successfully. Keep salt and nonce to prove source authenticity if required."
    }
end

-- 5. Query Whistleblower Leaks (Restricted to Accredited Journalists)
function Nyx.Press.GetAvailableLeaks(src)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return {} end

    local isAccredited, _ = Nyx.Press.CheckPlayerAccreditation(player.citizenId, nil)
    if not isAccredited then
        return {}
    end

    local rows = MySQL.query.await([[
        SELECT `leak_id`, `dropbox_id`, `target_outlet_id`, `title`, `leak_category`,
               `encrypted_payload`, `source_hash`, `evidence_fingerprint`,
               `claimed_by_journalist_id`, `status`, `submitted_at`, `claimed_at`
        FROM `nyx_press_leaks`
        WHERE `status` IN ('unclaimed', 'under_investigation')
        ORDER BY `submitted_at` DESC
        LIMIT 50
    ]])

    return rows or {}
end

-- 6. Claim Whistleblower Leak for Investigation
function Nyx.Press.ClaimWhistleblowerLeak(src, leakId)
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

    if not Nyx.Press.CanTransitionLeak(leak.status, "under_investigation") then
        return { success = false, error = "LEAK_ALREADY_CLAIMED_OR_RESOLVED", currentStatus = leak.status }
    end

    MySQL.prepare.await([[
        UPDATE `nyx_press_leaks`
        SET `status` = 'under_investigation',
            `claimed_by_journalist_id` = ?,
            `claimed_at` = CURRENT_TIMESTAMP
        WHERE `leak_id` = ?
    ]], { player.citizenId, leakId })

    print(string.format("^2[Nyx:Press] Journalist %s claimed whistleblower leak '%s' for investigation.^7",
        player.citizenId, leakId))

    return {
        success = true,
        leakId = leakId,
        status = "under_investigation",
        claimedBy = player.citizenId
    }
end

-- 7. Purchase Newspaper from Public Newsstand
function Nyx.Press.PurchaseNewspaper(src, standId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    local stand = MySQL.single.await([[
        SELECT * FROM `nyx_press_newsstands` WHERE `stand_id` = ?
    ]], { standId })

    if not stand then
        return { success = false, error = "NEWSSTAND_NOT_FOUND" }
    end

    if not stand.current_publication_id then
        return { success = false, error = "NEWSSTAND_EMPTY_NO_EDITION" }
    end

    if (tonumber(stand.copies_inventory) or 0) <= 0 then
        return { success = false, error = "NEWSSTAND_OUT_OF_STOCK" }
    end

    local pub = MySQL.single.await([[
        SELECT * FROM `nyx_press_publications` WHERE `publication_id` = ?
    ]], { stand.current_publication_id })

    if not pub then
        return { success = false, error = "PUBLICATION_NOT_FOUND" }
    end

    if tonumber(pub.is_retracted) == 1 then
        return { success = false, error = "PUBLICATION_RETRACTED_BY_COURT_ORDER", reason = pub.retraction_reason }
    end

    local coverPrice = tonumber(pub.price_per_copy) or 10.00
    local pubShare, muniShare = Nyx.Press.CalculateSaleRevenueSplit(
        coverPrice,
        Config.Newsstand.PublisherSplit or 0.75
    )

    -- Debit player
    local buyerAcc = "char:" .. player.citizenId .. ":bank"
    local bal = exports['nyx_treasury']:GetAccountBalance(buyerAcc) or 0.0

    if bal < coverPrice then
        return { success = false, error = "INSUFFICIENT_FUNDS", required = coverPrice, balance = bal }
    end

    -- Destination accounts
    local pubAcc = "faction:" .. pub.outlet_id
    local muniAcc = Config.Newsstand.MunicipalAccount or "gov:city:master"

    -- Leg 1: Transfer publisher share
    local okPub = exports['nyx_treasury']:ExecuteTransfer(
        buyerAcc,
        pubAcc,
        pubShare,
        "newspaper_sale",
        "stand:" .. standId,
        string.format("Retail Newspaper Purchase: %s", pub.headline),
        0.0
    )

    -- Leg 2: Transfer municipal tax share
    local okMuni = exports['nyx_treasury']:ExecuteTransfer(
        buyerAcc,
        muniAcc,
        muniShare,
        "newspaper_tax",
        "stand:" .. standId,
        string.format("Municipal Newsstand Sales Tax: %s", pub.headline),
        0.0
    )

    if not okPub or not okMuni then
        return { success = false, error = "TREASURY_SETTLEMENT_FAILED" }
    end

    -- Update database inventory and copies sold
    MySQL.prepare.await([[
        UPDATE `nyx_press_newsstands`
        SET `copies_inventory` = `copies_inventory` - 1,
            `total_sold` = `total_sold` + 1
        WHERE `stand_id` = ?
    ]], { standId })

    MySQL.prepare.await([[
        UPDATE `nyx_press_publications`
        SET `copies_sold` = `copies_sold` + 1
        WHERE `publication_id` = ?
    ]], { pub.publication_id })

    -- Give physical newspaper to player
    if exports['nyx_inventory'] and exports['nyx_inventory'].AddItem then
        local invId = "char:" .. player.citizenId
        exports['nyx_inventory']:AddItem(invId, "press_newspaper", 1, {
            publicationId = pub.publication_id,
            headline = pub.headline,
            byline = pub.author_byline,
            outlet = pub.outlet_id,
            edition = pub.edition_number
        })
    end

    -- Update in-memory cache
    if Nyx.Press.NewsstandsCache[standId] then
        Nyx.Press.NewsstandsCache[standId].copiesInventory = Nyx.Press.NewsstandsCache[standId].copiesInventory - 1
        Nyx.Press.NewsstandsCache[standId].totalSold = Nyx.Press.NewsstandsCache[standId].totalSold + 1
    end

    return {
        success = true,
        publicationId = pub.publication_id,
        headline = pub.headline,
        coverPrice = coverPrice,
        copiesRemaining = (tonumber(stand.copies_inventory) or 1) - 1
    }
end

-- 8. Judicial Retraction & Defamation Injunction Order
function Nyx.Press.RetractPublication(src, pubId, reason)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    -- Check if user is a Judge via nyx_judiciary or admin
    local isJudge = false
    if exports['nyx_judiciary'] and exports['nyx_judiciary'].IsJudge then
        isJudge = exports['nyx_judiciary']:IsJudge(player.citizenId)
    end

    if not isJudge and not (player.hasPermission and player.hasPermission("admin")) then
        return { success = false, error = "JUDICIAL_AUTHORITY_REQUIRED" }
    end

    local pub = MySQL.single.await([[
        SELECT * FROM `nyx_press_publications` WHERE `publication_id` = ?
    ]], { pubId })

    if not pub then
        return { success = false, error = "PUBLICATION_NOT_FOUND" }
    end

    if not Nyx.Press.CanTransitionPublication("published", "retracted") then
        return { success = false, error = "INVALID_STATE_TRANSITION" }
    end

    local judicialReason = reason or "Court Injunction: Defamation & Misinformation Invalidation."

    MySQL.prepare.await([[
        UPDATE `nyx_press_publications`
        SET `is_retracted` = 1,
            `retraction_reason` = ?,
            `retracted_by_judge_id` = ?
        WHERE `publication_id` = ?
    ]], { judicialReason, player.citizenId, pubId })

    -- Clear from newsstands stocking this edition
    MySQL.prepare.await([[
        UPDATE `nyx_press_newsstands`
        SET `current_publication_id` = NULL,
            `copies_inventory` = 0
        WHERE `current_publication_id` = ?
    ]], { pubId })

    print(string.format("^1[Nyx:Press] JUDICIAL RETRACTION: Publication '%s' quashed by Judge %s. Reason: %s^7",
        pubId, player.citizenId, judicialReason))

    TriggerClientEvent("nyx:press:client:publicationRetracted", -1, {
        publicationId = pubId,
        headline = pub.headline,
        retractedBy = player.citizenId,
        reason = judicialReason
    })

    return {
        success = true,
        publicationId = pubId,
        isRetracted = true,
        reason = judicialReason
    }
end

-- ============================================================================
-- RPC Bridge Endpoints
-- ============================================================================

Nyx.RPC.Register("press:getOutlets", function(src)
    local rows = MySQL.query.await("SELECT * FROM `nyx_press_outlets` WHERE `license_status` = 'active'")
    return rows or {}
end)

Nyx.RPC.Register("press:getRecentPublications", function(src, payload)
    local limit = 20
    local cat = nil
    if type(payload) == "table" then
        limit = math.min(50, math.max(1, tonumber(payload.limit) or 20))
        cat = payload.category
    end

    local query = "SELECT * FROM `nyx_press_publications` WHERE `is_retracted` = 0"
    local params = {}
    if cat then
        query = query .. " AND `category` = ?"
        params[#params + 1] = cat
    end
    query = query .. " ORDER BY `created_at` DESC LIMIT ?"
    params[#params + 1] = limit

    local rows = MySQL.query.await(query, params)
    return rows or {}
end)

Nyx.RPC.Register("press:getPublication", function(src, pubId)
    if not pubId then return nil end
    return MySQL.single.await("SELECT * FROM `nyx_press_publications` WHERE `publication_id` = ?", { pubId })
end)

Nyx.RPC.Register("press:publishArticle", function(src, payload)
    return Nyx.Press.PublishArticle(src, payload)
end)

Nyx.RPC.Register("press:printCopies", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end
    return Nyx.Press.PrintCirculationCopies(src, payload.publicationId, payload.copies, payload.targetStandId)
end)

Nyx.RPC.Register("press:getDropboxes", function(src)
    local rows = MySQL.query.await("SELECT `dropbox_id`, `label`, `coords`, `public_pgp_fingerprint` FROM `nyx_press_whistleblower_dropboxes` WHERE `is_active` = 1")
    return rows or {}
end)

Nyx.RPC.Register("press:depositLeak", function(src, payload)
    return Nyx.Press.DepositWhistleblowerLeak(src, payload)
end)

Nyx.RPC.Register("press:getAvailableLeaks", function(src)
    return Nyx.Press.GetAvailableLeaks(src)
end)

Nyx.RPC.Register("press:claimLeak", function(src, leakId)
    return Nyx.Press.ClaimWhistleblowerLeak(src, leakId)
end)

Nyx.RPC.Register("press:getNewsstandInfo", function(src, standId)
    if not standId then return nil end
    return MySQL.single.await([[
        SELECT s.*, p.`headline`, p.`author_byline`, p.`category`, p.`price_per_copy`, p.`is_retracted`
        FROM `nyx_press_newsstands` s
        LEFT JOIN `nyx_press_publications` p ON s.`current_publication_id` = p.`publication_id`
        WHERE s.`stand_id` = ?
    ]], { standId })
end)

Nyx.RPC.Register("press:purchasePaper", function(src, standId)
    return Nyx.Press.PurchaseNewspaper(src, standId)
end)

Nyx.RPC.Register("press:retractPublication", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end
    return Nyx.Press.RetractPublication(src, payload.publicationId, payload.reason)
end)
