--[[
    Nyxframework: nyx_factions
    File: server/inactivity.lua
    Description: Authoritative Organization Founder Inactivity, Succession & Charter Liquidation.
                 Monitors founder presence, promotes active shareholders upon abandonment,
                 or liquidates corporate charters with 100% closed-loop double-entry treasury conservation.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}

-- 1. Set Stewardship Delegate for a Faction
function Nyx.Factions.SetFactionStewardDelegate(src, factionId, delegateCitizenId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local faction = MySQL.single.await([[
        SELECT `faction_id`, `legal_name`, `founder_citizen_id`, `treasury_account_id`
        FROM `nyx_factions_registry`
        WHERE `faction_id` = ? AND `is_active` = 1
    ]], { factionId })

    if not faction then return false, "FACTION_NOT_FOUND" end

    -- Verify actor is the registered founder or has top governance permission
    local isFounder = (faction.founder_citizen_id == player.citizenId)
    local hasPerm = Nyx.Factions.HasPermission and Nyx.Factions.HasPermission(player.citizenId, factionId, "governance:call_vote")
    if not isFounder and not hasPerm then
        return false, "UNAUTHORIZED_NOT_FOUNDER_OR_EXECUTIVE"
    end

    if delegateCitizenId then
        -- Verify target delegate citizen exists
        local delChar = MySQL.single.await([[
            SELECT `citizen_id`, `first_name`, `last_name`
            FROM `nyx_characters`
            WHERE `citizen_id` = ? AND `deleted_at` IS NULL
        ]], { delegateCitizenId })

        if not delChar then
            return false, "DELEGATE_CITIZEN_NOT_FOUND"
        end

        -- Record proxy authorization in nyx_stewardship_delegates
        MySQL.prepare.await([[
            INSERT INTO `nyx_stewardship_delegates`
                (`owner_citizen_id`, `delegate_citizen_id`, `scope`, `is_active`, `authorized_at`, `notes`)
            VALUES (?, ?, 'factions', 1, NOW(), ?)
            ON DUPLICATE KEY UPDATE
                `is_active` = 1,
                `revoked_at` = NULL,
                `authorized_at` = NOW()
        ]], { player.citizenId, delegateCitizenId, string.format("Faction proxy for %s", faction.legal_name) })
    end

    MySQL.prepare.await([[
        UPDATE `nyx_factions_registry`
        SET `steward_delegate_citizen_id` = ?,
            `inactivity_status` = ?
        WHERE `faction_id` = ?
    ]], { delegateCitizenId, delegateCitizenId and "delegated" or "active", factionId })

    return true, {
        factionId = factionId,
        stewardCitizenId = delegateCitizenId,
        status = delegateCitizenId and "delegated" or "active"
    }
end

-- 2. Authoritative Faction Inactivity & Succession Sweeper
function Nyx.Factions.CheckFactionInactivity()
    local now = os.time()
    local cfg = Config.Succession or Nyx.Succession.Defaults

    local factions = MySQL.query.await([[
        SELECT f.`faction_id`, f.`legal_name`, f.`founder_citizen_id`, f.`steward_delegate_citizen_id`,
               f.`treasury_account_id`, f.`inactivity_status`,
               UNIX_TIMESTAMP(f.`inactivity_warning_at`) AS `warning_at_unix`,
               UNIX_TIMESTAMP(c.`last_active_at`) AS `founder_last_active_unix`,
               UNIX_TIMESTAMP(d.`last_active_at`) AS `delegate_last_active_unix`
        FROM `nyx_factions_registry` f
        LEFT JOIN `nyx_characters` c ON c.`citizen_id` = f.`founder_citizen_id`
        LEFT JOIN `nyx_characters` d ON d.`citizen_id` = f.`steward_delegate_citizen_id`
        WHERE f.`is_active` = 1 AND f.`founder_citizen_id` IS NOT NULL
    ]])

    if not factions or #factions == 0 then return { processed = 0, successions = 0, liquidations = 0 } end

    local successionCount = 0
    local liquidationCount = 0
    local warningCount = 0

    for _, f in ipairs(factions) do
        local factionId = f.faction_id
        local eval = Nyx.Succession.EvaluateFounderStatus(
            now,
            f.founder_last_active_unix,
            f.steward_delegate_citizen_id,
            f.delegate_last_active_unix,
            f.warning_at_unix,
            cfg
        )

        if eval.status == "active" or eval.status == "delegated" then
            if f.inactivity_status == "grace_period" or f.warning_at_unix ~= nil then
                MySQL.prepare.await([[
                    UPDATE `nyx_factions_registry`
                    SET `inactivity_status` = ?,
                        `inactivity_warning_at` = NULL
                    WHERE `faction_id` = ?
                ]], { eval.status, factionId })

                MySQL.prepare([[
                    INSERT INTO `nyx_inactivity_reclamation_logs`
                        (`asset_type`, `asset_id`, `previous_owner_citizen_id`, `delegate_citizen_id`, `action`, `notes`)
                    VALUES ('faction_charter', ?, ?, ?, 'warning_cleared', ?)
                ]], {
                    factionId,
                    f.founder_citizen_id,
                    f.steward_delegate_citizen_id,
                    string.format("Faction inactivity warning cleared: %s", eval.reason)
                })
            end
        elseif eval.status == "grace_period" then
            if eval.needsWarning or f.inactivity_status ~= "grace_period" then
                warningCount = warningCount + 1
                MySQL.prepare.await([[
                    UPDATE `nyx_factions_registry`
                    SET `inactivity_status` = 'grace_period',
                        `inactivity_warning_at` = FROM_UNIXTIME(?)
                    WHERE `faction_id` = ?
                ]], { now, factionId })

                MySQL.prepare([[
                    INSERT INTO `nyx_inactivity_reclamation_logs`
                        (`asset_type`, `asset_id`, `previous_owner_citizen_id`, `delegate_citizen_id`, `action`, `notes`)
                    VALUES ('faction_charter', ?, ?, ?, 'warning_issued', ?)
                ]], {
                    factionId,
                    f.founder_citizen_id,
                    f.steward_delegate_citizen_id,
                    string.format("72-hour grace period warning issued for enterprise '%s'", f.legal_name)
                })

                -- Alert online members
                local members = MySQL.query.await([[
                    SELECT `citizen_id` FROM `nyx_factions_members` WHERE `faction_id` = ?
                ]], { factionId }) or {}
                for _, m in ipairs(members) do
                    local ply = Nyx.GetPlayerByCitizenId(m.citizen_id)
                    if ply then
                        TriggerClientEvent("nyx:ui:notify", ply.source, {
                            type = "warning",
                            title = "VÁLLALATI INAKTIVITÁSI FIGYELMEZTETÉS",
                            message = string.format("A(z) %s alapítója inaktív! 72 órán belül öröklési eljárás vagy felszámolás indul.", f.legal_name)
                        })
                    end
                end
            end
        elseif eval.status == "actionable" then
            -- Grace period expired: determine successor or execute charter liquidation
            local members = MySQL.query.await([[
                SELECT m.`citizen_id`, m.`role_title`, m.`equity_shares`, m.`wage_hourly`,
                       UNIX_TIMESTAMP(m.`hired_at`) AS `hired_at_unix`,
                       UNIX_TIMESTAMP(c.`last_active_at`) AS `last_active_at`
                FROM `nyx_factions_members` m
                INNER JOIN `nyx_characters` c ON c.`citizen_id` = m.`citizen_id`
                WHERE m.`faction_id` = ?
            ]], { factionId }) or {}

            local outcome, successor, reason = Nyx.Succession.DetermineSuccessor(
                members,
                f.founder_citizen_id,
                now,
                cfg.FounderInactivityThresholdSeconds
            )

            if outcome == "succession" and successor then
                -- Case 1: Active shareholder elected to succeed founder
                successionCount = successionCount + 1
                MySQL.prepare.await([[
                    UPDATE `nyx_factions_registry`
                    SET `founder_citizen_id` = ?,
                        `steward_delegate_citizen_id` = NULL,
                        `inactivity_status` = 'active',
                        `inactivity_warning_at` = NULL
                    WHERE `faction_id` = ?
                ]], { successor.citizenId, factionId })

                MySQL.prepare.await([[
                    UPDATE `nyx_factions_members`
                    SET `role_title` = 'Chief Executive Officer'
                    WHERE `faction_id` = ? AND `citizen_id` = ?
                ]], { factionId, successor.citizenId })

                MySQL.prepare([[
                    INSERT INTO `nyx_inactivity_reclamation_logs`
                        (`asset_type`, `asset_id`, `previous_owner_citizen_id`, `action`, `notes`)
                    VALUES ('faction_charter', ?, ?, 'succession_executed', ?)
                ]], {
                    factionId,
                    f.founder_citizen_id,
                    string.format("Succession executed: Citizen %s assumed leadership of %s (Equity: %.2f%%)",
                        successor.citizenId, f.legal_name, successor.equityShares or 0.0)
                })

                -- Global broadcast of corporate succession
                TriggerClientEvent("nyx:ui:notify", -1, {
                    type = "info",
                    title = "VÁLLALATI VEZETŐVÁLTÁS",
                    message = string.format("A(z) %s új ügyvezetője: %s (Részvényarány: %.1f%%).",
                        f.legal_name, successor.citizenId, successor.equityShares or 0.0)
                })
            else
                -- Case 2: Complete abandonment -> Liquidate charter & sweep treasury balance
                liquidationCount = liquidationCount + 1
                local treasuryAcc = f.treasury_account_id or ("org:" .. factionId)
                local balance = exports['nyx_treasury']:GetAccountBalance(treasuryAcc) or 0.00

                local dist = Nyx.Succession.CalculateCharterLiquidationDistribution(balance, cfg.MunicipalMasterSplitRatio)
                local txUuid = nil

                if dist.totalLiquidated > 0.00 then
                    -- Execute closed-loop double-entry transfers
                    local okMaster, txId1 = exports['nyx_treasury']:ExecuteTransfer(
                        treasuryAcc,
                        "gov:city:master",
                        dist.masterAmount,
                        "charter_liquidation",
                        "faction:" .. factionId,
                        string.format("Abandoned Charter Liquidation (Master Reserve: %s)", f.legal_name),
                        0.0
                    )
                    local okWorks, txId2 = exports['nyx_treasury']:ExecuteTransfer(
                        treasuryAcc,
                        "gov:dept:works",
                        dist.worksAmount,
                        "charter_liquidation",
                        "faction:" .. factionId,
                        string.format("Abandoned Charter Liquidation (Public Works: %s)", f.legal_name),
                        0.0
                    )
                    txUuid = tostring(txId1)
                end

                MySQL.prepare.await([[
                    UPDATE `nyx_factions_registry`
                    SET `is_active` = 0,
                        `inactivity_status` = 'liquidated',
                        `liquidated_at` = NOW()
                    WHERE `faction_id` = ?
                ]], { factionId })

                MySQL.prepare([[
                    INSERT INTO `nyx_inactivity_reclamation_logs`
                        (`asset_type`, `asset_id`, `previous_owner_citizen_id`, `action`, `liquidated_funds`, `treasury_tx_uuid`, `notes`)
                    VALUES ('faction_charter', ?, ?, 'charter_liquidated', ?, ?, ?)
                ]], {
                    factionId,
                    f.founder_citizen_id,
                    dist.totalLiquidated,
                    txUuid,
                    string.format("Abandoned charter revoked: $%.2f liquidated into municipal treasury (Master: $%.2f, Works: $%.2f)",
                        dist.totalLiquidated, dist.masterAmount, dist.worksAmount)
                })

                -- Global announcement of charter dissolution
                TriggerClientEvent("nyx:ui:notify", -1, {
                    type = "warning",
                    title = "VÁLLALAT FELSZÁMOLVA",
                    message = string.format("A(z) %s inaktivitás miatt megszűnt. Kincstári maradvány ($%.2f) a városi alapba került.",
                        f.legal_name, dist.totalLiquidated)
                })
            end
        end
    end

    if Config.Debug then
        print(string.format("^2[Nyx:Factions:Inactivity]^7 Sweeper complete: %d checked, %d warnings, %d successions, %d liquidations.^7",
            #factions, warningCount, successionCount, liquidationCount))
    end

    return {
        processed = #factions,
        warnings = warningCount,
        successions = successionCount,
        liquidations = liquidationCount
    }
end

-- ============================================================================
-- RPC Registration
-- ============================================================================

Nyx.RPC.Register("factions:setFactionStewardDelegate", function(src, payload)
    local factionId = payload and payload.factionId
    local delegateCitizenId = payload and payload.delegateCitizenId
    return Nyx.Factions.SetFactionStewardDelegate(src, factionId, delegateCitizenId)
end)

Nyx.RPC.Register("factions:getFactionInactivityStatus", function(src, factionId)
    local faction = MySQL.single.await([[
        SELECT `faction_id`, `legal_name`, `founder_citizen_id`, `steward_delegate_citizen_id`,
               `inactivity_status`, `inactivity_warning_at`, `is_active`
        FROM `nyx_factions_registry`
        WHERE `faction_id` = ?
    ]], { factionId })
    return faction
end)
