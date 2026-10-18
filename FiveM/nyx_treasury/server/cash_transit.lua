--[[
    Nyxframework: nyx_treasury
    File: server/cash_transit.lua
    Description: Authoritative server engine for municipal bank vaults, armored cash box
                 deposits with double-entry settlements and courier commission splits,
                 as well as illicit heist breaching and forensic dye pack mechanics.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}
Nyx.CashTransit = Nyx.CashTransit or {}
Nyx.Treasury.BankVaults = {} -- [vault_id] = vaultData

local function generateUuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

-- 1. Hydrate Bank Vaults from Database
function Nyx.Treasury.HydrateBankVaults()
    local rows = MySQL.query.await([[
        SELECT `vault_id`, `label`, `treasury_account_id`, `coords`, `security_level`,
               `deposit_fee_pct`, `courier_reward_pct`, `is_active`
        FROM `nyx_treasury_bank_vaults`
    ]]) or {}

    for _, row in ipairs(rows) do
        local coords = nil
        if row.coords and type(row.coords) == "string" and #row.coords > 0 then
            local ok, parsed = pcall(json.decode, row.coords)
            if ok and type(parsed) == "table" then coords = parsed end
        elseif type(row.coords) == "table" then
            coords = row.coords
        end

        Nyx.Treasury.BankVaults[row.vault_id] = {
            vault_id = row.vault_id,
            label = row.label,
            treasury_account_id = row.treasury_account_id or "gov:city:master",
            coords = coords or { x = 255.2, y = 217.4, z = 101.9 },
            security_level = row.security_level or "maximum",
            deposit_fee_pct = tonumber(row.deposit_fee_pct) or 1.00,
            courier_reward_pct = tonumber(row.courier_reward_pct) or 2.00,
            is_active = tonumber(row.is_active) or 1
        }
    end

    if Config and Config.Debug then
        print(string.format("^2[Nyx:Treasury] Hydrated %d municipal bank vaults.^7", #rows))
    end
end

-- Startup hydration
CreateThread(function()
    Wait(500)
    Nyx.Treasury.HydrateBankVaults()
end)

-- 2. Query Bank Vaults
function Nyx.Treasury.GetBankVaults()
    local list = {}
    for _, v in pairs(Nyx.Treasury.BankVaults) do
        table.insert(list, v)
    end
    return list
end

-- 3. Authoritative Municipal Bank Vault Deposit
function Nyx.Treasury.DepositCashTransitBox(src, boxUuid, vaultId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then
        return false, "UNAUTHENTICATED"
    end

    local okVal, cleanPayload = Nyx.CashTransit.ValidateDepositPayload({
        boxUuid = boxUuid,
        vaultId = vaultId
    })
    if not okVal then
        return false, cleanPayload
    end

    local vault = Nyx.Treasury.BankVaults[cleanPayload.vaultId]
    if not vault then
        return false, "VAULT_NOT_FOUND"
    end

    -- Proximity verification to vault coords
    local ped = GetPlayerPed(src)
    local pCoords = GetEntityCoords(ped)
    local vCoords = vector3(vault.coords.x, vault.coords.y, vault.coords.z)
    if #(pCoords - vCoords) > 10.0 then
        return false, "TOO_FAR_FROM_VAULT"
    end

    local boxRow = MySQL.single.await([[
        SELECT * FROM `nyx_treasury_cash_transit_boxes` WHERE `box_uuid` = ?
    ]], { cleanPayload.boxUuid })

    if not boxRow then
        return false, "BOX_NOT_FOUND"
    end

    local okDeposit, errDeposit = Nyx.CashTransit.ValidateVaultDeposit(boxRow, vault, player.citizenId)
    if not okDeposit then
        return false, errDeposit
    end

    -- Verify player possesses the physical item
    local hasItem = false
    if exports['nyx_inventory'] and exports['nyx_inventory'].HasItem then
        hasItem = (exports['nyx_inventory']:HasItem(src, "armored_cash_box") or 0) > 0
    else
        hasItem = true
    end

    if not hasItem then
        return false, "PHYSICAL_BOX_NOT_IN_INVENTORY"
    end

    local cashAmt = tonumber(boxRow.cash_amount) or 0.0
    local splits = Nyx.CashTransit.CalculateTransitSplit(cashAmt, vault.deposit_fee_pct, vault.courier_reward_pct)

    -- Determine corporate destination account
    local faction = exports['nyx_factions']:GetFaction(boxRow.faction_id)
    local corpAccount = (faction and faction.treasury_account_id) or string.format("faction:%s", boxRow.faction_id)

    -- Ensure accounts exist
    Nyx.Treasury.EnsureAccount(corpAccount, string.format("Faction %s Treasury", boxRow.faction_id), "department", 0.0)
    Nyx.Treasury.EnsureAccount(vault.treasury_account_id, "Municipal Vault Treasury", "reserve", 0.0)

    local courierAccount = string.format("citizen:%s", player.citizenId)
    Nyx.Treasury.EnsureAccount(courierAccount, string.format("Citizen %s Account", player.citizenId), "personal", 0.0)

    -- Double-Entry Settlements:
    -- 1. Net Corporate Deposit
    local txId = generateUuid()
    if splits.netCorporateDeposit > 0 then
        Nyx.Treasury.ExecuteTransfer(
            "pool:cash_transit:clearing",
            corpAccount,
            splits.netCorporateDeposit,
            "commercial_revenue_vault_deposit",
            player.citizenId,
            string.format("Transit box %s vault settlement (%s)", boxRow.box_uuid, boxRow.register_id),
            0.0
        )
    end

    -- 2. Municipal Handling Fee
    if splits.municipalBankFee > 0 then
        Nyx.Treasury.ExecuteTransfer(
            "pool:cash_transit:clearing",
            vault.treasury_account_id,
            splits.municipalBankFee,
            "cash_transit_bank_handling_fee",
            player.citizenId,
            string.format("Handling fee for transit box %s", boxRow.box_uuid),
            0.0
        )
    end

    -- 3. Courier Commission Payout
    if splits.courierPayout > 0 then
        Nyx.Treasury.ExecuteTransfer(
            "pool:cash_transit:clearing",
            courierAccount,
            splits.courierPayout,
            "cash_transit_courier_reward",
            player.citizenId,
            string.format("Armored courier commission for box %s", boxRow.box_uuid),
            0.0
        )
    end

    -- Remove physical items from courier inventory
    if exports['nyx_inventory'] and exports['nyx_inventory'].RemoveItem then
        exports['nyx_inventory']:RemoveItem(src, "armored_cash_box", 1)
        exports['nyx_inventory']:RemoveItem(src, "cash_transit_manifest", 1)
    end

    -- Update database status
    MySQL.prepare.await([[
        UPDATE `nyx_treasury_cash_transit_boxes`
        SET `status` = 'deposited',
            `deposited_at` = CURRENT_TIMESTAMP,
            `deposited_by_citizen_id` = ?,
            `treasury_tx_id` = ?
        WHERE `box_id` = ?
    ]], { player.citizenId, txId, boxRow.box_id })

    -- Clear pending transit box on the source commercial register
    MySQL.prepare.await([[
        UPDATE `nyx_factions_commercial_registers`
        SET `pending_transit_box_id` = NULL
        WHERE `register_id` = ?
    ]], { boxRow.register_id })

    -- Audit trail
    MySQL.prepare.await([[
        INSERT INTO `nyx_treasury_cash_transit_audits`
            (`audit_uuid`, `box_id`, `action`, `actor_citizen_id`, `cash_amount`, `faction_id`, `vault_id`, `notes`)
        VALUES (?, ?, 'DEPOSITED_VAULT', ?, ?, ?, ?, ?)
    ]], {
        generateUuid(),
        boxRow.box_id,
        player.citizenId,
        cashAmt,
        boxRow.faction_id,
        vault.vault_id,
        string.format("Box deposited at %s. Net corporate: %s, Courier: %s, Fee: %s",
            vault.label,
            Nyx.CashTransit.FormatCurrency(splits.netCorporateDeposit),
            Nyx.CashTransit.FormatCurrency(splits.courierPayout),
            Nyx.CashTransit.FormatCurrency(splits.municipalBankFee)
        )
    })

    TriggerClientEvent("nyx:core:notify", src, {
        type = "success",
        title = "Banki Széf Letét",
        message = string.format("Páncéldoboz sikeresen bevételezve! Futárdíj: %s, Céges jóváírás: %s",
            Nyx.CashTransit.FormatCurrency(splits.courierPayout),
            Nyx.CashTransit.FormatCurrency(splits.netCorporateDeposit)
        )
    })

    return true, {
        boxUuid = boxRow.box_uuid,
        splits = splits,
        treasuryTxId = txId
    }
end

-- 4. Illicit Criminal Box Breaching & Forensic Dye Mechanics
function Nyx.Treasury.BreachCashTransitBox(src, toolName)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then
        return false, "UNAUTHENTICATED"
    end

    local prof = Nyx.CashTransit.BreachTools[toolName]
    if not prof then
        return false, "INVALID_BREACH_TOOL"
    end

    -- Verify player holds armored cash box
    local boxCount = (exports['nyx_inventory'] and exports['nyx_inventory'].HasItem and exports['nyx_inventory']:HasItem(src, "armored_cash_box")) or 0
    if boxCount <= 0 then
        return false, "NO_ARMORED_BOX"
    end

    -- Find active box row from database
    local boxRow = MySQL.single.await([[
        SELECT * FROM `nyx_treasury_cash_transit_boxes`
        WHERE `carrier_citizen_id` = ? AND `status` = 'in_transit' AND `tamper_state` != 'breached'
        ORDER BY `dispatched_at` DESC LIMIT 1
    ]], { player.citizenId })

    if not boxRow then
        -- Search any open in_transit box
        boxRow = MySQL.single.await([[
            SELECT * FROM `nyx_treasury_cash_transit_boxes`
            WHERE `status` = 'in_transit' AND `tamper_state` != 'breached'
            ORDER BY `dispatched_at` DESC LIMIT 1
        ]])
    end

    if not boxRow then
        return false, "NO_ELIGIBLE_TRANSIT_BOX"
    end

    local hasGloves = false
    local okOutcome, outcome = Nyx.CashTransit.CalculateBreachOutcome(toolName, nil, nil, hasGloves)
    if not okOutcome then
        return false, outcome
    end

    -- Remove breach tool durability or consume item
    if exports['nyx_inventory'] and exports['nyx_inventory'].RemoveItem then
        if toolName == "thermite_charge" then
            exports['nyx_inventory']:RemoveItem(src, "thermite_charge", 1)
        end
    end

    if not outcome.success then
        -- Failed breach attempt: trigger alarm
        if exports['nyx_mdt'] and exports['nyx_mdt'].CreateDispatchCall then
            exports['nyx_mdt']:CreateDispatchCall({
                code = "10-90",
                title = "10-90 Armored Cash Transit Tamper Attempt",
                priority = 1
            })
        end
        return false, "BREACH_FAILED"
    end

    -- Successful breach:
    local cashAmt = tonumber(boxRow.cash_amount) or 10000.00
    local lootItem = "dirty_money"
    local lootAmount = math.max(1, math.floor(cashAmt / 1000.0))

    if outcome.dyeTriggered then
        lootItem = "marked_bills"
        lootAmount = math.max(1, math.floor(cashAmt / 5000.0))
    end

    -- Remove armored box
    if exports['nyx_inventory'] and exports['nyx_inventory'].RemoveItem then
        exports['nyx_inventory']:RemoveItem(src, "armored_cash_box", 1)
        exports['nyx_inventory']:AddItem(src, lootItem, lootAmount)
    end

    -- Deposit forensic evidence in nyx_judiciary
    local ped = GetPlayerPed(src)
    local pCoords = GetEntityCoords(ped)
    local evidenceId = string.format("EVI-%06d", math.random(100000, 999999))

    if exports['nyx_judiciary'] and exports['nyx_judiciary'].RegisterEvidence then
        exports['nyx_judiciary']:RegisterEvidence({
            evidenceId = evidenceId,
            type = "toolmark",
            description = string.format("Metallic striations from %s on breached armored cash box %s", prof.label, boxRow.box_uuid),
            coords = { x = pCoords.x, y = pCoords.y, z = pCoords.z }
        })
    end

    -- Update database
    MySQL.prepare.await([[
        UPDATE `nyx_treasury_cash_transit_boxes`
        SET `status` = 'intercepted',
            `tamper_state` = 'breached',
            `breached_at` = CURRENT_TIMESTAMP,
            `breached_by_citizen_id` = ?,
            `evidence_id` = ?
        WHERE `box_id` = ?
    ]], { player.citizenId, evidenceId, boxRow.box_id })

    -- Audit trail
    MySQL.prepare.await([[
        INSERT INTO `nyx_treasury_cash_transit_audits`
            (`audit_uuid`, `box_id`, `action`, `actor_citizen_id`, `cash_amount`, `faction_id`, `notes`)
        VALUES (?, ?, 'BOX_BREACHED', ?, ?, ?, ?)
    ]], {
        generateUuid(),
        boxRow.box_id,
        player.citizenId,
        cashAmt,
        boxRow.faction_id,
        string.format("Box cracked with %s. Dye triggered: %s. Loot: %d %s",
            prof.label, tostring(outcome.dyeTriggered), lootAmount, lootItem)
    })

    -- Police alert
    if exports['nyx_mdt'] and exports['nyx_mdt'].CreateDispatchCall then
        exports['nyx_mdt']:CreateDispatchCall({
            code = "10-90",
            title = "10-90 Armored Cash Transit Robbery in Progress",
            priority = 1
        })
    end

    TriggerClientEvent("nyx:core:notify", src, {
        type = outcome.dyeTriggered and "warning" or "success",
        title = "Páncéldoboz Feltörve",
        message = outcome.dyeTriggered and "A dobozt feltörted, de a festékpatron felrobbant! Festékes bankjegyeket zsákmányoltál." or "Sikeres feltörés! Készpénzt szereztél."
    })

    return true, {
        success = true,
        dyeTriggered = outcome.dyeTriggered,
        lootItem = lootItem,
        lootCount = lootAmount
    }
end

-- 5. Query Endpoints
function Nyx.Treasury.GetCashTransitBox(boxUuid)
    if not boxUuid then return nil end
    return MySQL.single.await([[
        SELECT * FROM `nyx_treasury_cash_transit_boxes` WHERE `box_uuid` = ?
    ]], { boxUuid })
end

function Nyx.Treasury.GetTransitHistory(factionId)
    local query = "SELECT * FROM `nyx_treasury_cash_transit_boxes`"
    local params = {}
    if factionId and factionId ~= "" and factionId ~= "ALL" then
        query = query .. " WHERE `faction_id` = ?"
        params[#params + 1] = factionId
    end
    query = query .. " ORDER BY `dispatched_at` DESC LIMIT 50"
    return MySQL.query.await(query, params) or {}
end

-- 6. Register RPC Handlers
if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
    exports['nyx_core']:RegisterRPC("treasury:getBankVaults", function(src)
        return Nyx.Treasury.GetBankVaults()
    end)

    exports['nyx_core']:RegisterRPC("treasury:depositCashTransitBox", function(src, payload)
        if type(payload) ~= "table" then
            return { success = false, error = "INVALID_PAYLOAD" }
        end
        local ok, res = Nyx.Treasury.DepositCashTransitBox(src, payload.boxUuid, payload.vaultId)
        return { success = ok, result = res }
    end)

    exports['nyx_core']:RegisterRPC("treasury:breachCashTransitBox", function(src, payload)
        local tool = type(payload) == "table" and payload.toolName or payload
        local ok, res = Nyx.Treasury.BreachCashTransitBox(src, tool)
        return { success = ok, result = res }
    end)

    exports['nyx_core']:RegisterRPC("treasury:getCashTransitBox", function(src, boxUuid)
        return Nyx.Treasury.GetCashTransitBox(boxUuid)
    end)

    exports['nyx_core']:RegisterRPC("treasury:getTransitHistory", function(src, factionId)
        return Nyx.Treasury.GetTransitHistory(factionId)
    end)
end
