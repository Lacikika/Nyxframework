--[[
    Nyxframework: nyx_parliament
    File: server/campaign_finance.lua
    Description: Authoritative server logic for Political Action Committee (PAC) registration,
                 statutory donation caps, treasury transfers, and compliance audits.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- 1. Register a Political Action Committee (PAC)
function Nyx.Parliament.RegisterPAC(src, candidateId, officeId, title)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    if not title or type(title) ~= "string" or #title < 3 then
        return { success = false, error = "INVALID_PAC_TITLE" }
    end

    local citId = player.citizenId
    local fee = Config.PACRegistrationFee or 1000.00

    if fee > 0.0 then
        local debitAccount = "char:" .. citId .. ":bank"
        local creditAccount = "gov:escrow:pac"

        local balance = exports['nyx_treasury']:GetAccountBalance(debitAccount) or 0.0
        if balance < fee then
            return { success = false, error = "INSUFFICIENT_FUNDS_FOR_REGISTRATION", required = fee }
        end

        local okTransfer, transferErr = exports['nyx_treasury']:ExecuteTransfer(
            debitAccount,
            creditAccount,
            fee,
            "pac_registration_fee",
            "parliament:pac_reg:" .. citId,
            string.format("PAC Registration Fee: %s by %s", title, citId),
            0.0
        )

        if not okTransfer then
            return { success = false, error = "REGISTRATION_ESCROW_FAILED", detail = transferErr }
        end
    end

    local sanitizeTitle = title:gsub("[^%w%s]", ""):gsub("%s+", "_"):lower()
    local pacId = string.format("pac:%s_%s", sanitizeTitle:sub(1, 24), Nyx.RPC.GenerateNonce():sub(1, 6))

    -- Create dedicated PAC treasury account
    pcall(function()
        MySQL.prepare.await([[
            INSERT INTO `nyx_treasury_accounts`
                (`account_id`, `label`, `balance`, `type`, `signatories_required`)
            VALUES (?, ?, 0.00, 'reserve', 1)
            ON DUPLICATE KEY UPDATE `label` = VALUES(`label`)
        ]], { "account:" .. pacId, string.format("PAC Reserve: %s", title) })
    end)

    local inserted = MySQL.insert.await([[
        INSERT INTO `nyx_parliament_pacs`
            (`pac_id`, `candidate_id`, `office_id`, `title`, `treasurer_citizen_id`, `balance`, `total_donations_collected`, `status`)
        VALUES (?, ?, ?, ?, ?, 0.00, 0.00, 'active')
    ]], {
        pacId,
        candidateId,
        officeId,
        title,
        citId
    })

    if not inserted then
        return { success = false, error = "DATABASE_INSERTION_FAILED" }
    end

    print(string.format("^2[Nyx:Parliament] PAC '%s' (%s) registered by treasurer %s (Fee: $%.2f)^7",
        title, pacId, citId, fee))

    return {
        success = true,
        pacId = pacId,
        title = title,
        treasurerCitizenId = citId,
        balance = 0.00
    }
end

-- 2. Donate to a Political Action Committee with Statutory Cap Enforcement
function Nyx.Parliament.DonateToPAC(src, pacId, amount, donorFactionId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHORIZED" } end

    if not pacId or type(pacId) ~= "string" then
        return { success = false, error = "INVALID_PAC_ID" }
    end

    local amt = tonumber(amount) or 0.0
    if amt <= 0.0 then
        return { success = false, error = "INVALID_DONATION_AMOUNT" }
    end

    local pac = MySQL.single.await([[
        SELECT * FROM `nyx_parliament_pacs` WHERE `pac_id` = ?
    ]], { pacId })

    if not pac then
        return { success = false, error = "PAC_NOT_FOUND" }
    end

    if pac.status ~= "active" and pac.status ~= "audited" then
        return { success = false, error = "PAC_NOT_ACTIVE" }
    end

    local citId = player.citizenId
    local cap = Config.StatutoryDonationCap or 5000.00

    -- Query donor's cumulative existing contributions to this PAC
    local priorTotal = MySQL.scalar.await([[
        SELECT COALESCE(SUM(`amount`), 0.0)
        FROM `nyx_parliament_donations`
        WHERE `pac_id` = ? AND `donor_citizen_id` = ? AND `compliance_status` != 'refunded'
    ]], { pacId, citId }) or 0.0

    local okElig, evalReason, evalData = Nyx.CampaignFinance.EvaluateDonationEligibility(
        citId,
        priorTotal,
        amt,
        cap,
        donorFactionId ~= nil
    )

    if not okElig then
        return { success = false, error = evalReason, detail = evalData }
    end

    local debitAccount = "char:" .. citId .. ":bank"
    if donorFactionId and type(donorFactionId) == "string" and #donorFactionId > 0 then
        debitAccount = "faction:" .. donorFactionId .. ":vault"
    end

    local creditAccount = "gov:escrow:pac"

    local balance = exports['nyx_treasury']:GetAccountBalance(debitAccount) or 0.0
    if balance < amt then
        return { success = false, error = "INSUFFICIENT_FUNDS_FOR_DONATION", required = amt }
    end

    local okTransfer, txResult = exports['nyx_treasury']:ExecuteTransfer(
        debitAccount,
        creditAccount,
        amt,
        "campaign_donation",
        "parliament:" .. pacId,
        string.format("Campaign Finance Donation to %s by %s", pac.title, citId),
        0.0
    )

    if not okTransfer then
        return { success = false, error = "TREASURY_TRANSFER_FAILED", detail = txResult }
    end

    local txUuid = type(txResult) == "table" and txResult.txId or tostring(txResult or "TX-DONATION")
    local donationUuid = string.format("don_%s_%s", citId, Nyx.RPC.GenerateNonce():sub(1, 8))
    local complianceStatus = evalData and evalData.complianceStatus or "compliant"

    MySQL.insert.await([[
        INSERT INTO `nyx_parliament_donations`
            (`donation_uuid`, `pac_id`, `donor_citizen_id`, `donor_faction_id`, `amount`, `cap_limit_applied`, `compliance_status`, `treasury_tx_uuid`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        donationUuid,
        pacId,
        citId,
        donorFactionId,
        amt,
        cap,
        complianceStatus,
        txUuid
    })

    -- Update PAC balance and total collected
    MySQL.prepare.await([[
        UPDATE `nyx_parliament_pacs`
        SET `balance` = `balance` + ?, `total_donations_collected` = `total_donations_collected` + ?
        WHERE `pac_id` = ?
    ]], { amt, amt, pacId })

    print(string.format("^2[Nyx:Parliament] Donation $%.2f received for PAC '%s' from %s (Compliance: %s, Tx: %s)^7",
        amt, pac.title, citId, complianceStatus, txUuid))

    return {
        success = true,
        donationUuid = donationUuid,
        amount = amt,
        complianceStatus = complianceStatus,
        allowedAmount = evalData and evalData.allowedAmount or amt,
        excessAmount = evalData and evalData.excessAmount or 0.0,
        txUuid = txUuid
    }
end

-- 3. Perform PAC Statutory Audit & Assess Violations / Fines
function Nyx.Parliament.AuditPAC(src, pacId)
    if not pacId or type(pacId) ~= "string" then
        return { success = false, error = "INVALID_PAC_ID" }
    end

    local pac = MySQL.single.await([[
        SELECT * FROM `nyx_parliament_pacs` WHERE `pac_id` = ?
    ]], { pacId })

    if not pac then
        return { success = false, error = "PAC_NOT_FOUND" }
    end

    local donations = MySQL.query.await([[
        SELECT * FROM `nyx_parliament_donations` WHERE `pac_id` = ?
    ]], { pacId }) or {}

    local auditorCitId = "SYSTEM_PAC_AUDITOR"
    if src and src > 0 then
        local p = exports['nyx_core']:GetPlayer(src)
        if p then auditorCitId = p.citizenId end
    end

    local cap = Config.StatutoryDonationCap or 5000.00
    local mult = Config.PACAuditFineMultiplier or 1.5

    local summary = Nyx.CampaignFinance.CalculatePACAuditSummary(donations, cap, mult)
    local auditUuid = string.format("audit_%s_%s", pacId:gsub("[^%w]", ""):sub(1, 16), Nyx.RPC.GenerateNonce():sub(1, 6))

    if summary.fineAssessed > 0.0 then
        -- Execute statutory fine debit from PAC escrow to city treasury master account
        pcall(function()
            exports['nyx_treasury']:ExecuteTransfer(
                "gov:escrow:pac",
                "gov:city:master",
                summary.fineAssessed,
                "pac_statutory_fine",
                "parliament:audit:" .. auditUuid,
                string.format("Statutory PAC Campaign Finance Fine: %s", pac.title),
                0.0
            )
        end)
    end

    MySQL.insert.await([[
        INSERT INTO `nyx_parliament_pac_audits`
            (`audit_uuid`, `pac_id`, `auditor_citizen_id`, `total_audited_contributions`,
             `flagged_excess_amount`, `fine_assessed`, `audit_status`, `notes`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        auditUuid,
        pacId,
        auditorCitId,
        summary.totalContributions,
        summary.flaggedExcessAmount,
        summary.fineAssessed,
        summary.auditStatus,
        string.format("Audited %d contributions. Flagged: %d (Excess: $%.2f, Fine: $%.2f)",
            summary.totalCount, summary.flaggedCount, summary.flaggedExcessAmount, summary.fineAssessed)
    })

    MySQL.prepare.await([[
        UPDATE `nyx_parliament_pacs` SET `status` = 'audited' WHERE `pac_id` = ?
    ]], { pacId })

    print(string.format("^3[Nyx:Parliament] PAC Audit complete for '%s' (%s): Status = %s, Excess = $%.2f, Fine = $%.2f^7",
        pac.title, pacId, summary.auditStatus, summary.flaggedExcessAmount, summary.fineAssessed))

    return {
        success = true,
        auditUuid = auditUuid,
        auditSummary = summary
    }
end

-- ============================================================================
-- RPC Registrations for Campaign Finance & PACs
-- ============================================================================

Nyx.RPC.Register("parliament:registerPAC", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end
    return Nyx.Parliament.RegisterPAC(src, payload.candidateId, payload.officeId, payload.title)
end)

Nyx.RPC.Register("parliament:donateToPAC", function(src, payload)
    if type(payload) ~= "table" then return { success = false, error = "INVALID_PAYLOAD" } end
    return Nyx.Parliament.DonateToPAC(src, payload.pacId, payload.amount, payload.donorFactionId)
end)

Nyx.RPC.Register("parliament:auditPAC", function(src, pacId)
    return Nyx.Parliament.AuditPAC(src, pacId)
end)

Nyx.RPC.Register("parliament:getPACs", function(src)
    local rows = MySQL.query.await([[
        SELECT `pac_id`, `candidate_id`, `office_id`, `title`, `treasurer_citizen_id`,
               `balance`, `total_donations_collected`, `status`, `created_at`
        FROM `nyx_parliament_pacs`
        ORDER BY `total_donations_collected` DESC
    ]])
    return rows or {}
end)

Nyx.RPC.Register("parliament:getPACDonations", function(src, pacId)
    if not pacId then return {} end
    local rows = MySQL.query.await([[
        SELECT `donation_id`, `donation_uuid`, `pac_id`, `donor_citizen_id`, `donor_faction_id`,
               `amount`, `cap_limit_applied`, `compliance_status`, `treasury_tx_uuid`, `donated_at`
        FROM `nyx_parliament_donations`
        WHERE `pac_id` = ?
        ORDER BY `donated_at` DESC
    ]], { pacId })
    return rows or {}
end)

Nyx.RPC.Register("parliament:getPACAudits", function(src, pacId)
    local query = [[
        SELECT `audit_id`, `audit_uuid`, `pac_id`, `auditor_citizen_id`, `total_audited_contributions`,
               `flagged_excess_amount`, `fine_assessed`, `audit_status`, `notes`, `audited_at`
        FROM `nyx_parliament_pac_audits`
    ]]
    local params = {}
    if pacId and #pacId > 0 then
        query = query .. " WHERE `pac_id` = ?"
        params[#params + 1] = pacId
    end
    query = query .. " ORDER BY `audited_at` DESC LIMIT 50"

    local rows = MySQL.query.await(query, params)
    return rows or {}
end)
