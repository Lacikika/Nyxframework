--[[
    Nyxframework: nyx_factions
    File: server/vaults.lua
    Description: Corporate Treasury Sub-Vaults management, daily limit rolling window tracking,
                 emergency freeze/lockdown mechanics, and internal inter-vault transfers.
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

-- Utility: Slugify label
local function slugify(text)
    local slug = string.lower(text:gsub("%s+", "_"):gsub("[^%w_]", ""))
    if #slug > 24 then slug = string.sub(slug, 1, 24) end
    return slug
end

-- 1. Ensure primary vault exists for a faction (idempotent fallback for legacy factions)
function Nyx.Factions.EnsurePrimaryVault(factionId)
    local faction = Nyx.Factions.GetFaction(factionId)
    if not faction then return nil end

    local existing = MySQL.single.await([[
        SELECT * FROM `nyx_factions_vaults`
        WHERE `faction_id` = ? AND `is_primary` = 1
    ]], { factionId })

    if existing then
        return existing
    end

    local primaryVaultId = "vlt:" .. factionId .. ":main"
    local defaultLimit = Config.Vaults and Config.Vaults.DefaultDailyLimit or 250000.00

    -- Ensure underlying treasury account exists in nyx_treasury
    if exports['nyx_treasury'] and exports['nyx_treasury'].EnsureAccount then
        exports['nyx_treasury']:EnsureAccount(
            faction.treasury_account_id,
            string.format("%s Primary Operating Treasury", faction.legal_name),
            "corporate_vault",
            0.00
        )
    end

    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_vaults`
            (`vault_id`, `faction_id`, `vault_label`, `account_id`, `is_primary`, `daily_limit`, `daily_withdrawn`)
        VALUES (?, ?, ?, ?, 1, ?, 0.00)
        ON DUPLICATE KEY UPDATE `is_primary` = 1
    ]], {
        primaryVaultId,
        factionId,
        "Primary Operating Treasury",
        faction.treasury_account_id,
        defaultLimit
    })

    return MySQL.single.await([[
        SELECT * FROM `nyx_factions_vaults` WHERE `vault_id` = ?
    ]], { primaryVaultId })
end

-- 2. Query all vaults belonging to a faction (with rolling 24h daily limit reset)
function Nyx.Factions.GetFactionVaults(factionId)
    if not factionId then return {} end

    -- Ensure primary vault is initialized
    Nyx.Factions.EnsurePrimaryVault(factionId)

    local rows = MySQL.query.await([[
        SELECT * FROM `nyx_factions_vaults`
        WHERE `faction_id` = ?
        ORDER BY `is_primary` DESC, `created_at` ASC
    ]], { factionId })

    local now = os.time()
    local resetInterval = Config.Vaults and Config.Vaults.DailyResetSeconds or 86400
    local vaults = {}

    for _, row in ipairs(rows or {}) do
        local lastReset = os.time()
        if row.last_limit_reset then
            local pyear, pmonth, pday, phour, pmin, psec = string.match(tostring(row.last_limit_reset), "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
            if pyear then
                lastReset = os.time({
                    year = tonumber(pyear),
                    month = tonumber(pmonth),
                    day = tonumber(pday),
                    hour = tonumber(phour),
                    min = tonumber(pmin),
                    sec = tonumber(psec)
                })
            end
        end

        local dailyWithdrawn = tonumber(row.daily_withdrawn) or 0.00
        if (now - lastReset) >= resetInterval then
            dailyWithdrawn = 0.00
            MySQL.prepare.await([[
                UPDATE `nyx_factions_vaults`
                SET `daily_withdrawn` = 0.00, `last_limit_reset` = CURRENT_TIMESTAMP
                WHERE `vault_id` = ?
            ]], { row.vault_id })
        end

        local balance = 0.00
        if exports['nyx_treasury'] and exports['nyx_treasury'].GetAccountBalance then
            balance = exports['nyx_treasury']:GetAccountBalance(row.account_id) or 0.00
        end

        local limit = tonumber(row.daily_limit) or 100000.00
        local remainingLimit = math.max(0.00, limit - dailyWithdrawn)

        table.insert(vaults, {
            vaultId = row.vault_id,
            factionId = row.faction_id,
            vaultLabel = row.vault_label,
            accountId = row.account_id,
            isPrimary = (row.is_primary == 1),
            dailyLimit = limit,
            dailyWithdrawn = dailyWithdrawn,
            remainingDailyLimit = remainingLimit,
            isFrozen = (row.is_frozen == 1),
            frozenBy = row.frozen_by,
            freezeReason = row.freeze_reason,
            balance = balance,
            createdAt = row.created_at
        })
    end

    return vaults
end

-- 3. Query a specific vault by ID
function Nyx.Factions.GetVault(vaultId)
    if not vaultId then return nil end

    local row = MySQL.single.await([[
        SELECT * FROM `nyx_factions_vaults` WHERE `vault_id` = ?
    ]], { vaultId })

    if not row then return nil end

    local now = os.time()
    local resetInterval = Config.Vaults and Config.Vaults.DailyResetSeconds or 86400
    local lastReset = now

    if row.last_limit_reset then
        local pyear, pmonth, pday, phour, pmin, psec = string.match(tostring(row.last_limit_reset), "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
        if pyear then
            lastReset = os.time({
                year = tonumber(pyear),
                month = tonumber(pmonth),
                day = tonumber(pday),
                hour = tonumber(phour),
                min = tonumber(pmin),
                sec = tonumber(psec)
            })
        end
    end

    local dailyWithdrawn = tonumber(row.daily_withdrawn) or 0.00
    if (now - lastReset) >= resetInterval then
        dailyWithdrawn = 0.00
        MySQL.prepare.await([[
            UPDATE `nyx_factions_vaults`
            SET `daily_withdrawn` = 0.00, `last_limit_reset` = CURRENT_TIMESTAMP
            WHERE `vault_id` = ?
        ]], { row.vault_id })
    end

    local balance = 0.00
    if exports['nyx_treasury'] and exports['nyx_treasury'].GetAccountBalance then
        balance = exports['nyx_treasury']:GetAccountBalance(row.account_id) or 0.00
    end

    local limit = tonumber(row.daily_limit) or 100000.00
    local remainingLimit = math.max(0.00, limit - dailyWithdrawn)

    return {
        vaultId = row.vault_id,
        factionId = row.faction_id,
        vaultLabel = row.vault_label,
        accountId = row.account_id,
        isPrimary = (row.is_primary == 1),
        dailyLimit = limit,
        dailyWithdrawn = dailyWithdrawn,
        remainingDailyLimit = remainingLimit,
        isFrozen = (row.is_frozen == 1),
        frozenBy = row.frozen_by,
        freezeReason = row.freeze_reason,
        balance = balance,
        createdAt = row.created_at
    }
end

-- 4. Create a new Corporate Sub-Vault
function Nyx.Factions.CreateVault(actorCitizenId, factionId, vaultLabel, customDailyLimit)
    if actorCitizenId ~= "SYSTEM" and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "treasury:manage_vaults") then
        return false, "INSUFFICIENT_PERMISSIONS_MANAGE_VAULTS"
    end

    local faction = Nyx.Factions.GetFaction(factionId)
    if not faction then return false, "FACTION_NOT_FOUND" end

    if not vaultLabel or string.len(vaultLabel) < 3 or string.len(vaultLabel) > 64 then
        return false, "INVALID_VAULT_LABEL"
    end

    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_factions_vaults` WHERE `faction_id` = ?
    ]], { factionId })

    local maxVaults = Config.Vaults and Config.Vaults.MaxSubVaults or 10
    if count and count >= maxVaults then
        return false, "MAX_SUB_VAULTS_REACHED"
    end

    local slug = slugify(vaultLabel)
    local randomSuffix = string.sub(generateUUID(), 1, 6)
    local vaultId = string.format("vlt:%s:%s_%s", factionId, slug, randomSuffix)
    local accountId = string.format("faction:%s:%s_%s", factionId, slug, randomSuffix)
    local dailyLimit = math.max(1000.00, tonumber(customDailyLimit) or (Config.Vaults and Config.Vaults.DefaultDailyLimit or 100000.00))

    -- Register account in nyx_treasury
    if exports['nyx_treasury'] and exports['nyx_treasury'].EnsureAccount then
        exports['nyx_treasury']:EnsureAccount(
            accountId,
            string.format("%s - %s", faction.legal_name, vaultLabel),
            "corporate_vault",
            0.00
        )
    end

    local success = MySQL.prepare.await([[
        INSERT INTO `nyx_factions_vaults`
            (`vault_id`, `faction_id`, `vault_label`, `account_id`, `is_primary`, `daily_limit`, `daily_withdrawn`)
        VALUES (?, ?, ?, ?, 0, ?, 0.00)
    ]], {
        vaultId,
        factionId,
        vaultLabel,
        accountId,
        dailyLimit
    })

    if not success then
        return false, "DATABASE_ERROR"
    end

    -- Audit log
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_multisig_audit`
            (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
        VALUES (?, ?, ?, 'VAULT_CREATED', ?)
    ]], {
        vaultId,
        factionId,
        actorCitizenId,
        json.encode({ vaultLabel = vaultLabel, accountId = accountId, dailyLimit = dailyLimit })
    })

    return true, {
        vaultId = vaultId,
        factionId = factionId,
        vaultLabel = vaultLabel,
        accountId = accountId,
        dailyLimit = dailyLimit
    }
end

-- 5. Emergency Freeze / Lockdown or Unfreeze a Vault
function Nyx.Factions.SetVaultFreeze(actorCitizenId, factionId, vaultId, isFrozen, reason)
    if actorCitizenId ~= "SYSTEM" and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "treasury:freeze_vault")
       and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "governance:call_vote") then
        return false, "INSUFFICIENT_PERMISSIONS_FREEZE_VAULT"
    end

    local vault = Nyx.Factions.GetVault(vaultId)
    if not vault or vault.factionId ~= factionId then
        return false, "VAULT_NOT_FOUND"
    end

    local frozenFlag = isFrozen and 1 or 0
    local freezeReason = reason or (isFrozen and "Emergency Administrative Freeze" or "Administrative Unfreeze")

    MySQL.prepare.await([[
        UPDATE `nyx_factions_vaults`
        SET `is_frozen` = ?, `frozen_by` = ?, `freeze_reason` = ?
        WHERE `vault_id` = ?
    ]], {
        frozenFlag,
        actorCitizenId,
        freezeReason,
        vaultId
    })

    -- Audit log
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_multisig_audit`
            (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        vaultId,
        factionId,
        actorCitizenId,
        isFrozen and "VAULT_FROZEN" or "VAULT_UNFROZEN",
        json.encode({ reason = freezeReason, isFrozen = isFrozen })
    })

    -- Broadcast to online members
    local members = Nyx.Factions.GetFactionMembers(factionId)
    for _, member in ipairs(members) do
        local targetPlayer = Nyx.GetPlayerByCitizenId(member.citizenId)
        if targetPlayer then
            TriggerClientEvent("nyx:ui:notify", targetPlayer.source, {
                type = isFrozen and "error" or "success",
                title = isFrozen and "VAULT LOCKDOWN ACTIVATED" or "VAULT LOCKDOWN LIFTED",
                message = string.format("Vault '%s' %s by %s. Reason: %s",
                    vault.vaultLabel, isFrozen and "FROZEN" or "UNFROZEN", actorCitizenId, freezeReason)
            })
        end
    end

    return true, { vaultId = vaultId, isFrozen = isFrozen, reason = freezeReason }
end

-- 6. Inter-Vault Internal Transfer (Capital Rebalance)
function Nyx.Factions.TransferVaultFunds(actorCitizenId, factionId, fromVaultId, toVaultId, amount, memo)
    if actorCitizenId ~= "SYSTEM" and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "treasury:manage_vaults")
       and not Nyx.Factions.HasPermission(actorCitizenId, factionId, "treasury:withdraw_high") then
        return false, "INSUFFICIENT_PERMISSIONS_VAULT_TRANSFER"
    end

    local transferAmt = tonumber(amount) or 0.00
    if transferAmt <= 0.00 then
        return false, "INVALID_AMOUNT"
    end

    if fromVaultId == toVaultId then
        return false, "IDENTICAL_VAULTS"
    end

    local fromVault = Nyx.Factions.GetVault(fromVaultId)
    local toVault = Nyx.Factions.GetVault(toVaultId)

    if not fromVault or fromVault.factionId ~= factionId then
        return false, "SOURCE_VAULT_NOT_FOUND"
    end

    if not toVault or toVault.factionId ~= factionId then
        return false, "TARGET_VAULT_NOT_FOUND"
    end

    if fromVault.isFrozen then
        return false, "SOURCE_VAULT_FROZEN"
    end

    if toVault.isFrozen then
        return false, "TARGET_VAULT_FROZEN"
    end

    if fromVault.balance < transferAmt then
        return false, "INSUFFICIENT_VAULT_BALANCE"
    end

    local success, txId = exports['nyx_treasury']:ExecuteTransfer(
        fromVault.accountId,
        toVault.accountId,
        transferAmt,
        "vault_rebalance",
        actorCitizenId,
        memo or string.format("Internal Rebalance: %s -> %s", fromVault.vaultLabel, toVault.vaultLabel),
        0.0
    )

    if not success then
        return false, "TREASURY_TRANSFER_FAILED"
    end

    -- Audit log
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_multisig_audit`
            (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
        VALUES (?, ?, ?, 'VAULT_REBALANCE', ?)
    ]], {
        txId,
        factionId,
        actorCitizenId,
        json.encode({
            fromVaultId = fromVaultId,
            toVaultId = toVaultId,
            amount = transferAmt,
            memo = memo
        })
    })

    return true, {
        txId = txId,
        fromVaultId = fromVaultId,
        toVaultId = toVaultId,
        amount = transferAmt
    }
end

-- 7. Deposit Personal Funds into Vault
function Nyx.Factions.DepositToVault(src, factionId, vaultId, amount)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    if not Nyx.Factions.HasPermission(player.citizenId, factionId, "treasury:deposit") then
        return false, "INSUFFICIENT_PERMISSIONS_DEPOSIT"
    end

    local depositAmt = tonumber(amount) or 0.00
    if depositAmt <= 0.00 then
        return false, "INVALID_AMOUNT"
    end

    local vault = Nyx.Factions.GetVault(vaultId)
    if not vault or vault.factionId ~= factionId then
        return false, "VAULT_NOT_FOUND"
    end

    local personalAcc = "citizen:" .. player.citizenId
    local personalBal = exports['nyx_treasury']:GetAccountBalance(personalAcc) or 0.00
    if personalBal < depositAmt then
        return false, "INSUFFICIENT_PERSONAL_LIQUIDITY"
    end

    local success, txId = exports['nyx_treasury']:ExecuteTransfer(
        personalAcc,
        vault.accountId,
        depositAmt,
        "faction_deposit",
        player.citizenId,
        string.format("Capital deposit into %s", vault.vaultLabel),
        0.0
    )

    if not success then
        return false, "TREASURY_TRANSFER_FAILED"
    end

    -- Audit log
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_multisig_audit`
            (`request_id`, `faction_id`, `actor_citizen_id`, `action`, `details`)
        VALUES (?, ?, ?, 'VAULT_DEPOSIT', ?)
    ]], {
        txId,
        factionId,
        player.citizenId,
        json.encode({ vaultId = vaultId, amount = depositAmt })
    })

    return true, { txId = txId, vaultId = vaultId, amount = depositAmt }
end
