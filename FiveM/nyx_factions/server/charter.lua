--[[
    Nyxframework: nyx_factions
    File: server/charter.lua
    Description: Autonomous organization charter creation pipeline, municipal filing fee remittance,
                 and dynamic account/warehouse initialization.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}

-- Utility: Generate slugified faction identifier
local function generateFactionId(charterType, legalName)
    local prefix = string.sub(charterType, 1, 4)
    local slug = string.lower(legalName:gsub("%s+", "_"):gsub("[^%w_]", ""))
    if #slug > 24 then slug = string.sub(slug, 1, 24) end
    return string.format("%s:%s", prefix, slug)
end

-- 1. Create a legal autonomous organization charter
function Nyx.Factions.CreateCharter(src, legalName, charterType, initialDeposit)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    if not legalName or string.len(legalName) < 3 or string.len(legalName) > 96 then
        return false, "INVALID_LEGAL_NAME"
    end

    if not Config.Charter.AllowedTypes[charterType] then
        return false, "INVALID_CHARTER_TYPE"
    end

    local filingFee = Config.Charter.FilingFee or 15000.00
    local minSeed = Config.Charter.MinSeedCapital or 10000.00
    local seedDeposit = math.max(tonumber(initialDeposit) or 0.00, minSeed)
    local totalRequired = filingFee + seedDeposit

    local founderAcc = "citizen:" .. player.citizenId
    local founderBal = exports['nyx_treasury']:GetAccountBalance(founderAcc) or 0.00

    if founderBal < totalRequired then
        return false, string.format("INSUFFICIENT_LIQUIDITY_REQUIRED_%.2f", totalRequired)
    end

    local factionId = generateFactionId(charterType, legalName)

    -- Ensure faction ID and legal name are unique
    local exists = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_factions_registry`
        WHERE `faction_id` = ? OR `legal_name` = ?
    ]], { factionId, legalName })

    if exists and exists > 0 then
        return false, "FACTION_OR_NAME_ALREADY_REGISTERED"
    end

    local corpTreasuryAcc = "faction:" .. factionId
    local corpStashId = "faction:stash:" .. factionId
    local municipalAcc = Config.Charter.MunicipalAccount or "gov:city:master"

    -- Transaction Step 1: Debit municipal filing fee to city master treasury
    local feeOk, feeErr = exports['nyx_treasury']:ExecuteTransfer(
        founderAcc,
        municipalAcc,
        filingFee,
        "charter_filing_fee",
        founderAcc,
        string.format("Municipal Charter Filing Fee for %s", legalName),
        0.0
    )

    if not feeOk then
        return false, "FILING_FEE_TRANSFER_FAILED"
    end

    -- Transaction Step 2: Seed corporate bank account with founder capital
    local seedOk, seedErr = exports['nyx_treasury']:ExecuteTransfer(
        founderAcc,
        corpTreasuryAcc,
        seedDeposit,
        "seed_capital",
        founderAcc,
        string.format("Initial Seed Capital for %s", legalName),
        0.0
    )

    if not seedOk then
        return false, "SEED_CAPITAL_TRANSFER_FAILED"
    end

    -- Step 3: Register primary commercial stash in nyx_inventory
    if exports['nyx_inventory'] and exports['nyx_inventory'].RegisterContainer then
        exports['nyx_inventory']:RegisterContainer(
            corpStashId,
            string.format("%s Master Warehouse", legalName),
            2000000, -- 2,000 kg capacity
            120,     -- 120 slots
            "permanent",
            nil
        )
    end

    -- Step 4: Persist faction registry row
    local insertOk = MySQL.prepare.await([[
        INSERT INTO `nyx_factions_registry`
            (`faction_id`, `legal_name`, `charter_type`, `treasury_account_id`, `primary_stash_id`,
             `multisig_threshold_amount`, `multisig_required_signatures`)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        factionId,
        legalName,
        charterType,
        corpTreasuryAcc,
        corpStashId,
        Config.MultiSig.DefaultThresholdAmount or 50000.00,
        Config.MultiSig.DefaultRequiredSignatures or 2
    })

    if not insertOk then
        return false, "REGISTRY_INSERT_FAILED"
    end

    -- Step 4b: Initialize primary corporate vault in nyx_factions_vaults
    local primaryVaultId = "vlt:" .. factionId .. ":main"
    local defaultDailyLimit = Config.Vaults and Config.Vaults.DefaultDailyLimit or 100000.00
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_vaults`
            (`vault_id`, `faction_id`, `vault_label`, `account_id`, `is_primary`, `daily_limit`, `daily_withdrawn`)
        VALUES (?, ?, 'Primary Operating Treasury', ?, 1, ?, 0.00)
        ON DUPLICATE KEY UPDATE `is_primary` = 1
    ]], {
        primaryVaultId,
        factionId,
        corpTreasuryAcc,
        defaultDailyLimit
    })

    -- Step 4c: Seed default tiered sign-off rules
    local defThreshold = Config.MultiSig and Config.MultiSig.DefaultThresholdAmount or 50000.00
    local defSigs = Config.MultiSig and Config.MultiSig.DefaultRequiredSignatures or 2
    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_signoff_rules`
            (`rule_id`, `faction_id`, `vault_id`, `rule_name`, `min_amount`, `max_amount`, `required_signatures`, `timelock_seconds`, `priority`, `is_active`)
        VALUES
            (UUID(), ?, NULL, 'Standard Low-Tier Operating Liquidity', 0.00, ?, 1, 0, 10, 1),
            (UUID(), ?, NULL, 'High-Tier Multi-Sig Corporate Quorum', ?, NULL, ?, 0, 20, 1)
    ]], {
        factionId, defThreshold,
        factionId, defThreshold, defSigs
    })

    -- Step 5: Assign founder as Supreme Executive with wildcard permissions and 100% initial equity
    Nyx.Factions.AddMember(
        "SYSTEM",
        factionId,
        player.citizenId,
        "Founder & Chief Executive",
        { "*" },
        100.00,
        0.00
    )

    if Config.Debug then
        print(string.format("^2[Nyx:Factions]^7 Created autonomous organization %s (%s) by %s^7",
            legalName, factionId, player.citizenId))
    end

    return true, {
        factionId = factionId,
        legalName = legalName,
        charterType = charterType,
        treasuryAccountId = corpTreasuryAcc,
        primaryVaultId = primaryVaultId,
        primaryStashId = corpStashId,
        seedCapital = seedDeposit
    }
end

-- 2. Query basic faction registry entry
function Nyx.Factions.GetFaction(factionId)
    return MySQL.single.await([[
        SELECT * FROM `nyx_factions_registry` WHERE `faction_id` = ?
    ]], { factionId })
end

-- 3. Query comprehensive organizational overview
function Nyx.Factions.GetFactionOverview(factionId)
    local faction = Nyx.Factions.GetFaction(factionId)
    if not faction then return nil end

    local treasuryBalance = exports['nyx_treasury']:GetAccountBalance(faction.treasury_account_id) or 0.00
    local members = Nyx.Factions.GetFactionMembers(factionId)
    local vaults = Nyx.Factions.GetFactionVaults(factionId)
    local signoffRules = Nyx.Factions.GetSignoffRules(factionId)

    local pendingMultiSig = MySQL.query.await([[
        SELECT * FROM `nyx_factions_multisig_queue`
        WHERE `faction_id` = ? AND `status` = 'pending'
    ]], { factionId })

    local timelockedMultiSig = MySQL.query.await([[
        SELECT * FROM `nyx_factions_multisig_queue`
        WHERE `faction_id` = ? AND `status` = 'timelocked'
    ]], { factionId })

    local fleetCount = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_factions_fleet` WHERE `faction_id` = ?
    ]], { factionId })

    return {
        faction = faction,
        treasuryBalance = treasuryBalance,
        vaults = vaults,
        signoffRules = signoffRules,
        members = members,
        pendingMultiSig = pendingMultiSig or {},
        timelockedMultiSig = timelockedMultiSig or {},
        fleetCount = tonumber(fleetCount) or 0
    }
end
