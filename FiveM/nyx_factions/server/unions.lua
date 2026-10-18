--[[
    Nyxframework: nyx_factions
    File: server/unions.lua
    Description: Authoritative server trade union registry, automated dues checkoff,
                 strike fund management, and strike relief disbursements.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}
Nyx.Factions.Unions = Nyx.Factions.Unions or {}

-- Utility: Generate slugified union identifier
local function generateUnionId(legalName)
    local slug = string.lower(legalName:gsub("%s+", "_"):gsub("[^%w_]", ""))
    if #slug > 24 then slug = string.sub(slug, 1, 24) end
    return string.format("union:%s", slug)
end

-- 1. Register a new democratic trade union
function Nyx.Factions.RegisterUnion(src, legalName, industrySector, duesAmount, duesMode)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    if not legalName or string.len(legalName) < 3 or string.len(legalName) > 96 then
        return false, "INVALID_LEGAL_NAME"
    end

    local allowedSectors = Config.Unions and Config.Unions.Sectors or {}
    if not allowedSectors[industrySector] then
        industrySector = "general"
    end

    local unionId = generateUnionId(legalName)
    local treasuryAcc = unionId

    -- Ensure unique union_id and legal name
    local exists = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_factions_unions`
        WHERE `union_id` = ? OR `legal_name` = ?
    ]], { unionId, legalName })

    if exists and exists > 0 then
        return false, "UNION_ALREADY_EXISTS"
    end

    local mode = (duesMode == "percentage") and "percentage" or "flat"
    local duesAmt = math.max(10.0, math.floor((tonumber(duesAmount) or Config.Unions.DefaultDuesFlat or 50.0) * 100) / 100)
    local duesRate = Config.Unions.DefaultDuesRate or 0.025
    local strikePayRate = Config.Unions.DefaultStrikePayRate or 150.00

    -- Provision union treasury account in nyx_treasury
    if exports['nyx_treasury'] and exports['nyx_treasury'].EnsureAccount then
        exports['nyx_treasury']:EnsureAccount(treasuryAcc, string.format("%s Strike & Operating Fund", legalName), "union_treasury", 0.00)
    end

    local ok = MySQL.prepare.await([[
        INSERT INTO `nyx_factions_unions`
            (`union_id`, `legal_name`, `industry_sector`, `treasury_account_id`, `founder_citizen_id`,
             `dues_amount`, `dues_rate`, `dues_mode`, `strike_fund_balance`, `strike_pay_rate`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0.00, ?, 'active')
    ]], {
        unionId,
        legalName,
        industrySector,
        treasuryAcc,
        player.citizenId,
        duesAmt,
        duesRate,
        mode,
        strikePayRate
    })

    if not ok then
        return false, "DATABASE_ERROR"
    end

    -- Add founder as Chief Union Steward
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_union_members`
            (`union_id`, `citizen_id`, `enterprise_faction_id`, `role`, `standing`, `joined_at`)
        VALUES (?, ?, NULL, 'steward', 'good_standing', CURRENT_TIMESTAMP)
    ]], { unionId, player.citizenId })

    if Config.Debug then
        print(string.format("^2[Nyx:Factions]^7 Registered Trade Union %s (%s) by %s^7", legalName, unionId, player.citizenId))
    end

    return true, {
        unionId = unionId,
        legalName = legalName,
        industrySector = industrySector,
        treasuryAccountId = treasuryAcc,
        duesAmount = duesAmt,
        duesMode = mode,
        strikePayRate = strikePayRate
    }
end

-- 2. Join a trade union
function Nyx.Factions.JoinUnion(src, unionId, enterpriseFactionId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local union = MySQL.single.await([[
        SELECT * FROM `nyx_factions_unions` WHERE `union_id` = ? AND `status` = 'active'
    ]], { unionId })

    if not union then
        return false, "UNION_NOT_FOUND"
    end

    -- Check if already a member
    local isMember = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_factions_union_members`
        WHERE `union_id` = ? AND `citizen_id` = ?
    ]], { unionId, player.citizenId })

    if isMember and isMember > 0 then
        return false, "ALREADY_MEMBER"
    end

    local ok = MySQL.prepare.await([[
        INSERT INTO `nyx_factions_union_members`
            (`union_id`, `citizen_id`, `enterprise_faction_id`, `role`, `standing`, `joined_at`)
        VALUES (?, ?, ?, 'member', 'good_standing', CURRENT_TIMESTAMP)
        ON DUPLICATE KEY UPDATE
            `enterprise_faction_id` = VALUES(`enterprise_faction_id`),
            `standing` = 'good_standing'
    ]], { unionId, player.citizenId, enterpriseFactionId or nil })

    return (ok ~= nil), unionId
end

-- 3. Leave a trade union
function Nyx.Factions.LeaveUnion(src, unionId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local affected = MySQL.update.await([[
        DELETE FROM `nyx_factions_union_members`
        WHERE `union_id` = ? AND `citizen_id` = ? AND `role` != 'steward'
    ]], { unionId, player.citizenId })

    if affected and affected > 0 then
        return true
    end

    return false, "CANNOT_LEAVE_OR_STEWARD_MUST_TRANSFER"
end

-- 4. Query union details
function Nyx.Factions.GetUnion(unionId)
    local union = MySQL.single.await([[
        SELECT * FROM `nyx_factions_unions` WHERE `union_id` = ?
    ]], { unionId })
    if not union then return nil end

    local memberCount = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_factions_union_members` WHERE `union_id` = ?
    ]], { unionId }) or 0

    local runway = Nyx.Unions.CalculateStrikeFundRunway(
        tonumber(union.strike_fund_balance) or 0.0,
        memberCount,
        tonumber(union.strike_pay_rate) or 150.00
    )

    return {
        unionId = union.union_id,
        legalName = union.legal_name,
        industrySector = union.industry_sector,
        treasuryAccountId = union.treasury_account_id,
        founderCitizenId = union.founder_citizen_id,
        duesAmount = tonumber(union.dues_amount) or 50.00,
        duesRate = tonumber(union.dues_rate) or 0.025,
        duesMode = union.dues_mode,
        strikeFundBalance = tonumber(union.strike_fund_balance) or 0.00,
        strikePayRate = tonumber(union.strike_pay_rate) or 150.00,
        status = union.status,
        memberCount = tonumber(memberCount) or 0,
        runway = runway
    }
end

-- 5. Query citizen union membership
function Nyx.Factions.GetCitizenUnionMembership(citizenId)
    if not citizenId then return nil end
    local row = MySQL.single.await([[
        SELECT m.*, u.legal_name, u.industry_sector, u.dues_amount, u.dues_mode, u.strike_pay_rate
        FROM `nyx_factions_union_members` m
        JOIN `nyx_factions_unions` u ON m.union_id = u.union_id
        WHERE m.citizen_id = ? AND u.status = 'active'
    ]], { citizenId })
    return row
end

-- 6. Query all active trade unions
function Nyx.Factions.GetAllUnions()
    local rows = MySQL.query.await([[
        SELECT u.*, COUNT(m.id) AS member_count
        FROM `nyx_factions_unions` u
        LEFT JOIN `nyx_factions_union_members` m ON u.union_id = m.union_id
        WHERE u.status = 'active'
        GROUP BY u.union_id
    ]])
    return rows or {}
end

-- 7. Automated Dues Checkoff Processing
-- Called during payroll or direct wage distribution
function Nyx.Factions.ProcessUnionDues(citizenId, grossWage, enterpriseFactionId)
    grossWage = math.max(0.0, math.floor((tonumber(grossWage) or 0.0) * 100) / 100)
    local membership = Nyx.Factions.GetCitizenUnionMembership(citizenId)

    if not membership or membership.standing == "exempt" then
        return grossWage, 0.00, nil
    end

    local duesAmount, netWage = Nyx.Unions.CalculateDuesCheckoff(
        grossWage,
        membership.dues_mode,
        membership.dues_amount,
        membership.dues_rate
    )

    if duesAmount > 0.00 and exports['nyx_treasury'] then
        local payerAcc = string.format("char:%s:bank", citizenId)
        local unionAcc = membership.treasury_account_id or membership.union_id

        local ok, txId = exports['nyx_treasury']:ExecuteTransfer(
            payerAcc,
            unionAcc,
            duesAmount,
            "union_dues",
            payerAcc,
            string.format("Automated Union Dues Checkoff (%s)", membership.legal_name),
            0.0
        )

        if ok then
            -- Allocate 60% of dues to strike fund, 40% to operating fund
            local strikeFundContribution = math.floor((duesAmount * 0.60) * 100) / 100
            MySQL.prepare([[
                UPDATE `nyx_factions_unions`
                SET `strike_fund_balance` = `strike_fund_balance` + ?
                WHERE `union_id` = ?
            ]], { strikeFundContribution, membership.union_id })

            MySQL.prepare([[
                UPDATE `nyx_factions_union_members`
                SET `last_dues_paid_at` = CURRENT_TIMESTAMP,
                    `unpaid_dues` = 0.00,
                    `standing` = 'good_standing'
                WHERE `union_id` = ? AND `citizen_id` = ?
            ]], { membership.union_id, citizenId })

            return netWage, duesAmount, membership.union_id
        end
    end

    return grossWage, 0.00, membership.union_id
end

-- 8. Claim Daily Strike Pay / Relief Stipend
function Nyx.Factions.ClaimStrikeRelief(src, unionId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local membership = MySQL.single.await([[
        SELECT * FROM `nyx_factions_union_members`
        WHERE `union_id` = ? AND `citizen_id` = ?
    ]], { unionId, player.citizenId })

    if not membership then
        return false, "NOT_UNION_MEMBER"
    end

    if membership.standing == "arrears" then
        return false, "MEMBER_IN_ARREARS"
    end

    local enterpriseId = membership.enterprise_faction_id
    if not enterpriseId or not Nyx.Factions.IsEnterpriseOnStrike(enterpriseId) then
        return false, "ENTERPRISE_NOT_ON_STRIKE"
    end

    local union = MySQL.single.await([[
        SELECT * FROM `nyx_factions_unions` WHERE `union_id` = ?
    ]], { unionId })

    if not union then return false, "UNION_NOT_FOUND" end

    local strikePay = tonumber(union.strike_pay_rate) or 150.00
    local balance = tonumber(union.strike_fund_balance) or 0.00

    if balance < strikePay then
        return false, "STRIKE_FUND_DEPLETED"
    end

    local lastClaim = 0
    if membership.last_strike_pay_at then
        lastClaim = os.time({
            year = tonumber(membership.last_strike_pay_at:sub(1,4)),
            month = tonumber(membership.last_strike_pay_at:sub(6,7)),
            day = tonumber(membership.last_strike_pay_at:sub(9,10)),
            hour = tonumber(membership.last_strike_pay_at:sub(12,13)) or 0,
            min = tonumber(membership.last_strike_pay_at:sub(15,16)) or 0,
            sec = tonumber(membership.last_strike_pay_at:sub(18,19)) or 0
        })
    end

    local canClaim, remSeconds = Nyx.Unions.CanClaimStrikePay(lastClaim, os.time(), Config.Unions.StrikePayCooldownSeconds or 86400)
    if not canClaim then
        return false, string.format("STRIKE_PAY_COOLDOWN_ACTIVE_%d_SEC", remSeconds)
    end

    -- Closed-loop treasury disbursement from union treasury to member wallet
    local unionAcc = union.treasury_account_id or union.union_id
    local memberAcc = string.format("char:%s:bank", player.citizenId)

    local ok, txId = exports['nyx_treasury']:ExecuteTransfer(
        unionAcc,
        memberAcc,
        strikePay,
        "strike_relief_disbursement",
        unionAcc,
        string.format("Daily Strike Relief Stipend (%s)", union.legal_name),
        0.0
    )

    if not ok then
        return false, "TREASURY_TRANSFER_FAILED"
    end

    MySQL.prepare.await([[
        UPDATE `nyx_factions_unions`
        SET `strike_fund_balance` = `strike_fund_balance` - ?
        WHERE `union_id` = ?
    ]], { strikePay, unionId })

    MySQL.prepare.await([[
        UPDATE `nyx_factions_union_members`
        SET `last_strike_pay_at` = CURRENT_TIMESTAMP
        WHERE `union_id` = ? AND `citizen_id` = ?
    ]], { unionId, player.citizenId })

    return true, {
        stipendPaid = strikePay,
        newStrikeFundBalance = balance - strikePay,
        txId = txId
    }
end

-- 9. Deposit into Union Strike Fund
function Nyx.Factions.DepositStrikeFund(src, unionId, amount)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local deposit = math.max(1.0, math.floor((tonumber(amount) or 0.0) * 100) / 100)
    local union = MySQL.single.await([[
        SELECT * FROM `nyx_factions_unions` WHERE `union_id` = ?
    ]], { unionId })

    if not union then return false, "UNION_NOT_FOUND" end

    local playerAcc = string.format("char:%s:bank", player.citizenId)
    local unionAcc = union.treasury_account_id or union.union_id

    local ok, txId = exports['nyx_treasury']:ExecuteTransfer(
        playerAcc,
        unionAcc,
        deposit,
        "strike_fund_donation",
        playerAcc,
        string.format("Strike Fund Contribution to %s", union.legal_name),
        0.0
    )

    if not ok then
        return false, "INSUFFICIENT_FUNDS"
    end

    MySQL.prepare.await([[
        UPDATE `nyx_factions_unions`
        SET `strike_fund_balance` = `strike_fund_balance` + ?
        WHERE `union_id` = ?
    ]], { deposit, unionId })

    return true, {
        deposited = deposit,
        newBalance = (tonumber(union.strike_fund_balance) or 0.0) + deposit,
        txId = txId
    }
end
