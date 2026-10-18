--[[
    Nyxframework: nyx_ui
    File: server/phone.lua
    Description: Authoritative server subsystem for Citizen OS Smartphone Framework.
                 Orchestrates mobile banking, freight board exchanges, emergency alerts,
                 and phone settings persistence.
]]

Nyx = Nyx or {}
Nyx.Phone = Nyx.Phone or {}

-- Standardized RPC Bridge to nyx_core
Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        exports['nyx_core']:RegisterRPC(route, handler)
    end,
    GenerateNonce = function()
        local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        return (string.gsub(template, '[xy]', function(c)
            local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format('%x', v)
        end))
    end
}

-- Ensure Citizen Phone Settings & Number Hydration
function Nyx.Phone.EnsureSettings(citizenId, fullName)
    if not citizenId then return nil end

    local row = MySQL.single.await([[
        SELECT `citizen_id`, `phone_number`, `wallpaper`, `dark_mode`, `airplane_mode`, `notifications_enabled`
        FROM `nyx_phone_settings`
        WHERE `citizen_id` = ?
    ]], { citizenId })

    if not row then
        local phoneNum = Nyx.Phone.GeneratePhoneNumber(citizenId)
        local now = os.time()

        pcall(function()
            MySQL.insert.await([[
                INSERT INTO `nyx_phone_settings`
                    (`citizen_id`, `phone_number`, `wallpaper`, `dark_mode`, `airplane_mode`, `notifications_enabled`, `updated_at`)
                VALUES (?, ?, 'default_dark', 1, 0, 1, ?)
            ]], { citizenId, phoneNum, now })

            MySQL.update.await([[
                UPDATE `nyx_characters` SET `phone_number` = ? WHERE `citizen_id` = ?
            ]], { phoneNum, citizenId })
        end)

        return {
            citizenId = citizenId,
            phoneNumber = phoneNum,
            wallpaper = 'default_dark',
            darkMode = true,
            airplaneMode = false,
            notificationsEnabled = true
        }
    end

    return {
        citizenId = row.citizen_id,
        phoneNumber = row.phone_number or Nyx.Phone.GeneratePhoneNumber(citizenId),
        wallpaper = row.wallpaper or 'default_dark',
        darkMode = (row.dark_mode == 1),
        airplaneMode = (row.airplane_mode == 1),
        notificationsEnabled = (row.notifications_enabled == 1)
    }
end

-- 1. RPC: Master Smartphone Overview Telemetry
Nyx.RPC.Register("phone:getOverview", function(src)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then
        return { success = false, error = "UNAUTHENTICATED" }
    end

    local citizenId = player.citizenId or (player.getCitizenId and player:getCitizenId())
    local fullName = player.name or (player.getCharName and player:getCharName()) or "Állampolgár"
    local job = player.job or (player.getJob and player:getJob()) or "unemployed"

    local settings = Nyx.Phone.EnsureSettings(citizenId, fullName)

    -- 1. Mobile Banking Telemetry
    local bankAccId = string.format("char:%s:bank", citizenId)
    local bankBalance = 0.00
    if exports['nyx_treasury'] and exports['nyx_treasury'].GetBalance then
        bankBalance = tonumber(exports['nyx_treasury']:GetBalance(bankAccId)) or 0.00
    elseif player.getMoney then
        bankBalance = tonumber(player:getMoney("bank")) or 0.00
    end

    local fiscalState = "SOLVENT"
    local transferTaxRate = 0.02
    if exports['nyx_treasury'] and exports['nyx_treasury'].GetFiscalState then
        fiscalState = exports['nyx_treasury']:GetFiscalState()
    end

    local recentTransactions = MySQL.query.await([[
        SELECT `tx_uuid`, `debit_account`, `credit_account`, `amount`, `category`, `memo`, `created_at`
        FROM `nyx_treasury_ledger`
        WHERE `debit_account` = ? OR `credit_account` = ?
        ORDER BY `entry_id` DESC
        LIMIT 10
    ]], { bankAccId, bankAccId }) or {}

    -- Format transactions for display
    local txList = {}
    for _, tx in ipairs(recentTransactions) do
        local isDebit = (tx.debit_account == bankAccId)
        local amt = tonumber(tx.amount) or 0.0
        table.insert(txList, {
            txUuid = tx.tx_uuid,
            isDebit = isDebit,
            amount = amt,
            formattedAmount = (isDebit and "- " or "+ ") .. Nyx.Phone.FormatCurrency(amt),
            category = tx.category,
            memo = tx.memo or "",
            createdAt = tx.created_at
        })
    end

    -- 2. Freight & Logistics Telemetry
    local activeHaul = MySQL.single.await([[
        SELECT `contract_id`, `contract_uuid`, `contract_type`, `item_id`, `quantity`,
               `payout_per_unit`, `total_payout`, `escrow_deposit`, `status`,
               UNIX_TIMESTAMP(`expires_at`) AS `expires_at_unix`
        FROM `nyx_logistics_freight_contracts`
        WHERE `claimed_by_citizen_id` = ? AND `status` = 'in_transit'
        LIMIT 1
    ]], { citizenId })

    local availableHaulsCount = MySQL.scalar.await([[
        SELECT COUNT(*) FROM `nyx_logistics_freight_contracts` WHERE `status` = 'available'
    ]]) or 0

    local formattedActiveHaul = activeHaul and Nyx.Phone.FormatContractCard(activeHaul) or nil

    -- 3. Emergency Alerts Feed
    local alerts = MySQL.query.await([[
        SELECT `alert_id`, `alert_uuid`, `caller_name`, `category`, `message`, `location_label`, `priority`, `created_at`
        FROM `nyx_phone_emergency_alerts`
        ORDER BY `created_at` DESC
        LIMIT 10
    ]]) or {}

    local alertsFeed = {}
    for _, a in ipairs(alerts) do
        local badge = Nyx.Phone.FormatAlertBadge(a.priority, a.category)
        table.insert(alertsFeed, {
            id = a.alert_id,
            uuid = a.alert_uuid,
            caller = a.caller_name,
            category = a.category,
            message = a.message,
            location = a.location_label,
            priority = a.priority,
            createdAt = a.created_at,
            badge = badge
        })
    end

    return {
        success = true,
        citizen = {
            citizenId = citizenId,
            fullName = fullName,
            job = job,
            phoneNumber = settings and settings.phoneNumber or "555-0100"
        },
        settings = settings,
        banking = {
            accountId = bankAccId,
            balance = bankBalance,
            formattedBalance = Nyx.Phone.FormatCurrency(bankBalance),
            fiscalState = fiscalState,
            transferTaxRate = transferTaxRate,
            transactions = txList
        },
        logistics = {
            activeHaul = formattedActiveHaul,
            availableHaulsCount = tonumber(availableHaulsCount) or 0
        },
        alerts = alertsFeed
    }
end)

-- 2. RPC: Direct Mobile Wire Transfer (P2P with Closed-Loop Treasury Tax)
Nyx.RPC.Register("phone:transferMoney", function(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    local citizenId = player.citizenId or (player.getCitizenId and player:getCitizenId())
    local ok, sanitized = Nyx.Phone.ValidateTransferPayload(payload, citizenId)
    if not ok then
        return { success = false, error = sanitized }
    end

    local recipientCitizenId = sanitized.recipientCitizenId
    local amount = sanitized.amount
    local memo = sanitized.memo

    local debitAccount = string.format("char:%s:bank", citizenId)
    local creditAccount = string.format("char:%s:bank", recipientCitizenId)

    -- Calculate transfer tax
    local transferTaxRate = 0.02
    local fee, totalDebit = Nyx.Phone.CalculateTransferTax(amount, transferTaxRate)

    local currentBalance = 0.00
    if exports['nyx_treasury'] and exports['nyx_treasury'].GetBalance then
        currentBalance = tonumber(exports['nyx_treasury']:GetBalance(debitAccount)) or 0.00
    elseif player.getMoney then
        currentBalance = tonumber(player:getMoney("bank")) or 0.00
    end

    if currentBalance < totalDebit then
        return { success = false, error = "INSUFFICIENT_FUNDS", required = totalDebit, current = currentBalance }
    end

    -- Execute double-entry transfer via nyx_treasury
    if exports['nyx_treasury'] and exports['nyx_treasury'].ExecuteTransfer then
        local transferOk, txUuid = exports['nyx_treasury']:ExecuteTransfer(
            debitAccount,
            creditAccount,
            amount,
            "p2p_wire",
            citizenId,
            memo ~= "" and memo or string.format("Wire to %s", recipientCitizenId),
            fee
        )

        if not transferOk then
            return { success = false, error = txUuid or "TRANSFER_FAILED" }
        end

        -- If transfer fee is greater than zero, transfer tax to municipal treasury
        if fee > 0.00 then
            exports['nyx_treasury']:ExecuteTransfer(
                debitAccount,
                "gov:city:master",
                fee,
                "transfer_tax",
                "SYSTEM",
                string.format("P2P Transfer Tax for TX %s", tostring(txUuid):sub(1, 8)),
                0.00
            )
        end

        local newBalance = currentBalance - totalDebit

        -- Notify recipient if online
        local targetPlayer = exports['nyx_core']:GetPlayerByCitizenId(recipientCitizenId)
        if targetPlayer then
            TriggerClientEvent("nyx:ui:notify", targetPlayer.source, {
                type = "success",
                title = "CIVICPAY JÓVÁÍRÁS",
                message = string.format("Átutalás érkezett: +%s tőle: %s (%s)", Nyx.Phone.FormatCurrency(amount), player.name or citizenId, memo ~= "" and memo or "Nincs megjegyzés")
            })
        end

        return {
            success = true,
            txUuid = txUuid,
            amount = amount,
            fee = fee,
            totalDebit = totalDebit,
            newBalance = newBalance,
            formattedBalance = Nyx.Phone.FormatCurrency(newBalance)
        }
    end

    return { success = false, error = "TREASURY_UNAVAILABLE" }
end)

-- 3. RPC: Mobile Freight Board Query
Nyx.RPC.Register("phone:getFreightBoard", function(src, filterType, search)
    local query = [[
        SELECT `contract_id`, `contract_uuid`, `contract_type`, `item_id`, `quantity`,
               `payout_per_unit`, `total_payout`, `escrow_deposit`, `status`,
               UNIX_TIMESTAMP(`expires_at`) AS `expires_at_unix`
        FROM `nyx_logistics_freight_contracts`
        WHERE `status` = 'available'
        ORDER BY `total_payout` DESC
        LIMIT 30
    ]]
    local rows = MySQL.query.await(query) or {}

    local list = {}
    for _, r in ipairs(rows) do
        local card = Nyx.Phone.FormatContractCard(r)
        if card then table.insert(list, card) end
    end

    local filtered = Nyx.Phone.FilterFreightContracts(list, filterType, search)
    return {
        success = true,
        contracts = filtered
    }
end)

-- 4. RPC: Mobile Freight Contract Claim
Nyx.RPC.Register("phone:claimContract", function(src, contractId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    contractId = tonumber(contractId)
    if not contractId then return { success = false, error = "INVALID_CONTRACT_ID" } end

    -- Forward to authoritative nyx_logistics RPC / handler
    if exports['nyx_logistics'] and exports['nyx_logistics'].ClaimContract then
        local ok, res = exports['nyx_logistics']:ClaimContract(contractId, player)
        return { success = ok, result = res, error = (not ok and res or nil) }
    end

    -- Direct fallback query & claim
    local contract = MySQL.single.await([[
        SELECT * FROM `nyx_logistics_freight_contracts` WHERE `contract_id` = ? AND `status` = 'available'
    ]], { contractId })

    if not contract then
        return { success = false, error = "CONTRACT_NOT_AVAILABLE" }
    end

    local citizenId = player.citizenId or (player.getCitizenId and player:getCitizenId())
    local escrowBond = tonumber(contract.escrow_deposit) or 0.0

    -- Deduct escrow bond from citizen bank
    local bankAccId = string.format("char:%s:bank", citizenId)
    local curBal = exports['nyx_treasury']:GetBalance(bankAccId)
    if curBal < escrowBond then
        return { success = false, error = "INSUFFICIENT_ESCROW_FUNDS", required = escrowBond }
    end

    -- Lock contract
    local updated = MySQL.prepare.await([[
        UPDATE `nyx_logistics_freight_contracts`
        SET `status` = 'in_transit', `claimed_by_citizen_id` = ?, `claimed_by_char_id` = ?
        WHERE `contract_id` = ? AND `status` = 'available'
    ]], { citizenId, player.charId or 1, contractId })

    if updated and updated > 0 then
        if escrowBond > 0 then
            exports['nyx_treasury']:ExecuteTransfer(
                bankAccId,
                "gov:escrow:logistics",
                escrowBond,
                "freight_escrow",
                citizenId,
                string.format("Escrow lock for Contract #%d", contractId)
            )
        end
        return { success = true, contractId = contractId }
    end

    return { success = false, error = "CLAIM_RACE_CONDITION" }
end)

-- 5. RPC: Citizen Emergency Alert & 911 Dispatch Submission
Nyx.RPC.Register("phone:sendEmergencyAlert", function(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    local ok, sanitized = Nyx.Phone.ValidateEmergencyAlertPayload(payload)
    if not ok then
        return { success = false, error = sanitized }
    end

    local citizenId = player.citizenId or (player.getCitizenId and player:getCitizenId())
    local fullName = player.name or (player.getCharName and player:getCharName()) or "Állampolgár"
    local ped = GetPlayerPed(tostring(src))
    local pCoords = GetEntityCoords(ped)
    local coordsTable = { x = pCoords.x, y = pCoords.y, z = pCoords.z }
    local alertUuid = Nyx.RPC.GenerateNonce()
    local now = os.time()

    local alertId = MySQL.insert.await([[
        INSERT INTO `nyx_phone_emergency_alerts`
            (`alert_uuid`, `citizen_id`, `caller_name`, `category`, `message`, `location_label`, `coords_json`, `priority`, `status`, `created_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'broadcasted', ?)
    ]], {
        alertUuid,
        citizenId,
        fullName,
        sanitized.category,
        sanitized.message,
        sanitized.locationLabel,
        json.encode(coordsTable),
        sanitized.priority,
        now
    })

    -- Forward to MDT Dispatch Queue if nyx_mdt is running
    if exports['nyx_mdt'] and exports['nyx_mdt'].CreateCall then
        pcall(function()
            local codeMap = {
                police = "10-99",
                medical = "10-52",
                fire = "10-70",
                traffic = "10-50",
                general = "10-90"
            }
            local code = codeMap[sanitized.category] or "10-99"
            exports['nyx_mdt']:CreateCall(
                code,
                string.format("Segélyhívás: %s", sanitized.category:upper()),
                sanitized.message,
                string.format("%s (%s)", fullName, citizenId),
                coordsTable,
                sanitized.locationLabel,
                sanitized.priority
            )
        end)
    end

    local badge = Nyx.Phone.FormatAlertBadge(sanitized.priority, sanitized.category)
    local alertPacket = {
        id = alertId,
        uuid = alertUuid,
        caller = fullName,
        category = sanitized.category,
        message = sanitized.message,
        location = sanitized.locationLabel,
        priority = sanitized.priority,
        createdAt = now,
        badge = badge
    }

    -- Broadcast to all active citizens
    TriggerClientEvent("nyx:phone:client:emergencyAlert", -1, alertPacket)

    return {
        success = true,
        alertId = alertId,
        alertUuid = alertUuid
    }
end)

-- 6. RPC: Query Public Emergency Alerts
Nyx.RPC.Register("phone:getEmergencyAlerts", function(src)
    local alerts = MySQL.query.await([[
        SELECT `alert_id`, `alert_uuid`, `caller_name`, `category`, `message`, `location_label`, `priority`, `created_at`
        FROM `nyx_phone_emergency_alerts`
        ORDER BY `created_at` DESC
        LIMIT 15
    ]]) or {}

    local alertsFeed = {}
    for _, a in ipairs(alerts) do
        local badge = Nyx.Phone.FormatAlertBadge(a.priority, a.category)
        table.insert(alertsFeed, {
            id = a.alert_id,
            uuid = a.alert_uuid,
            caller = a.caller_name,
            category = a.category,
            message = a.message,
            location = a.location_label,
            priority = a.priority,
            createdAt = a.created_at,
            badge = badge
        })
    end

    return {
        success = true,
        alerts = alertsFeed
    }
end)

-- 7. RPC: Update Phone Settings
Nyx.RPC.Register("phone:updateSettings", function(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    local citizenId = player.citizenId or (player.getCitizenId and player:getCitizenId())
    if not citizenId then return { success = false, error = "INVALID_CITIZEN_ID" } end

    local wallpaper = tostring(payload and payload.wallpaper or "default_dark")
    local darkMode = (payload and payload.darkMode == true) and 1 or 0
    local airplaneMode = (payload and payload.airplaneMode == true) and 1 or 0
    local now = os.time()

    MySQL.prepare.await([[
        UPDATE `nyx_phone_settings`
        SET `wallpaper` = ?, `dark_mode` = ?, `airplane_mode` = ?, `updated_at` = ?
        WHERE `citizen_id` = ?
    ]], { wallpaper, darkMode, airplaneMode, now, citizenId })

    return { success = true }
end)
