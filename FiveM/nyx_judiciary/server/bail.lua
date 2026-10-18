--[[
    Nyxframework: nyx_judiciary
    File: server/bail.lua
    Description: Authoritative server subsystem for pre-trial judicial bail bonds,
                 municipal escrow pools, appearance verification, exoneration splits,
                 bail forfeiture, and automated fugitive recovery bounties.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}
Nyx.Judiciary.ActiveBailBonds = {} -- [bondId] = bondData
Nyx.Judiciary.BailByDefendant = {} -- [citizenId] = bondId
Nyx.Judiciary.BailByDocket = {}    -- [docketId] = bondId

-- Helper: Generate UUID v4
local function generateUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format("%x", v)
    end)
end

-- Helper: Log immutable audit entry to nyx_judiciary_bail_audits
local function logBailAudit(bondId, docketId, citizenId, action, amount, notes, txUuid)
    local auditUuid = generateUUID()
    MySQL.prepare([[
        INSERT INTO `nyx_judiciary_bail_audits`
        (`audit_uuid`, `bond_id`, `docket_id`, `citizen_id`, `action`, `amount`, `treasury_tx_uuid`, `notes`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        auditUuid,
        bondId or 0,
        docketId or "UNKNOWN",
        citizenId or "SYSTEM",
        action,
        tonumber(amount) or 0.00,
        txUuid or nil,
        notes or nil
    })
end

-- 1. Bootloader Cache Hydration: Load active bail bonds on resource start
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end

    local rows = MySQL.query.await([[
        SELECT * FROM `nyx_judiciary_bail_bonds`
        WHERE `status` = 'posted'
    ]])

    if rows then
        for _, row in ipairs(rows) do
            local conditions = {}
            if row.conditions and type(row.conditions) == "string" then
                local ok, parsed = pcall(json.decode, row.conditions)
                if ok and type(parsed) == "table" then conditions = parsed end
            end

            local bondData = {
                id = row.bond_id,
                uuid = row.bond_uuid,
                docketId = row.docket_id,
                defendantCitId = row.defendant_citizen_id,
                posterCitId = row.poster_citizen_id,
                bondType = row.bond_type,
                bailAmount = tonumber(row.bail_amount) or 0.00,
                collateralAmount = tonumber(row.collateral_amount) or 0.00,
                bondsmanFee = tonumber(row.bondsman_fee) or 0.00,
                clerkAdminFee = tonumber(row.clerk_admin_fee) or 0.00,
                status = row.status,
                escrowAcc = row.escrow_account_id,
                conditions = conditions,
                appearanceVerified = (tonumber(row.court_appearance_verified) == 1),
                bountyClaimed = (tonumber(row.bounty_claimed) == 1),
                postedAt = row.posted_at
            }

            Nyx.Judiciary.ActiveBailBonds[row.bond_id] = bondData
            Nyx.Judiciary.BailByDefendant[row.defendant_citizen_id] = row.bond_id
            Nyx.Judiciary.BailByDocket[row.docket_id] = row.bond_id
        end
        print(string.format("^2[Nyx:Judiciary] Hydrated %d active judicial bail bonds into memory.^7", #rows))
    end
end)

-- 2. Configure Bail Schedule for a Docket
function Nyx.Judiciary.SetBailSchedule(docketId, judgeCitizenId, bailAmount, conditions)
    if not docketId then
        return false, "INVALID_DOCKET_ID"
    end

    local docket = MySQL.single.await([[
        SELECT `docket_id`, `case_type`, `status`, `bail_status`
        FROM `nyx_judiciary_dockets`
        WHERE `docket_id` = ?
    ]], { docketId })

    if not docket then
        return false, "DOCKET_NOT_FOUND"
    end

    if docket.status == 'concluded' or docket.status == 'dismissed' then
        return false, "DOCKET_ALREADY_CLOSED"
    end

    local amount = math.max(Nyx.BailBonds.MIN_BAIL_AMOUNT, tonumber(bailAmount) or Nyx.BailBonds.CalculateBailSchedule(docket.case_type, 0, 1.0))
    conditions = conditions or { "curfew_2200", "no_weapons", "stay_in_county" }

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_dockets`
        SET `bail_schedule_amount` = ?,
            `bail_status` = 'eligible'
        WHERE `docket_id` = ?
    ]], { amount, docketId })

    logBailAudit(0, docketId, judgeCitizenId or "COURT_MAGISTRATE", "BAIL_SCHEDULE_SET", amount, "Statutory bail schedule established")

    return true, {
        docketId = docketId,
        bailAmount = amount,
        conditions = conditions
    }
end

-- 3. Post Pre-Trial Bail Bond (Cash or Commercial Surety)
function Nyx.Judiciary.PostBail(source, docketId, bondType, guarantorCitizenId)
    local player = exports['nyx_core']:GetPlayer(source)
    if not player then return false, "UNAUTHENTICATED" end

    local docket = MySQL.single.await([[
        SELECT `docket_id`, `defendant_citizen_id`, `case_type`, `status`,
               `bail_schedule_amount`, `bail_status`
        FROM `nyx_judiciary_dockets`
        WHERE `docket_id` = ?
    ]], { docketId })

    if not docket then return false, "DOCKET_NOT_FOUND" end

    local isEligible, reason = Nyx.BailBonds.EvaluateBailEligibility(docket, nil)
    if not isEligible then
        return false, reason
    end

    if docket.bail_status == 'posted' then
        return false, "BAIL_ALREADY_POSTED"
    end

    local bailAmount = tonumber(docket.bail_schedule_amount)
    if not bailAmount or bailAmount <= 0.0 then
        bailAmount = Nyx.BailBonds.CalculateBailSchedule(docket.case_type, 0, 1.0)
    end

    bondType = bondType or Nyx.BailBonds.BOND_CASH
    local breakdown = Nyx.BailBonds.CalculateBailPaymentBreakdown(bailAmount, bondType)
    if not breakdown then
        return false, "INVALID_BOND_TYPE"
    end

    local posterCitId = guarantorCitizenId or player.citizenId
    local posterAcc = "citizen:" .. posterCitId
    local escrowAcc = "gov:escrow:bail"

    -- Verify liquidity and transfer required deposit to municipal bail escrow
    if exports['nyx_treasury'] then
        local posterBal = exports['nyx_treasury']:GetAccountBalance(posterAcc) or 0.0
        if posterBal < breakdown.requiredUpfrontDeposit then
            return false, "INSUFFICIENT_POSTER_FUNDS"
        end

        local transferOk, txId = exports['nyx_treasury']:ExecuteTransfer(
            posterAcc,
            escrowAcc,
            breakdown.requiredUpfrontDeposit,
            "bail_escrow",
            string.format("Bail Bond Escrow: %s (%s)", docketId, bondType),
            0.0
        )

        if not transferOk then
            return false, "ESCROW_TRANSFER_FAILED"
        end

        breakdown.treasuryTxUuid = txId
    end

    local bondUuid = generateUUID()
    local defaultConditions = { "no_weapons", "curfew_2200", "stay_in_county" }

    local bondId = MySQL.insert.await([[
        INSERT INTO `nyx_judiciary_bail_bonds`
        (`bond_uuid`, `docket_id`, `defendant_citizen_id`, `poster_citizen_id`, `bond_type`,
         `bail_amount`, `collateral_amount`, `bondsman_fee`, `clerk_admin_fee`, `status`,
         `escrow_account_id`, `treasury_tx_uuid`, `conditions`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'posted', ?, ?, ?)
    ]], {
        bondUuid,
        docketId,
        docket.defendant_citizen_id,
        posterCitId,
        bondType,
        breakdown.bailAmount,
        breakdown.suretyCollateral,
        breakdown.suretyPremiumPaid,
        breakdown.clerkAdminFee,
        escrowAcc,
        breakdown.treasuryTxUuid or nil,
        json.encode(defaultConditions)
    })

    if not bondId then
        return false, "DATABASE_ERROR"
    end

    -- Update docket with bail reference
    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_dockets`
        SET `bail_status` = 'posted',
            `bail_bond_id` = ?
        WHERE `docket_id` = ?
    ]], { bondId, docketId })

    -- Hydrate into active cache
    local bondRecord = {
        id = bondId,
        uuid = bondUuid,
        docketId = docketId,
        defendantCitId = docket.defendant_citizen_id,
        posterCitId = posterCitId,
        bondType = bondType,
        bailAmount = breakdown.bailAmount,
        collateralAmount = breakdown.suretyCollateral,
        bondsmanFee = breakdown.suretyPremiumPaid,
        clerkAdminFee = breakdown.clerkAdminFee,
        status = 'posted',
        escrowAcc = escrowAcc,
        conditions = defaultConditions,
        appearanceVerified = false,
        bountyClaimed = false,
        postedAt = os.date("%Y-%m-%d %H:%M:%S")
    }

    Nyx.Judiciary.ActiveBailBonds[bondId] = bondRecord
    Nyx.Judiciary.BailByDefendant[docket.defendant_citizen_id] = bondId
    Nyx.Judiciary.BailByDocket[docketId] = bondId

    logBailAudit(bondId, docketId, posterCitId, "BAIL_POSTED", breakdown.requiredUpfrontDeposit,
        string.format("Pre-trial bail posted via %s bond", bondType), breakdown.treasuryTxUuid)

    -- Broadcast state update
    TriggerClientEvent("nyx:judiciary:client:bailStatusChanged", -1, {
        bondId = bondId,
        docketId = docketId,
        defendantCitId = docket.defendant_citizen_id,
        status = "posted",
        bailAmount = breakdown.bailAmount
    })

    return true, bondRecord
end

-- 4. Verify Physical Court Appearance at Courtroom Terminal
function Nyx.Judiciary.VerifyCourtAppearance(source, docketId)
    local player = exports['nyx_core']:GetPlayer(source)
    if not player then return false, "UNAUTHENTICATED" end

    local bondId = Nyx.Judiciary.BailByDocket[docketId]
    local bond = bondId and Nyx.Judiciary.ActiveBailBonds[bondId]

    if not bond then
        local row = MySQL.single.await([[
            SELECT * FROM `nyx_judiciary_bail_bonds`
            WHERE `docket_id` = ? AND `status` = 'posted'
        ]], { docketId })
        if not row then return false, "NO_ACTIVE_BAIL_BOND" end
        bond = {
            id = row.bond_id,
            docketId = row.docket_id,
            defendantCitId = row.defendant_citizen_id,
            appearanceVerified = (tonumber(row.court_appearance_verified) == 1)
        }
    end

    -- Proximity verification to Central Courthouse
    local ped = GetPlayerPed(source)
    local pCoords = GetEntityCoords(ped)
    local courtCoords = Nyx.BailBonds.TERMINALS['court_central_ls'].coords
    local isNear, dist = Nyx.BailBonds.EvaluateCourtAppearance(
        { x = pCoords.x, y = pCoords.y, z = pCoords.z },
        { x = courtCoords.x, y = courtCoords.y, z = courtCoords.z },
        Nyx.BailBonds.MAX_COURTROOM_CHECKIN_DIST
    )

    if not isNear then
        return false, string.format("NOT_IN_COURTROOM_ZONE (dist: %.2fm)", dist)
    end

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_bail_bonds`
        SET `court_appearance_verified` = 1
        WHERE `bond_id` = ?
    ]], { bond.id })

    if Nyx.Judiciary.ActiveBailBonds[bond.id] then
        Nyx.Judiciary.ActiveBailBonds[bond.id].appearanceVerified = true
    end

    logBailAudit(bond.id, docketId, player.citizenId, "APPEARANCE_CHECKED", 0.0, "Defendant verified present in courtroom for docket trial")

    return true, {
        bondId = bond.id,
        docketId = docketId,
        appearanceVerified = true
    }
end

-- 5. Exonerate Pre-Trial Bail Bond (Verdict rendered or case concluded)
function Nyx.Judiciary.ExonerateBail(docketId, reason)
    if not docketId then return false, "INVALID_DOCKET_ID" end

    local row = MySQL.single.await([[
        SELECT * FROM `nyx_judiciary_bail_bonds`
        WHERE `docket_id` = ? AND `status` = 'posted'
    ]], { docketId })

    if not row then
        return false, "NO_POSTED_BAIL_FOUND"
    end

    local breakdown = Nyx.BailBonds.CalculateBailPaymentBreakdown(row.bail_amount, row.bond_type)
    local escrowAcc = "gov:escrow:bail"
    local posterAcc = "citizen:" .. row.poster_citizen_id
    local cityMasterAcc = "gov:city:master"

    -- Double-entry refund and administrative clerk fee execution
    if exports['nyx_treasury'] then
        -- Step 1: Refund 95% of collateral to poster
        if breakdown.exonerationRefund > 0.0 then
            exports['nyx_treasury']:ExecuteTransfer(
                escrowAcc,
                posterAcc,
                breakdown.exonerationRefund,
                "bail_refund",
                string.format("Court Bail Exoneration Refund: %s", docketId),
                0.0
            )
        end

        -- Step 2: Transfer 5% clerk administration fee to municipal master account
        if breakdown.clerkAdminFee > 0.0 then
            exports['nyx_treasury']:ExecuteTransfer(
                escrowAcc,
                cityMasterAcc,
                breakdown.clerkAdminFee,
                "fee",
                string.format("Court Bail Administration Clerk Fee (5%%): %s", docketId),
                0.0
            )
        end
    end

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_bail_bonds`
        SET `status` = 'exonerated',
            `resolved_at` = CURRENT_TIMESTAMP,
            `notes` = ?
        WHERE `bond_id` = ?
    ]], { reason or "Trial concluded; bail exonerated by San Andreas District Court.", row.bond_id })

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_dockets`
        SET `bail_status` = 'exonerated'
        WHERE `docket_id` = ?
    ]], { docketId })

    Nyx.Judiciary.ActiveBailBonds[row.bond_id] = nil
    Nyx.Judiciary.BailByDefendant[row.defendant_citizen_id] = nil
    Nyx.Judiciary.BailByDocket[docketId] = nil

    logBailAudit(row.bond_id, docketId, row.poster_citizen_id, "BAIL_EXONERATED", breakdown.exonerationRefund,
        string.format("Exoneration completed (Refund: $%.2f, Fee: $%.2f)", breakdown.exonerationRefund, breakdown.clerkAdminFee))

    TriggerClientEvent("nyx:judiciary:client:bailStatusChanged", -1, {
        bondId = row.bond_id,
        docketId = docketId,
        defendantCitId = row.defendant_citizen_id,
        status = "exonerated"
    })

    return true, {
        bondId = row.bond_id,
        docketId = docketId,
        status = "exonerated",
        refundAmount = breakdown.exonerationRefund,
        clerkAdminFee = breakdown.clerkAdminFee
    }
end

-- 6. Forfeit Pre-Trial Bail Bond (Failure to Appear / Bail Jumping)
function Nyx.Judiciary.ForfeitBail(docketId, reason)
    if not docketId then return false, "INVALID_DOCKET_ID" end

    local row = MySQL.single.await([[
        SELECT * FROM `nyx_judiciary_bail_bonds`
        WHERE `docket_id` = ? AND `status` = 'posted'
    ]], { docketId })

    if not row then
        return false, "NO_POSTED_BAIL_FOUND"
    end

    local bailAmount = tonumber(row.bail_amount) or 0.00
    local forfeitedAmount, recoveryBounty = Nyx.BailBonds.CalculateForfeitureAndBounty(bailAmount)
    local escrowAcc = "gov:escrow:bail"
    local cityMasterAcc = "gov:city:master"

    -- Double-entry seizure of 100% of escrow into municipal general reserves
    if exports['nyx_treasury'] and forfeitedAmount > 0.0 then
        exports['nyx_treasury']:ExecuteTransfer(
            escrowAcc,
            cityMasterAcc,
            forfeitedAmount,
            "fine",
            string.format("Court Bail Forfeiture (FTA - Bail Jumping): %s", docketId),
            0.0
        )
    end

    -- Automatically issue Felony Arrest Warrant for Bail Jumping with Bounty Reward
    local warrantReason = string.format("FTA: Bail Jumping on docket %s. Fugitive recovery bounty: $%.2f", docketId, recoveryBounty)
    local warrantId = nil
    if Nyx.Judiciary.IssueWarrant then
        local wOk, wRes = Nyx.Judiciary.IssueWarrant(
            "CHIEF_MAGISTRATE",
            row.defendant_citizen_id,
            "arrest",
            warrantReason,
            nil,
            72 -- 72 hours duration
        )
        if wOk and type(wRes) == "table" then
            warrantId = wRes.warrantId
        end
    end

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_bail_bonds`
        SET `status` = 'forfeited',
            `resolved_at` = CURRENT_TIMESTAMP,
            `notes` = ?
        WHERE `bond_id` = ?
    ]], { reason or warrantReason, row.bond_id })

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_dockets`
        SET `bail_status` = 'forfeited'
        WHERE `docket_id` = ?
    ]], { docketId })

    Nyx.Judiciary.ActiveBailBonds[row.bond_id] = nil
    Nyx.Judiciary.BailByDefendant[row.defendant_citizen_id] = nil
    Nyx.Judiciary.BailByDocket[docketId] = nil

    logBailAudit(row.bond_id, docketId, row.defendant_citizen_id, "BAIL_FORFEITED_FTA", forfeitedAmount,
        string.format("Bail forfeited to city treasury; fugitive arrest warrant issued (Bounty: $%.2f)", recoveryBounty))

    TriggerClientEvent("nyx:judiciary:client:bailStatusChanged", -1, {
        bondId = row.bond_id,
        docketId = docketId,
        defendantCitId = row.defendant_citizen_id,
        status = "forfeited",
        bounty = recoveryBounty,
        warrantId = warrantId
    })

    return true, {
        bondId = row.bond_id,
        docketId = docketId,
        forfeitedAmount = forfeitedAmount,
        fugitiveBounty = recoveryBounty,
        warrantId = warrantId
    }
end

-- 7. Claim Fugitive Recovery Bounty upon Apprehension
function Nyx.Judiciary.ClaimFugitiveBounty(source, bondId, fugitiveCitizenId)
    local player = exports['nyx_core']:GetPlayer(source)
    if not player then return false, "UNAUTHENTICATED" end

    local row = MySQL.single.await([[
        SELECT * FROM `nyx_judiciary_bail_bonds`
        WHERE `bond_id` = ? AND `status` = 'forfeited' AND `bounty_claimed` = 0
    ]], { bondId })

    if not row then
        return false, "BOUNTY_NOT_AVAILABLE_OR_ALREADY_CLAIMED"
    end

    if row.defendant_citizen_id ~= fugitiveCitizenId then
        return false, "FUGITIVE_CITIZEN_MISMATCH"
    end

    local bailAmount = tonumber(row.bail_amount) or 0.00
    local _, recoveryBounty = Nyx.BailBonds.CalculateForfeitureAndBounty(bailAmount)
    local claimantAcc = "citizen:" .. player.citizenId
    local cityMasterAcc = "gov:city:master"

    if exports['nyx_treasury'] and recoveryBounty > 0.0 then
        local ok, txId = exports['nyx_treasury']:ExecuteTransfer(
            cityMasterAcc,
            claimantAcc,
            recoveryBounty,
            "grant",
            string.format("Fugitive Recovery Bounty Payout: Docket %s (Cit: %s)", row.docket_id, fugitiveCitizenId),
            0.0
        )
        if not ok then
            return false, "TREASURY_BOUNTY_DISBURSEMENT_FAILED"
        end
    end

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_bail_bonds`
        SET `bounty_claimed` = 1,
            `bounty_hunter_citizen_id` = ?
        WHERE `bond_id` = ?
    ]], { player.citizenId, bondId })

    logBailAudit(bondId, row.docket_id, player.citizenId, "BOUNTY_DISBURSED", recoveryBounty,
        string.format("Fugitive recovery bounty disbursed to %s", player.citizenId))

    return true, {
        bondId = bondId,
        fugitiveCitId = fugitiveCitizenId,
        bountyAmount = recoveryBounty,
        claimant = player.citizenId
    }
end

-- 8. Query Functions
function Nyx.Judiciary.GetActiveBailBond(bondId)
    if not bondId then return nil end
    if Nyx.Judiciary.ActiveBailBonds[bondId] then
        return Nyx.Judiciary.ActiveBailBonds[bondId]
    end
    local row = MySQL.single.await("SELECT * FROM `nyx_judiciary_bail_bonds` WHERE `bond_id` = ?", { bondId })
    return row
end

function Nyx.Judiciary.GetDefendantBail(citizenId)
    if not citizenId then return nil end
    local bondId = Nyx.Judiciary.BailByDefendant[citizenId]
    if bondId and Nyx.Judiciary.ActiveBailBonds[bondId] then
        return Nyx.Judiciary.ActiveBailBonds[bondId]
    end
    local row = MySQL.single.await([[
        SELECT * FROM `nyx_judiciary_bail_bonds`
        WHERE `defendant_citizen_id` = ? AND `status` = 'posted'
        ORDER BY `posted_at` DESC LIMIT 1
    ]], { citizenId })
    return row
end

-- 9. RPC Route Bindings
Nyx.RPC.Register("judiciary:getBailSchedule", function(src, docketId)
    local docket = MySQL.single.await("SELECT * FROM `nyx_judiciary_dockets` WHERE `docket_id` = ?", { docketId })
    if not docket then return nil, "DOCKET_NOT_FOUND" end
    local scheduleAmount = tonumber(docket.bail_schedule_amount)
    if not scheduleAmount or scheduleAmount <= 0.0 then
        scheduleAmount = Nyx.BailBonds.CalculateBailSchedule(docket.case_type, 0, 1.0)
    end
    local cashBreakdown = Nyx.BailBonds.CalculateBailPaymentBreakdown(scheduleAmount, "cash")
    local suretyBreakdown = Nyx.BailBonds.CalculateBailPaymentBreakdown(scheduleAmount, "surety")
    return {
        docketId = docketId,
        caseType = docket.case_type,
        bailStatus = docket.bail_status,
        bailAmount = scheduleAmount,
        cash = cashBreakdown,
        surety = suretyBreakdown
    }
end)

Nyx.RPC.Register("judiciary:postBail", function(src, docketId, bondType, guarantorCitizenId)
    return Nyx.Judiciary.PostBail(src, docketId, bondType, guarantorCitizenId)
end)

Nyx.RPC.Register("judiciary:checkinCourtAppearance", function(src, docketId)
    return Nyx.Judiciary.VerifyCourtAppearance(src, docketId)
end)

Nyx.RPC.Register("judiciary:getDefendantBailStatus", function(src, targetCitizenId)
    local citId = targetCitizenId
    if not citId then
        local player = exports['nyx_core']:GetPlayer(src)
        citId = player and player.citizenId
    end
    if not citId then return nil, "UNAUTHENTICATED" end
    return Nyx.Judiciary.GetDefendantBail(citId)
end)

Nyx.RPC.Register("judiciary:claimFugitiveBounty", function(src, bondId, fugitiveCitizenId)
    return Nyx.Judiciary.ClaimFugitiveBounty(src, bondId, fugitiveCitizenId)
end)
