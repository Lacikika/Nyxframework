--[[
    Nyxframework: nyx_factions
    File: server/cba.lua
    Description: Authoritative Collective Bargaining Agreements (CBAs), democratic strike authorization,
                 state bag synchronization, industrial picket line interlocks, and binding arbitration.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}
Nyx.Factions.ActiveStrikes = {}

-- Utility: Generate UUID for CBAs and Strikes
local function generateUUID()
    if Nyx.RPC and Nyx.RPC.GenerateNonce then
        return Nyx.RPC.GenerateNonce()
    end
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format("%x", v)
    end)
end

-- Synchronize OneSync State Bag for all clients
local function syncActiveStrikesStateBag()
    GlobalState.activeStrikes = Nyx.Factions.ActiveStrikes
end

-- 1. Initialize Active Strikes on Boot
CreateThread(function()
    Wait(1000)
    local strikes = MySQL.query.await([[
        SELECT * FROM `nyx_factions_strikes` WHERE `status` = 'active'
    ]])
    if strikes then
        for _, s in ipairs(strikes) do
            Nyx.Factions.ActiveStrikes[s.enterprise_faction_id] = {
                strikeId = s.strike_id,
                unionId = s.union_id,
                enterpriseFactionId = s.enterprise_faction_id,
                reason = s.reason,
                startedAt = s.started_at
            }
        end
        syncActiveStrikesStateBag()
        if Config.Debug then
            print(string.format("^3[Nyx:Factions] Loaded %d active industrial strikes into GlobalState.^7", #strikes))
        end
    end
end)

-- 2. Propose a Collective Bargaining Agreement (CBA)
function Nyx.Factions.ProposeCBA(src, unionId, enterpriseFactionId, title, wageFloor, overtimeMultiplier, hazardBonus)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    -- Verify caller is union steward or delegate
    local member = MySQL.single.await([[
        SELECT * FROM `nyx_factions_union_members`
        WHERE `union_id` = ? AND `citizen_id` = ? AND `role` IN ('steward', 'delegate')
    ]], { unionId, player.citizenId })

    if not member then
        return false, "UNAUTHORIZED_NOT_UNION_LEADER"
    end

    local enterprise = Nyx.Factions.GetFaction(enterpriseFactionId)
    if not enterprise then
        return false, "ENTERPRISE_NOT_FOUND"
    end

    local cbaId = generateUUID()
    local floor = math.max(10.0, math.floor((tonumber(wageFloor) or 35.00) * 100) / 100)
    local otMult = math.max(1.0, math.min(3.0, tonumber(overtimeMultiplier) or 1.50))
    local hazard = math.max(0.0, math.floor((tonumber(hazardBonus) or 15.00) * 100) / 100)

    local ok = MySQL.prepare.await([[
        INSERT INTO `nyx_factions_cba`
            (`cba_id`, `union_id`, `enterprise_faction_id`, `cba_title`, `wage_floor`,
             `overtime_multiplier`, `hazard_pay_bonus`, `status`, `created_by`)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'proposed', ?)
    ]], {
        cbaId,
        unionId,
        enterpriseFactionId,
        title or "Collective Bargaining Agreement",
        floor,
        otMult,
        hazard,
        player.citizenId
    })

    if not ok then return false, "DATABASE_ERROR" end

    TriggerClientEvent("nyx:factions:client:cbaUpdated", -1, {
        cbaId = cbaId,
        unionId = unionId,
        enterpriseFactionId = enterpriseFactionId,
        status = "proposed"
    })

    return true, {
        cbaId = cbaId,
        unionId = unionId,
        enterpriseFactionId = enterpriseFactionId,
        wageFloor = floor,
        overtimeMultiplier = otMult,
        hazardBonus = hazard,
        status = "proposed"
    }
end

-- 3. Ratify a Collective Bargaining Agreement
function Nyx.Factions.RatifyCBA(src, cbaId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local cba = MySQL.single.await([[
        SELECT * FROM `nyx_factions_cba` WHERE `cba_id` = ? AND `status` = 'proposed'
    ]], { cbaId })

    if not cba then return false, "CBA_NOT_FOUND_OR_NOT_PROPOSED" end

    -- Verify that signer is authorized executive of the enterprise
    local isExec = Nyx.Factions.HasPermission(player.citizenId, cba.enterprise_faction_id, "treasury:manage_rules")
    if not isExec and not Nyx.Factions.HasPermission(player.citizenId, cba.enterprise_faction_id, "*") then
        return false, "UNAUTHORIZED_NOT_ENTERPRISE_EXECUTIVE"
    end

    MySQL.prepare.await([[
        UPDATE `nyx_factions_cba`
        SET `status` = 'ratified',
            `ratified_at` = CURRENT_TIMESTAMP,
            `expires_at` = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 30 DAY),
            `ratified_by_enterprise` = ?
        WHERE `cba_id` = ?
    ]], { player.citizenId, cbaId })

    -- If there was an active strike against this enterprise, settle it upon ratification
    if Nyx.Factions.ActiveStrikes[cba.enterprise_faction_id] then
        Nyx.Factions.EndStrike(Nyx.Factions.ActiveStrikes[cba.enterprise_faction_id].strikeId, "CBA_RATIFIED")
    end

    TriggerClientEvent("nyx:factions:client:cbaUpdated", -1, {
        cbaId = cbaId,
        unionId = cba.union_id,
        enterpriseFactionId = cba.enterprise_faction_id,
        status = "ratified"
    })

    return true, {
        cbaId = cbaId,
        status = "ratified",
        ratifiedBy = player.citizenId
    }
end

-- 4. Query active CBA for an enterprise
function Nyx.Factions.GetEnterpriseCBA(enterpriseFactionId)
    local row = MySQL.single.await([[
        SELECT * FROM `nyx_factions_cba`
        WHERE `enterprise_faction_id` = ? AND `status` = 'ratified' AND (`expires_at` IS NULL OR `expires_at` > CURRENT_TIMESTAMP)
        ORDER BY `ratified_at` DESC LIMIT 1
    ]], { enterpriseFactionId })
    return row
end

-- 5. Call a Democratic Strike Authorization Vote
function Nyx.Factions.CallStrikeVote(src, unionId, enterpriseFactionId, reason)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    -- Must be union steward or delegate
    local leader = MySQL.single.await([[
        SELECT * FROM `nyx_factions_union_members`
        WHERE `union_id` = ? AND `citizen_id` = ? AND `role` IN ('steward', 'delegate')
    ]], { unionId, player.citizenId })

    if not leader then return false, "UNAUTHORIZED_NOT_UNION_LEADER" end

    -- Check if strike already active or voting
    local existing = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_factions_strikes`
        WHERE `enterprise_faction_id` = ? AND `status` IN ('voting', 'active')
    ]], { enterpriseFactionId })

    if existing and existing > 0 then
        return false, "STRIKE_ALREADY_IN_PROGRESS_OR_VOTING"
    end

    local strikeId = generateUUID()
    local cba = Nyx.Factions.GetEnterpriseCBA(enterpriseFactionId)

    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_strikes`
            (`strike_id`, `union_id`, `enterprise_faction_id`, `cba_id`, `reason`, `status`, `voting_deadline`)
        VALUES (?, ?, ?, ?, ?, 'voting', DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 24 HOUR))
    ]], {
        strikeId,
        unionId,
        enterpriseFactionId,
        cba and cba.cba_id or nil,
        reason or "CBA Wage Breach & Unfair Labor Practices"
    })

    -- Auto-cast Yes vote for initiating leader
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_strike_votes` (`strike_id`, `citizen_id`, `vote`)
        VALUES (?, ?, 'yes')
    ]], { strikeId, player.citizenId })

    TriggerClientEvent("nyx:factions:client:strikeVoteStarted", -1, {
        strikeId = strikeId,
        unionId = unionId,
        enterpriseFactionId = enterpriseFactionId,
        reason = reason
    })

    return true, {
        strikeId = strikeId,
        status = "voting"
    }
end

-- 6. Cast Ballot in Strike Authorization Vote
function Nyx.Factions.CastStrikeVote(src, strikeId, vote)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local strike = MySQL.single.await([[
        SELECT * FROM `nyx_factions_strikes` WHERE `strike_id` = ? AND `status` = 'voting'
    ]], { strikeId })

    if not strike then return false, "STRIKE_NOT_IN_VOTING" end

    -- Verify voter is union member employed at this enterprise
    local member = MySQL.single.await([[
        SELECT * FROM `nyx_factions_union_members`
        WHERE `union_id` = ? AND `citizen_id` = ?
    ]], { strike.union_id, player.citizenId })

    if not member then return false, "NOT_UNION_MEMBER" end

    local v = string.lower(tostring(vote or "abstain"))
    if v ~= "yes" and v ~= "no" then v = "abstain" end

    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_strike_votes` (`strike_id`, `citizen_id`, `vote`)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE `vote` = VALUES(`vote`), `voted_at` = CURRENT_TIMESTAMP
    ]], { strikeId, player.citizenId, v })

    -- Count total eligible union members for this enterprise
    local eligibleCount = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_factions_union_members`
        WHERE `union_id` = ? AND (`enterprise_faction_id` = ? OR `enterprise_faction_id` IS NULL)
    ]], { strike.union_id, strike.enterprise_faction_id }) or 1

    local votes = MySQL.query.await([[
        SELECT `vote` FROM `nyx_factions_strike_votes` WHERE `strike_id` = ?
    ]], { strikeId }) or {}

    local result = Nyx.Unions.EvaluateStrikeVote(
        eligibleCount,
        votes,
        Config.Unions.StrikeVoteQuorumPct or 0.50,
        Config.Unions.StrikeVoteMajorityPct or 0.50
    )

    if result.passed then
        -- Declare Active Strike
        MySQL.prepare.await([[
            UPDATE `nyx_factions_strikes`
            SET `status` = 'active',
                `vote_passed_ratio` = ?,
                `started_at` = CURRENT_TIMESTAMP
            WHERE `strike_id` = ?
        ]], { (result.yes_count / math.max(1, result.total_cast)) * 100, strikeId })

        Nyx.Factions.ActiveStrikes[strike.enterprise_faction_id] = {
            strikeId = strikeId,
            unionId = strike.union_id,
            enterpriseFactionId = strike.enterprise_faction_id,
            reason = strike.reason,
            startedAt = os.date("%Y-%m-%d %H:%M:%S")
        }
        syncActiveStrikesStateBag()

        TriggerClientEvent("nyx:factions:client:strikeDeclared", -1, {
            strikeId = strikeId,
            unionId = strike.union_id,
            enterpriseFactionId = strike.enterprise_faction_id,
            reason = strike.reason
        })

        print(string.format("^1[Nyx:Factions] STRIKE DECLARED: %s against %s (Quorum: %d/%d, Yes: %d)^7",
            strike.union_id, strike.enterprise_faction_id, result.total_cast, result.eligible, result.yes_count))
    end

    return true, {
        strikeId = strikeId,
        yourVote = v,
        passed = result.passed,
        totalCast = result.total_cast,
        yesCount = result.yes_count
    }
end

-- 7. Query if an enterprise is on active strike
function Nyx.Factions.IsEnterpriseOnStrike(enterpriseFactionId)
    if not enterpriseFactionId then return false end
    return (Nyx.Factions.ActiveStrikes[enterpriseFactionId] ~= nil)
end

-- 8. End / Settle an industrial strike
function Nyx.Factions.EndStrike(strikeId, resolutionReason)
    local strike = MySQL.single.await([[
        SELECT * FROM `nyx_factions_strikes` WHERE `strike_id` = ?
    ]], { strikeId })

    if not strike then return false, "STRIKE_NOT_FOUND" end

    MySQL.prepare.await([[
        UPDATE `nyx_factions_strikes`
        SET `status` = 'settled',
            `ended_at` = CURRENT_TIMESTAMP
        WHERE `strike_id` = ?
    ]], { strikeId })

    Nyx.Factions.ActiveStrikes[strike.enterprise_faction_id] = nil
    syncActiveStrikesStateBag()

    TriggerClientEvent("nyx:factions:client:strikeEnded", -1, {
        strikeId = strikeId,
        enterpriseFactionId = strike.enterprise_faction_id,
        reason = resolutionReason or "SETTLED"
    })

    return true
end

-- 9. Petition Binding Labor Arbitration
function Nyx.Factions.PetitionLaborArbitration(src, strikeId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local strike = MySQL.single.await([[
        SELECT * FROM `nyx_factions_strikes` WHERE `strike_id` = ?
    ]], { strikeId })

    if not strike then return false, "STRIKE_NOT_FOUND" end

    -- Verify caller is either union steward or enterprise executive
    local isUnionSteward = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_factions_union_members`
        WHERE `union_id` = ? AND `citizen_id` = ? AND `role` IN ('steward', 'delegate')
    ]], { strike.union_id, player.citizenId }) or 0

    local isEnterpriseExec = Nyx.Factions.HasPermission(player.citizenId, strike.enterprise_faction_id, "treasury:manage_rules")

    if isUnionSteward == 0 and not isEnterpriseExec then
        return false, "UNAUTHORIZED_PETITIONER"
    end

    MySQL.prepare.await([[
        UPDATE `nyx_factions_strikes`
        SET `status` = 'arbitration'
        WHERE `strike_id` = ?
    ]], { strikeId })

    -- Open judicial docket in nyx_judiciary if available
    local docketId = nil
    if exports['nyx_judiciary'] and exports['nyx_judiciary'].FileDocket then
        local dOk, dRes = pcall(function()
            return exports['nyx_judiciary']:FileDocket(
                player.citizenId,
                string.format("Labor Dispute & Binding Arbitration: %s vs %s", strike.union_id, strike.enterprise_faction_id),
                "labor_arbitration",
                strike.enterprise_faction_id,
                strike.reason
            )
        end)
        if dOk and dRes then docketId = dRes end
    end

    return true, {
        strikeId = strikeId,
        status = "arbitration",
        docketId = docketId
    }
end

-- 10. Execute Binding Labor Arbitration Award
function Nyx.Factions.ExecuteArbitrationAward(arbitratorCitId, strikeId, underpaidHours, hourlyDeficit, penaltyRate, revisedWageFloor)
    local strike = MySQL.single.await([[
        SELECT * FROM `nyx_factions_strikes` WHERE `strike_id` = ?
    ]], { strikeId })

    if not strike then return false, "STRIKE_NOT_FOUND" end

    local members = MySQL.query.await([[
        SELECT `citizen_id` FROM `nyx_factions_union_members`
        WHERE `union_id` = ? AND (`enterprise_faction_id` = ? OR `enterprise_faction_id` IS NULL)
    ]], { strike.union_id, strike.enterprise_faction_id }) or {}

    local memberCount = math.max(1, #members)
    local award = Nyx.Unions.CalculateArbitrationAward(
        underpaidHours,
        hourlyDeficit,
        memberCount,
        penaltyRate or Config.Unions.ArbitrationStatutoryPenaltyRate or 0.10
    )

    local enterpriseAcc = string.format("faction:%s", strike.enterprise_faction_id)
    local unionAcc = strike.union_id
    local awardId = generateUUID()

    -- Closed-loop double-entry execution via nyx_treasury
    local enterpriseBal = exports['nyx_treasury']:GetAccountBalance(enterpriseAcc) or 0.00
    if enterpriseBal < award.total_award then
        -- Default or seize from sub-vaults
        print(string.format("^1[Nyx:Factions] ARBITRATION SEIZURE: Enterprise %s deficit (Balance: $%.2f, Required: $%.2f)^7",
            strike.enterprise_faction_id, enterpriseBal, award.total_award))
    end

    -- Step 1: Disburse per-member restitution directly to member wallets
    for _, m in ipairs(members) do
        local memberAcc = string.format("char:%s:bank", m.citizen_id)
        exports['nyx_treasury']:ExecuteTransfer(
            enterpriseAcc,
            memberAcc,
            award.per_member_restitution,
            "arbitration_restitution",
            enterpriseAcc,
            string.format("Judicial Arbitration Restitution Award (Case %s)", strikeId:sub(1,8)),
            0.0
        )
    end

    -- Step 2: Transfer statutory penalty to union treasury fund
    if award.statutory_penalty > 0.00 then
        exports['nyx_treasury']:ExecuteTransfer(
            enterpriseAcc,
            unionAcc,
            award.statutory_penalty,
            "arbitration_statutory_penalty",
            enterpriseAcc,
            string.format("Judicial Statutory Penalty against %s", strike.enterprise_faction_id),
            0.0
        )
    end

    -- Step 3: Record arbitration award
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_arbitration_awards`
            (`award_id`, `strike_id`, `cba_id`, `arbitrator_citizen_id`, `union_id`, `enterprise_faction_id`,
             `restitution_damages`, `statutory_penalty`, `revised_wage_floor`, `award_summary`, `settlement_status`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'settled')
    ]], {
        awardId,
        strikeId,
        strike.cba_id or nil,
        arbitratorCitId or "JUDICIAL_ARBITRATOR",
        strike.union_id,
        strike.enterprise_faction_id,
        award.total_restitution,
        award.statutory_penalty,
        revisedWageFloor or 0.00,
        string.format("Binding Arbitration: %d workers compensated, $%.2f restitution + $%.2f statutory penalty",
            memberCount, award.total_restitution, award.statutory_penalty)
    })

    -- Step 4: If revised wage floor supplied, update CBA
    if revisedWageFloor and revisedWageFloor > 0.00 and strike.cba_id then
        MySQL.prepare.await([[
            UPDATE `nyx_factions_cba`
            SET `wage_floor` = ?, `status` = 'ratified'
            WHERE `cba_id` = ?
        ]], { revisedWageFloor, strike.cba_id })
    end

    -- Step 5: Settle strike and restore operations
    Nyx.Factions.EndStrike(strikeId, "ARBITRATION_AWARD_SETTLED")

    return true, {
        awardId = awardId,
        totalAward = award.total_award,
        restitutionPerMember = award.per_member_restitution,
        statutoryPenalty = award.statutory_penalty,
        membersCompensated = memberCount
    }
end
