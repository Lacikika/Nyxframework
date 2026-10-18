--[[
    Nyxframework: nyx_factions
    File: server/multisig.lua
    Description: Multi-signature corporate treasury vaults, dynamic sign-off rules engine,
                 timelock execution escrow, and immutable cryptographic audit logging.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}

-- Utility: Generate UUIDv4
local function generateUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

-- Utility: Parse timestamp string to Unix epoch
local function parseTimestamp(str)
    if not str then return 0 end
    local pyear, pmonth, pday, phour, pmin, psec = string.match(tostring(str), "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    if pyear then
        return os.time({
            year = tonumber(pyear),
            month = tonumber(pmonth),
            day = tonumber(pday),
            hour = tonumber(phour),
            min = tonumber(pmin),
            sec = tonumber(psec)
        })
    end
    return 0
end

-- ============================================================================
-- 1. Sign-Off Rules Management & Matching Engine
-- ============================================================================

-- Query active sign-off rules for a faction
function Nyx.Factions.GetSignoffRules(factionId, vaultId)
    if not factionId then return {} end

    local query = [[
        SELECT * FROM `nyx_factions_signoff_rules`
        WHERE `faction_id` = ? AND `is_active` = 1
    ]]
    local params = { factionId }

    if vaultId then
        query = query .. " AND (`vault_id` = ? OR `vault_id` IS NULL)"
        table.insert(params, vaultId)
    end

    query = query .. " ORDER BY (`vault_id` IS NOT NULL) DESC, `priority` DESC, `min_amount` DESC"

    local rows = MySQL.query.await(query, params)
    local rules = {}

    for _, row in ipairs(rows or {}) do
        local requiredRoles = nil
        if row.required_roles then
            if type(row.required_roles) == "string" then
                local ok, parsed = pcall(json.decode, row.required_roles)
                if ok and type(parsed) == "table" then requiredRoles = parsed end
            elseif type(row.required_roles) == "table" then
                requiredRoles = row.required_roles
            end
        end

        table.insert(rules, {
            ruleId = row.rule_id,
            factionId = row.faction_id,
            vaultId = row.vault_id,
            ruleName = row.rule_name,
            minAmount = tonumber(row.min_amount) or 0.00,
            maxAmount = row.max_amount and tonumber(row.max_amount) or nil,
            requiredSignatures = tonumber(row.required_signatures) or 2,
            requiredRoles = requiredRoles,
            timelockSeconds = tonumber(row.timelock_seconds) or 0,
            priority = tonumber(row.priority) or 0,
            isActive = (row.is_active == 1),
            createdAt = row.created_at
        })
    end

    return rules
end

-- Match an incoming withdrawal to the most specific and highest priority sign-off rule
function Nyx.Factions.EvaluateSignoffRule(factionId, vaultId, amount)
    local amt = tonumber(amount) or 0.00
    local rules = Nyx.Factions.GetSignoffRules(factionId, vaultId)

    for _, rule in ipairs(rules) do
        local matchesMin = (amt >= rule.minAmount)
        local matchesMax = (rule.maxAmount == nil or amt <= rule.maxAmount)

        if matchesMin and matchesMax then
            return rule
        end
    end

    -- Fallback: Use standard faction registry threshold
    local faction = Nyx.Factions.GetFaction(factionId)
    local threshold = faction and tonumber(faction.multisig_threshold_amount) or 50000.00
    local reqSigs = faction and tonumber(faction.multisig_required_signatures) or 2

    if amt <= threshold then
        return {
            ruleId = "default:direct",
            factionId = factionId,
            vaultId = vaultId,
            ruleName = "Default Direct Low-Tier Policy",
            minAmount = 0.00,
            maxAmount = threshold,
            requiredSignatures = 1,
            requiredRoles = nil,
            timelockSeconds = 0,
            isDirect = true
        }
    else
        return {
            ruleId = "default:multisig",
            factionId = factionId,
            vaultId = vaultId,
            ruleName = "Default Multi-Sig High-Tier Policy",
            minAmount = threshold,
            maxAmount = nil,
            requiredSignatures = reqSigs,
            requiredRoles = nil,
            timelockSeconds = 0,
            isDirect = false
        }
    end
end

-- Create or update a sign-off rule
function Nyx.Factions.SetSignoffRule(actorCitizenId, factionId, ruleData)
    if actorCitizenId ~= "SYSTEM" and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "treasury:manage_rules")
       and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "governance:call_vote") then
        return false, "INSUFFICIENT_PERMISSIONS_MANAGE_RULES"
    end

    if not ruleData or type(ruleData) ~= "table" then
        return false, "INVALID_RULE_DATA"
    end

    local ruleName = ruleData.ruleName or "Custom Sign-Off Rule"
    local minAmount = math.max(0.00, tonumber(ruleData.minAmount) or 0.00)
    local maxAmount = ruleData.maxAmount and tonumber(ruleData.maxAmount) or nil
    if maxAmount and maxAmount < minAmount then
        return false, "INVALID_AMOUNT_BOUNDARIES"
    end

    local reqSigs = math.max(1, tonumber(ruleData.requiredSignatures) or 2)
    local timelock = math.max(0, tonumber(ruleData.timelockSeconds) or 0)
    local priority = tonumber(ruleData.priority) or 0
    local vaultId = (ruleData.vaultId and ruleData.vaultId ~= "") and ruleData.vaultId or nil
    local ruleId = ruleData.ruleId or generateUUID()
    local reqRolesJson = ruleData.requiredRoles and json.encode(ruleData.requiredRoles) or nil

    local success = MySQL.prepare.await([[
        INSERT INTO `nyx_factions_signoff_rules`
            (`rule_id`, `faction_id`, `vault_id`, `rule_name`, `min_amount`, `max_amount`,
             `required_signatures`, `required_roles`, `timelock_seconds`, `priority`, `is_active`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
        ON DUPLICATE KEY UPDATE
            `vault_id` = VALUES(`vault_id`),
            `rule_name` = VALUES(`rule_name`),
            `min_amount` = VALUES(`min_amount`),
            `max_amount` = VALUES(`max_amount`),
            `required_signatures` = VALUES(`required_signatures`),
            `required_roles` = VALUES(`required_roles`),
            `timelock_seconds` = VALUES(`timelock_seconds`),
            `priority` = VALUES(`priority`),
            `is_active` = 1
    ]], {
        ruleId,
        factionId,
        vaultId,
        ruleName,
        minAmount,
        maxAmount,
        reqSigs,
        reqRolesJson,
        timelock,
        priority
    })

    if not success then
        return false, "DATABASE_ERROR"
    end

    -- Audit log
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_multisig_audit`
            (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
        VALUES (?, ?, ?, 'RULE_CONFIGURED', ?)
    ]], {
        ruleId,
        factionId,
        actorCitizenId,
        json.encode({ ruleName = ruleName, minAmount = minAmount, maxAmount = maxAmount, reqSigs = reqSigs, timelock = timelock })
    })

    return true, {
        ruleId = ruleId,
        factionId = factionId,
        vaultId = vaultId,
        ruleName = ruleName,
        minAmount = minAmount,
        maxAmount = maxAmount,
        requiredSignatures = reqSigs,
        timelockSeconds = timelock
    }
end

-- Deactivate a sign-off rule
function Nyx.Factions.DeleteSignoffRule(actorCitizenId, factionId, ruleId)
    if actorCitizenId ~= "SYSTEM" and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "treasury:manage_rules") then
        return false, "INSUFFICIENT_PERMISSIONS_MANAGE_RULES"
    end

    local affected = MySQL.update.await([[
        UPDATE `nyx_factions_signoff_rules`
        SET `is_active` = 0
        WHERE `rule_id` = ? AND `faction_id` = ?
    ]], { ruleId, factionId })

    if not affected or affected == 0 then
        return false, "RULE_NOT_FOUND"
    end

    -- Audit log
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_multisig_audit`
            (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
        VALUES (?, ?, ?, 'RULE_DEACTIVATED', ?)
    ]], {
        ruleId,
        factionId,
        actorCitizenId,
        json.encode({ ruleId = ruleId })
    })

    return true
end

-- ============================================================================
-- 2. Multi-Signature Withdrawal Queue & Lifecycle Handlers
-- ============================================================================

-- Check if a list of signatories satisfies the required roles
local function evaluateSignatoryRoles(signaturesDetails, requiredRoles)
    if not requiredRoles or #requiredRoles == 0 then
        return true
    end

    local presentRoles = {}
    for _, sig in ipairs(signaturesDetails or {}) do
        if sig.roleTitle then
            presentRoles[sig.roleTitle] = true
        end
    end

    for _, reqRole in ipairs(requiredRoles) do
        if not presentRoles[reqRole] then
            return false, reqRole
        end
    end

    return true
end

-- Initiate a corporate withdrawal (Direct or Multi-Sig queued with sign-off rule evaluation)
function Nyx.Factions.InitiateWithdrawal(src, factionId, vaultId, targetAccount, amount, reason)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local transferAmount = tonumber(amount) or 0.00
    if transferAmount <= 0.00 then
        return false, "INVALID_AMOUNT"
    end

    local faction = Nyx.Factions.GetFaction(factionId)
    if not faction then return false, "FACTION_NOT_FOUND" end

    -- Resolve Vault: If vaultId not passed or empty, default to primary vault
    local vault = nil
    if vaultId and vaultId ~= "" then
        vault = Nyx.Factions.GetVault(vaultId)
    else
        local primary = Nyx.Factions.EnsurePrimaryVault(factionId)
        if primary then
            vault = Nyx.Factions.GetVault(primary.vault_id)
        end
    end

    if not vault or vault.factionId ~= factionId then
        return false, "VAULT_NOT_FOUND"
    end

    -- Check Emergency Lockdown / Freeze
    if vault.isFrozen then
        return false, "VAULT_FROZEN"
    end

    -- Check Liquidity
    if vault.balance < transferAmount then
        return false, "INSUFFICIENT_VAULT_LIQUIDITY"
    end

    -- Check Rolling Daily Limit
    if (vault.dailyWithdrawn + transferAmount) > vault.dailyLimit then
        return false, "EXCEEDS_VAULT_DAILY_LIMIT"
    end

    -- Evaluate matching sign-off rule
    local matchedRule = Nyx.Factions.EvaluateSignoffRule(factionId, vault.vaultId, transferAmount)
    local requiredSigs = tonumber(matchedRule.requiredSignatures) or 2
    local timelockSeconds = tonumber(matchedRule.timelockSeconds) or 0

    -- Scenario A: Direct Single-Signer Withdrawal (Below Threshold / 1 Signature Required with 0 Timelock)
    if requiredSigs <= 1 and timelockSeconds == 0 then
        if not Nyx.Factions.HasPermission(player.citizenId, factionId, "treasury:withdraw_low")
           and not Nyx.Factions.HasPermission(player.citizenId, factionId, "treasury:withdraw_high") then
            return false, "INSUFFICIENT_PERMISSIONS_WITHDRAW_LOW"
        end

        local success, txId = exports['nyx_treasury']:ExecuteTransfer(
            vault.accountId,
            targetAccount,
            transferAmount,
            "faction_withdrawal",
            player.citizenId,
            reason or string.format("Direct Authorized Disbursement from %s", vault.vaultLabel),
            0.0
        )

        if success then
            -- Debit daily limit
            MySQL.prepare.await([[
                UPDATE `nyx_factions_vaults`
                SET `daily_withdrawn` = `daily_withdrawn` + ?
                WHERE `vault_id` = ?
            ]], { transferAmount, vault.vaultId })

            -- Audit log
            MySQL.prepare.await([[
                INSERT INTO `nyx_factions_multisig_audit`
                    (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
                VALUES (?, ?, ?, 'DIRECT_DISBURSED', ?)
            ]], {
                txId,
                factionId,
                player.citizenId,
                json.encode({
                    vaultId = vault.vaultId,
                    amount = transferAmount,
                    targetAccount = targetAccount,
                    ruleId = matchedRule.ruleId
                })
            })

            return true, "DISBURSED_DIRECT", { txId = txId, amount = transferAmount, vaultId = vault.vaultId }
        else
            return false, "TREASURY_TRANSFER_FAILED"
        end
    end

    -- Scenario B: Multi-Signature Quorum or Timelocked Disbursement Required
    if not Nyx.Factions.HasPermission(player.citizenId, factionId, "treasury:withdraw_high") then
        return false, "INSUFFICIENT_PERMISSIONS_WITHDRAW_HIGH"
    end

    local requestId = generateUUID()
    local currentSigs = {}
    local signatureDetails = {}

    -- Auto-sign if the initiator has signatory rights
    if Nyx.Factions.HasPermission(player.citizenId, factionId, "treasury:sign_tx") then
        local member = Nyx.Factions.GetMember(player.citizenId, factionId)
        local roleTitle = member and member.roleTitle or "Signatory"
        table.insert(currentSigs, player.citizenId)
        table.insert(signatureDetails, {
            citizenId = player.citizenId,
            roleTitle = roleTitle,
            signedAt = os.date("%Y-%m-%d %H:%M:%S"),
            note = "Initiator Authorizing Signature"
        })
    end

    local expireHours = Config.MultiSig and Config.MultiSig.RequestExpirationHours or 48
    local expireTime = os.date("%Y-%m-%d %H:%M:%S", os.time() + (expireHours * 3600))
    local initialStatus = "pending"
    local timelockUntil = nil

    local insertOk = MySQL.prepare.await([[
        INSERT INTO `nyx_factions_multisig_queue`
            (`request_id`, `faction_id`, `vault_id`, `rule_id`, `initiated_by`, `target_account`,
             `amount`, `reason`, `required_signatures`, `current_signatures`, `signature_details`,
             `status`, `timelock_until`, `expires_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        requestId,
        factionId,
        vault.vaultId,
        matchedRule.ruleId,
        player.citizenId,
        targetAccount,
        transferAmount,
        reason or string.format("Multi-Sig Corporate Disbursement from %s", vault.vaultLabel),
        requiredSigs,
        json.encode(currentSigs),
        json.encode(signatureDetails),
        initialStatus,
        timelockUntil,
        expireTime
    })

    if not insertOk then
        return false, "DATABASE_ERROR"
    end

    -- Audit log
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_multisig_audit`
            (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
        VALUES (?, ?, ?, 'WITHDRAWAL_INITIATED', ?)
    ]], {
        requestId,
        factionId,
        player.citizenId,
        json.encode({
            vaultId = vault.vaultId,
            ruleId = matchedRule.ruleId,
            amount = transferAmount,
            targetAccount = targetAccount,
            requiredSignatures = requiredSigs,
            timelockSeconds = timelockSeconds
        })
    })

    -- Check if initial signature already satisfies quorum
    local rolesOk = evaluateSignatoryRoles(signatureDetails, matchedRule.requiredRoles)
    if #currentSigs >= requiredSigs and rolesOk then
        -- Check Timelock
        if timelockSeconds > 0 then
            timelockUntil = os.date("%Y-%m-%d %H:%M:%S", os.time() + timelockSeconds)
            MySQL.prepare.await([[
                UPDATE `nyx_factions_multisig_queue`
                SET `status` = 'timelocked', `timelock_until` = ?
                WHERE `request_id` = ?
            ]], { timelockUntil, requestId })

            -- Audit log
            MySQL.prepare.await([[
                INSERT INTO `nyx_factions_multisig_audit`
                    (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
                VALUES (?, ?, ?, 'TIMELOCK_ENGAGED', ?)
            ]], {
                requestId,
                factionId,
                player.citizenId,
                json.encode({ timelockUntil = timelockUntil, timelockSeconds = timelockSeconds })
            })

            return true, "TIMELOCKED", {
                requestId = requestId,
                amount = transferAmount,
                timelockUntil = timelockUntil,
                vaultId = vault.vaultId
            }
        else
            -- Disburse immediately
            local ok, txId = exports['nyx_treasury']:ExecuteTransfer(
                vault.accountId,
                targetAccount,
                transferAmount,
                "factions_multisig",
                "MULTISIG:" .. requestId,
                reason or "Multi-Sig Instant Quorum Transfer",
                0.0
            )

            if ok then
                MySQL.prepare.await([[
                    UPDATE `nyx_factions_multisig_queue`
                    SET `status` = 'approved'
                    WHERE `request_id` = ?
                ]], { requestId })

                -- Debit daily limit
                MySQL.prepare.await([[
                    UPDATE `nyx_factions_vaults`
                    SET `daily_withdrawn` = `daily_withdrawn` + ?
                    WHERE `vault_id` = ?
                ]], { transferAmount, vault.vaultId })

                -- Audit log
                MySQL.prepare.await([[
                    INSERT INTO `nyx_factions_multisig_audit`
                        (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
                    VALUES (?, ?, ?, 'DISBURSED', ?)
                ]], {
                    requestId,
                    factionId,
                    player.citizenId,
                    json.encode({ txId = txId, amount = transferAmount })
                })

                return true, "DISBURSED", { requestId = requestId, amount = transferAmount, txId = txId, vaultId = vault.vaultId }
            end
        end
    end

    -- Broadcast notification to online certified signatories
    local members = Nyx.Factions.GetFactionMembers(factionId)
    for _, member in ipairs(members) do
        local targetPlayer = Nyx.GetPlayerByCitizenId(member.citizenId)
        if targetPlayer and Nyx.Factions.HasPermission(member.citizenId, factionId, "treasury:sign_tx") then
            TriggerClientEvent("nyx:ui:notify", targetPlayer.source, {
                type = "warning",
                title = "MULTI-SIG SIGN-OFF REQUIRED",
                message = string.format("Withdrawal for $%.2f from '%s' pending approval on %s.",
                    transferAmount, vault.vaultLabel, faction.legal_name)
            })
        end
    end

    return true, "QUEUED_MULTISIG", {
        requestId = requestId,
        amount = transferAmount,
        currentSignatures = #currentSigs,
        requiredSignatures = requiredSigs,
        ruleName = matchedRule.ruleName,
        timelockSeconds = timelockSeconds,
        vaultId = vault.vaultId,
        expiresAt = expireTime
    }
end

-- Approve / Sign a pending multi-sig request
function Nyx.Factions.ApproveMultiSigRequest(src, requestId, signNote)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local req = MySQL.single.await([[
        SELECT r.*, f.legal_name, v.account_id as vault_account_id, v.is_frozen, v.daily_limit, v.daily_withdrawn
        FROM `nyx_factions_multisig_queue` r
        JOIN `nyx_factions_registry` f ON r.faction_id = f.faction_id
        LEFT JOIN `nyx_factions_vaults` v ON r.vault_id = v.vault_id
        WHERE r.request_id = ? AND r.status = 'pending'
    ]], { requestId })

    if not req then
        return false, "REQUEST_NOT_FOUND_OR_RESOLVED"
    end

    -- Verify expiration
    local nowStr = os.date("%Y-%m-%d %H:%M:%S")
    if req.expires_at <= nowStr then
        MySQL.prepare.await([[
            UPDATE `nyx_factions_multisig_queue` SET `status` = 'expired' WHERE `request_id` = ?
        ]], { requestId })
        return false, "REQUEST_EXPIRED"
    end

    -- Verify vault freeze state
    if req.is_frozen == 1 then
        return false, "VAULT_FROZEN"
    end

    -- Verify caller holds signatory privileges
    if not Nyx.Factions.HasPermission(player.citizenId, req.faction_id, "treasury:sign_tx") then
        return false, "INSUFFICIENT_SIGNATORY_PRIVILEGES"
    end

    -- Parse existing signatures
    local signatures = {}
    if type(req.current_signatures) == "string" then
        local ok, parsed = pcall(json.decode, req.current_signatures)
        if ok and type(parsed) == "table" then signatures = parsed end
    elseif type(req.current_signatures) == "table" then
        signatures = req.current_signatures
    end

    local signatureDetails = {}
    if type(req.signature_details) == "string" then
        local ok, parsed = pcall(json.decode, req.signature_details)
        if ok and type(parsed) == "table" then signatureDetails = parsed end
    elseif type(req.signature_details) == "table" then
        signatureDetails = req.signature_details
    end

    -- Prevent duplicate signatures
    for _, signerId in ipairs(signatures) do
        if signerId == player.citizenId then
            return false, "ALREADY_SIGNED"
        end
    end

    -- Fetch signer member record to capture role
    local member = Nyx.Factions.GetMember(player.citizenId, req.faction_id)
    local signerRole = member and member.roleTitle or "Signatory"

    table.insert(signatures, player.citizenId)
    table.insert(signatureDetails, {
        citizenId = player.citizenId,
        roleTitle = signerRole,
        signedAt = nowStr,
        note = signNote or "Authorized Signatory Approval"
    })

    -- Audit log: Signature registered
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_multisig_audit`
            (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
        VALUES (?, ?, ?, 'SIGNED', ?)
    ]], {
        requestId,
        req.faction_id,
        player.citizenId,
        json.encode({ role = signerRole, note = signNote })
    })

    -- Fetch rule if bound to verify role criteria and timelock
    local rule = nil
    if req.rule_id then
        local rRow = MySQL.single.await([[
            SELECT * FROM `nyx_factions_signoff_rules` WHERE `rule_id` = ?
        ]], { req.rule_id })
        if rRow then
            local rRoles = nil
            if rRow.required_roles then
                local ok, parsed = pcall(json.decode, rRow.required_roles)
                if ok then rRoles = parsed end
            end
            rule = {
                requiredRoles = rRoles,
                timelockSeconds = tonumber(rRow.timelock_seconds) or 0
            }
        end
    end

    local rolesSatisfied = true
    if rule and rule.requiredRoles then
        rolesSatisfied = evaluateSignatoryRoles(signatureDetails, rule.requiredRoles)
    end

    -- Check if quorum is fulfilled
    local quorumSatisfied = (#signatures >= tonumber(req.required_signatures)) and rolesSatisfied

    if quorumSatisfied then
        local timelockSeconds = rule and rule.timelockSeconds or 0

        -- Check Timelock requirement
        if timelockSeconds > 0 then
            local timelockUntil = os.date("%Y-%m-%d %H:%M:%S", os.time() + timelockSeconds)
            MySQL.prepare.await([[
                UPDATE `nyx_factions_multisig_queue`
                SET `current_signatures` = ?, `signature_details` = ?, `status` = 'timelocked', `timelock_until` = ?
                WHERE `request_id` = ?
            ]], { json.encode(signatures), json.encode(signatureDetails), timelockUntil, requestId })

            -- Audit log
            MySQL.prepare.await([[
                INSERT INTO `nyx_factions_multisig_audit`
                    (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
                VALUES (?, ?, ?, 'TIMELOCK_ENGAGED', ?)
            ]], {
                requestId,
                req.faction_id,
                player.citizenId,
                json.encode({ timelockUntil = timelockUntil, timelockSeconds = timelockSeconds })
            })

            TriggerClientEvent("nyx:ui:notify", -1, {
                type = "info",
                title = "TIMELOCK ESCROW ENGAGED",
                message = string.format("Withdrawal of $%.2f reached quorum. Executable at %s.", req.amount, timelockUntil)
            })

            return true, "TIMELOCKED", {
                requestId = requestId,
                amount = req.amount,
                timelockUntil = timelockUntil
            }
        else
            -- Direct Authoritative Disbursement
            local sourceAccount = req.vault_account_id or ("faction:" .. req.faction_id)
            local success, txId = exports['nyx_treasury']:ExecuteTransfer(
                sourceAccount,
                req.target_account,
                tonumber(req.amount),
                "factions_multisig",
                "MULTISIG:" .. requestId,
                req.reason,
                0.0
            )

            if success then
                MySQL.prepare.await([[
                    UPDATE `nyx_factions_multisig_queue`
                    SET `current_signatures` = ?, `signature_details` = ?, `status` = 'approved'
                    WHERE `request_id` = ?
                ]], { json.encode(signatures), json.encode(signatureDetails), requestId })

                -- Debit daily limit on vault
                if req.vault_id then
                    MySQL.prepare.await([[
                        UPDATE `nyx_factions_vaults`
                        SET `daily_withdrawn` = `daily_withdrawn` + ?
                        WHERE `vault_id` = ?
                    ]], { tonumber(req.amount), req.vault_id })
                end

                -- Audit log
                MySQL.prepare.await([[
                    INSERT INTO `nyx_factions_multisig_audit`
                        (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
                    VALUES (?, ?, ?, 'DISBURSED', ?)
                ]], {
                    requestId,
                    req.faction_id,
                    player.citizenId,
                    json.encode({ txId = txId, amount = req.amount, targetAccount = req.target_account })
                })

                -- Broadcast confirmation
                TriggerClientEvent("nyx:factions:client:multisigDisbursed", -1, {
                    requestId = requestId,
                    factionId = req.faction_id,
                    vaultId = req.vault_id,
                    amount = req.amount,
                    targetAccount = req.target_account
                })

                return true, "DISBURSED", { txId = txId, amount = req.amount }
            else
                return false, "TREASURY_TRANSFER_FAILED"
            end
        end
    else
        -- Append signature and wait for remaining quorum / roles
        MySQL.prepare.await([[
            UPDATE `nyx_factions_multisig_queue`
            SET `current_signatures` = ?, `signature_details` = ?
            WHERE `request_id` = ?
        ]], { json.encode(signatures), json.encode(signatureDetails), requestId })

        return true, "SIGNATURE_REGISTERED", {
            currentSignatures = #signatures,
            requiredSignatures = req.required_signatures,
            rolesSatisfied = rolesSatisfied
        }
    end
end

-- Execute a Timelocked multi-sig request whose delay period has elapsed
function Nyx.Factions.ExecuteTimelockedMultiSig(src, requestId)
    local player = nil
    local actorCitId = "SYSTEM"
    if src and src ~= 0 then
        player = Nyx.GetPlayer(src)
        if not player then return false, "UNAUTHENTICATED" end
        actorCitId = player.citizenId
    end

    local req = MySQL.single.await([[
        SELECT r.*, v.account_id as vault_account_id, v.is_frozen
        FROM `nyx_factions_multisig_queue` r
        LEFT JOIN `nyx_factions_vaults` v ON r.vault_id = v.vault_id
        WHERE r.request_id = ? AND r.status = 'timelocked'
    ]], { requestId })

    if not req then
        return false, "REQUEST_NOT_FOUND_OR_NOT_TIMELOCKED"
    end

    -- Verify vault freeze
    if req.is_frozen == 1 then
        return false, "VAULT_FROZEN"
    end

    -- Verify timelock delay has elapsed
    local timelockEpoch = parseTimestamp(req.timelock_until)
    if os.time() < timelockEpoch then
        local remaining = timelockEpoch - os.time()
        return false, string.format("TIMELOCK_ACTIVE_REMAINING_%d_SECONDS", remaining)
    end

    local sourceAccount = req.vault_account_id or ("faction:" .. req.faction_id)
    local transferAmt = tonumber(req.amount) or 0.00

    local success, txId = exports['nyx_treasury']:ExecuteTransfer(
        sourceAccount,
        req.target_account,
        transferAmt,
        "factions_multisig_timelocked",
        "MULTISIG_TIMELOCKED:" .. requestId,
        req.reason,
        0.0
    )

    if not success then
        return false, "TREASURY_TRANSFER_FAILED"
    end

    MySQL.prepare.await([[
        UPDATE `nyx_factions_multisig_queue`
        SET `status` = 'approved'
        WHERE `request_id` = ?
    ]], { requestId })

    if req.vault_id then
        MySQL.prepare.await([[
            UPDATE `nyx_factions_vaults`
            SET `daily_withdrawn` = `daily_withdrawn` + ?
            WHERE `vault_id` = ?
        ]], { transferAmt, req.vault_id })
    end

    -- Audit log
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_multisig_audit`
            (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
        VALUES (?, ?, ?, 'TIMELOCKED_DISBURSED', ?)
    ]], {
        requestId,
        req.faction_id,
        actorCitId,
        json.encode({ txId = txId, amount = transferAmt, targetAccount = req.target_account })
    })

    TriggerClientEvent("nyx:factions:client:multisigDisbursed", -1, {
        requestId = requestId,
        factionId = req.faction_id,
        vaultId = req.vault_id,
        amount = transferAmt,
        targetAccount = req.target_account
    })

    return true, "DISBURSED", { txId = txId, amount = transferAmt }
end

-- Cancel a pending or timelocked multi-sig request (Initiator or Authorized Executive)
function Nyx.Factions.CancelMultiSigRequest(src, requestId, cancellationReason)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local req = MySQL.single.await([[
        SELECT `faction_id`, `initiated_by`, `status` FROM `nyx_factions_multisig_queue`
        WHERE `request_id` = ? AND (`status` = 'pending' OR `status` = 'timelocked')
    ]], { requestId })

    if not req then return false, "REQUEST_NOT_FOUND_OR_RESOLVED" end

    -- Authorized if caller is initiator OR has governance:call_vote / treasury:manage_rules
    local isInitiator = (req.initiated_by == player.citizenId)
    local isExecutive = Nyx.Factions.HasPermission(player.citizenId, req.faction_id, "treasury:manage_rules")
                     or Nyx.Factions.HasPermission(player.citizenId, req.faction_id, "governance:call_vote")

    if not isInitiator and not isExecutive then
        return false, "INSUFFICIENT_PERMISSIONS_CANCEL"
    end

    local reason = cancellationReason or "Cancelled by Authorized Personnel"

    MySQL.prepare.await([[
        UPDATE `nyx_factions_multisig_queue`
        SET `status` = 'cancelled', `cancelled_by` = ?, `cancellation_reason` = ?
        WHERE `request_id` = ?
    ]], { player.citizenId, reason, requestId })

    -- Audit log
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_multisig_audit`
            (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
        VALUES (?, ?, ?, 'CANCELLED', ?)
    ]], {
        requestId,
        req.faction_id,
        player.citizenId,
        json.encode({ reason = reason })
    })

    return true, "CANCELLED"
end

-- Reject a pending multi-sig request
function Nyx.Factions.RejectMultiSigRequest(src, requestId, rejectionReason)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local req = MySQL.single.await([[
        SELECT `faction_id`, `status` FROM `nyx_factions_multisig_queue`
        WHERE `request_id` = ? AND (`status` = 'pending' OR `status` = 'timelocked')
    ]], { requestId })

    if not req then return false, "REQUEST_NOT_FOUND" end

    if not Nyx.Factions.HasPermission(player.citizenId, req.faction_id, "treasury:sign_tx") then
        return false, "INSUFFICIENT_SIGNATORY_PRIVILEGES"
    end

    MySQL.prepare.await([[
        UPDATE `nyx_factions_multisig_queue`
        SET `status` = 'rejected', `cancellation_reason` = ?
        WHERE `request_id` = ?
    ]], { rejectionReason or "Rejected by Signatory", requestId })

    -- Audit log
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_multisig_audit`
            (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
        VALUES (?, ?, ?, 'REJECTED', ?)
    ]], {
        requestId,
        req.faction_id,
        player.citizenId,
        json.encode({ reason = rejectionReason })
    })

    return true, "REJECTED"
end

-- Query multi-sig audit history
function Nyx.Factions.GetMultiSigAuditLog(factionId, limit)
    local maxLimit = math.min(100, tonumber(limit) or 50)
    local rows = MySQL.query.await([[
        SELECT * FROM `nyx_factions_multisig_audit`
        WHERE `faction_id` = ?
        ORDER BY `created_at` DESC
        LIMIT ?
    ]], { factionId, maxLimit })

    local auditLogs = {}
    for _, row in ipairs(rows or {}) do
        local details = nil
        if row.details then
            local ok, parsed = pcall(json.decode, row.details)
            if ok then details = parsed end
        end

        table.insert(auditLogs, {
            auditId = row.audit_id,
            requestId = row.request_id,
            factionId = row.faction_id,
            actorCitizenId = row.actor_citizen_id,
            action = row.action,
            details = details,
            createdAt = row.created_at
        })
    end

    return auditLogs
end

-- Periodic background task: sweep timed-out requests and process expired timelocks
function Nyx.Factions.SweepExpiredMultiSig()
    -- 1. Expire stale pending requests
    local expiredCount = MySQL.update.await([[
        UPDATE `nyx_factions_multisig_queue`
        SET `status` = 'expired'
        WHERE `status` = 'pending' AND `expires_at` <= CURRENT_TIMESTAMP
    ]])

    if expiredCount and expiredCount > 0 and Config.Debug then
        print(string.format("^3[Nyx:Factions]^7 Expired %d pending multi-sig requests^7", expiredCount))
    end

    -- 2. Check and auto-execute timelocked requests whose delay has elapsed
    local readyTimelocks = MySQL.query.await([[
        SELECT `request_id` FROM `nyx_factions_multisig_queue`
        WHERE `status` = 'timelocked' AND `timelock_until` <= CURRENT_TIMESTAMP
    ]])

    for _, row in ipairs(readyTimelocks or {}) do
        Nyx.Factions.ExecuteTimelockedMultiSig(0, row.request_id)
    end
end
