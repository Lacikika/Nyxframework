--[[
    Nyxframework: nyx_factions
    File: server/laundering.lua
    Description: Authoritative server engine for commercial front cash registers,
                 illicit cash injections, drip laundering double-entry integration,
                 and judicial asset freezing.
]]

Nyx = Nyx or {}
Nyx.Factions = Nyx.Factions or {}
Nyx.Laundering = Nyx.Laundering or {}
Nyx.Laundering.Registers = {} -- [register_id] = registerData

local function generateUuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end))
end

-- 1. Hydrate Commercial Registers into memory cache
function Nyx.Laundering.HydrateRegisters()
    local rows = MySQL.query.await([[
        SELECT `register_id`, `faction_id`, `label`, `business_type`, `clean_cash_balance`,
               `dirty_cash_pool`, `total_washed`, `total_tax_paid`, `max_daily_laundering_cap`,
               `daily_laundered_amount`, `last_cap_reset`, `wash_rate_pct`, `drip_amount_per_tick`,
               `coords`, `is_active`, `is_frozen`, `frozen_by`, `freeze_reason`
        FROM `nyx_factions_commercial_registers`
    ]]) or {}

    for _, row in ipairs(rows) do
        local coords = nil
        if row.coords and type(row.coords) == "string" and #row.coords > 0 then
            local ok, parsed = pcall(json.decode, row.coords)
            if ok and type(parsed) == "table" then coords = parsed end
        elseif type(row.coords) == "table" then
            coords = row.coords
        end

        Nyx.Laundering.Registers[row.register_id] = {
            register_id = row.register_id,
            faction_id = row.faction_id,
            label = row.label,
            business_type = row.business_type,
            clean_cash_balance = tonumber(row.clean_cash_balance) or 0.00,
            dirty_cash_pool = tonumber(row.dirty_cash_pool) or 0.00,
            total_washed = tonumber(row.total_washed) or 0.00,
            total_tax_paid = tonumber(row.total_tax_paid) or 0.00,
            max_daily_laundering_cap = tonumber(row.max_daily_laundering_cap) or 50000.00,
            daily_laundered_amount = tonumber(row.daily_laundered_amount) or 0.00,
            last_cap_reset = row.last_cap_reset,
            wash_rate_pct = tonumber(row.wash_rate_pct) or 80.00,
            drip_amount_per_tick = tonumber(row.drip_amount_per_tick) or 2500.00,
            coords = coords,
            is_active = tonumber(row.is_active) or 1,
            is_frozen = tonumber(row.is_frozen) or 0,
            frozen_by = row.frozen_by,
            freeze_reason = row.freeze_reason
        }
    end

    if Config.Debug then
        print(string.format("^2[Nyx:Factions] Hydrated %d commercial front cash registers.^7", #rows))
    end
end

-- 2. Query Register Helpers
function Nyx.Laundering.GetRegister(registerId)
    if not registerId then return nil end
    return Nyx.Laundering.Registers[registerId]
end

function Nyx.Laundering.GetFactionRegisters(factionId)
    local list = {}
    if not factionId then return list end
    for _, reg in pairs(Nyx.Laundering.Registers) do
        if reg.faction_id == factionId then
            table.insert(list, reg)
        end
    end
    return list
end

-- 3. Authoritative Dirty Cash Injection
function Nyx.Laundering.InjectDirtyCash(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local okVal, cleanPayload = Nyx.Laundering.ValidateInjectionPayload({
        registerId = payload and payload.registerId,
        amount = payload and payload.amount,
        citizenId = player.citizenId,
        sourceNote = payload and payload.sourceNote
    })

    if not okVal then return false, cleanPayload end

    local reg = Nyx.Laundering.Registers[cleanPayload.registerId]
    if not reg then return false, "REGISTER_NOT_FOUND" end

    -- Verify authorization: citizen must belong to faction or hold treasury privileges
    local isMember = exports['nyx_factions']:HasPermission(player.citizenId, reg.faction_id, "treasury:deposit")
    if not isMember then
        -- Also allow founders / syndicate associates
        local faction = exports['nyx_factions']:GetFaction(reg.faction_id)
        if not faction then return false, "FACTION_NOT_FOUND" end
    end

    local okElig, eligData = Nyx.Laundering.EvaluateRegisterEligibility(reg, cleanPayload.amount)
    if not okElig then return false, eligData end

    -- Deduct illicit cash from player: check inventory items first, then wallets
    local deducted = false
    local amount = cleanPayload.amount

    if exports['nyx_inventory'] and exports['nyx_inventory'].HasItem then
        local count = exports['nyx_inventory']:HasItem(src, "dirty_money")
        if count and count > 0 then
            local stacksNeeded = math.ceil(amount / 1000.0)
            if count >= stacksNeeded then
                exports['nyx_inventory']:RemoveItem(src, "dirty_money", stacksNeeded)
                deducted = true
            end
        end
    end

    if not deducted then
        -- Check player wallets: dirty_cash / black_money
        local dirtyBal = player:getWallet("dirty_cash") or player:getWallet("black_money") or 0
        if dirtyBal >= amount then
            if player:getWallet("dirty_cash") >= amount then
                player:removeMoney("dirty_cash", amount, "Commercial Register Laundering Intake")
            else
                player:removeMoney("black_money", amount, "Commercial Register Laundering Intake")
            end
            deducted = true
        elseif (player:getWallet("cash") or 0) >= amount then
            -- Allow standard cash tagged as illicit intake
            player:removeMoney("cash", amount, "Commercial Register Laundering Deposit")
            deducted = true
        end
    end

    if not deducted then
        return false, "INSUFFICIENT_ILLICIT_CASH"
    end

    local injectionUuid = generateUuid()

    -- Atomic Database Update
    MySQL.prepare.await([[
        UPDATE `nyx_factions_commercial_registers`
        SET `dirty_cash_pool` = `dirty_cash_pool` + ?
        WHERE `register_id` = ?
    ]], { amount, cleanPayload.registerId })

    MySQL.prepare.await([[
        INSERT INTO `nyx_factions_laundering_injections`
        (`injection_uuid`, `register_id`, `faction_id`, `citizen_id`, `amount`, `source_note`, `status`)
        VALUES (?, ?, ?, ?, ?, ?, 'queued')
    ]], {
        injectionUuid,
        cleanPayload.registerId,
        reg.faction_id,
        player.citizenId,
        amount,
        cleanPayload.sourceNote
    })

    -- Update memory cache
    reg.dirty_cash_pool = reg.dirty_cash_pool + amount

    TriggerClientEvent("nyx:core:client:notify", src, {
        type = "success",
        title = "Pénztárgép Befizetés",
        message = string.format("$%.2f készpénz elhelyezve a(z) %s pénztárgépben.", amount, reg.label)
    })

    return true, {
        injectionUuid = injectionUuid,
        registerId = cleanPayload.registerId,
        amount = amount,
        newDirtyPool = reg.dirty_cash_pool
    }
end

-- 4. Process Periodic Drip Laundering Cycle for a Register
function Nyx.Laundering.ProcessRegisterLaunderingTick(registerId)
    local reg = Nyx.Laundering.Registers[registerId]
    if not reg then return false, "REGISTER_NOT_FOUND" end

    if reg.is_active ~= 1 or reg.is_frozen == 1 then
        return false, "REGISTER_INACTIVE_OR_FROZEN"
    end

    if reg.dirty_cash_pool <= 0.00 then
        return false, "DIRTY_POOL_EMPTY"
    end

    local remainingCap = math.max(0.00, reg.max_daily_laundering_cap - reg.daily_laundered_amount)
    local washAmount = Nyx.Laundering.CalculateDripAmount(reg.dirty_cash_pool, reg.drip_amount_per_tick, remainingCap)
    if washAmount <= 0.00 then
        return false, "DAILY_CAP_REACHED"
    end

    local municipalTaxRate = 10.0
    if exports['nyx_treasury'] and exports['nyx_treasury'].GetZoneTaxRate then
        municipalTaxRate = exports['nyx_treasury']:GetZoneTaxRate("zone_commercial") or 10.0
    end

    local split = Nyx.Laundering.CalculateLaunderingSplit(washAmount, reg.business_type, municipalTaxRate)
    if not split.isValid then
        return false, "INVALID_SPLIT_CALCULATION"
    end

    local clearingAcc = "pool:laundering:clearing"
    local corpAcc = "faction:" .. reg.faction_id
    local municipalTaxAcc = "gov:city:tax"

    -- Ensure clearing pool has sufficient book liquidity for double-entry settlement
    if exports['nyx_treasury'] and exports['nyx_treasury'].EnsureAccount then
        exports['nyx_treasury']:EnsureAccount(clearingAcc, "Laundering Clearing Pool", "reserve", 1000000.00)
    end

    -- Transaction Leg 1: Clean proceeds credited to faction operating account
    local cleanOk, cleanTx = exports['nyx_treasury']:ExecuteTransfer(
        clearingAcc,
        corpAcc,
        split.clean,
        "laundering_clean_deposit",
        "SYSTEM_LAUNDERING_ENGINE",
        string.format("Daily retail register receipts: %s (%s)", reg.label, reg.business_type),
        0.00
    )

    if not cleanOk then
        return false, "TREASURY_CLEAN_TRANSFER_FAILED"
    end

    -- Transaction Leg 2: Municipal Point-of-Sale sales tax remittance
    if split.tax > 0.00 then
        exports['nyx_treasury']:ExecuteTransfer(
            clearingAcc,
            municipalTaxAcc,
            split.tax,
            "sales_tax",
            "SYSTEM_LAUNDERING_ENGINE",
            string.format("Point-of-sale tax remittance: %s", reg.label),
            0.00
        )
    end

    -- Update database counters
    MySQL.prepare.await([[
        UPDATE `nyx_factions_commercial_registers`
        SET `dirty_cash_pool` = `dirty_cash_pool` - ?,
            `clean_cash_balance` = `clean_cash_balance` + ?,
            `total_washed` = `total_washed` + ?,
            `total_tax_paid` = `total_tax_paid` + ?,
            `daily_laundered_amount` = `daily_laundered_amount` + ?
        WHERE `register_id` = ?
    ]], { washAmount, split.clean, split.clean, split.tax, washAmount, registerId })

    -- Update memory cache
    reg.dirty_cash_pool = math.max(0.00, reg.dirty_cash_pool - washAmount)
    reg.clean_cash_balance = reg.clean_cash_balance + split.clean
    reg.total_washed = reg.total_washed + split.clean
    reg.total_tax_paid = reg.total_tax_paid + split.tax
    reg.daily_laundered_amount = reg.daily_laundered_amount + washAmount

    return true, {
        registerId = registerId,
        washedGross = washAmount,
        cleanCredited = split.clean,
        taxRemitted = split.tax,
        overheadBurned = split.overhead,
        remainingDirtyPool = reg.dirty_cash_pool,
        txUuid = cleanTx
    }
end

-- 5. Freeze & Unfreeze Commercial Register
function Nyx.Laundering.FreezeRegister(registerId, judgeCitId, reason)
    local reg = Nyx.Laundering.Registers[registerId]
    if not reg then return false, "REGISTER_NOT_FOUND" end

    MySQL.prepare.await([[
        UPDATE `nyx_factions_commercial_registers`
        SET `is_frozen` = 1, `frozen_by` = ?, `freeze_reason` = ?
        WHERE `register_id` = ?
    ]], { judgeCitId or "JUDICIAL_WARRANT", reason or "Subpoena Restraining Order", registerId })

    reg.is_frozen = 1
    reg.frozen_by = judgeCitId
    reg.freeze_reason = reason

    return true
end

function Nyx.Laundering.UnfreezeRegister(registerId, judgeCitId)
    local reg = Nyx.Laundering.Registers[registerId]
    if not reg then return false, "REGISTER_NOT_FOUND" end

    MySQL.prepare.await([[
        UPDATE `nyx_factions_commercial_registers`
        SET `is_frozen` = 0, `frozen_by` = NULL, `freeze_reason` = NULL
        WHERE `register_id` = ?
    ]], { registerId })

    reg.is_frozen = 0
    reg.frozen_by = nil
    reg.freeze_reason = nil

    return true
end

-- 6. Background Drip Sweeper Thread
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(100)
    end
    Wait(500)
    Nyx.Laundering.HydrateRegisters()

    while true do
        Wait(60000) -- Check every 60 seconds
        for regId, reg in pairs(Nyx.Laundering.Registers) do
            if reg.is_active == 1 and reg.is_frozen == 0 and reg.dirty_cash_pool > 0.00 then
                pcall(function()
                    Nyx.Laundering.ProcessRegisterLaunderingTick(regId)
                end)
            end
        end
    end
end)

-- 7. Register RPC Handlers
CreateThread(function()
    while not exports['nyx_core'] or not exports['nyx_core'].RegisterRPC do
        Wait(50)
    end

    exports['nyx_core']:RegisterRPC("factions:getCommercialRegisters", function(src, factionId)
        return true, Nyx.Laundering.GetFactionRegisters(factionId)
    end)

    exports['nyx_core']:RegisterRPC("factions:injectDirtyCash", function(src, payload)
        return Nyx.Laundering.InjectDirtyCash(src, payload)
    end)

    exports['nyx_core']:RegisterRPC("factions:getRegisterDetails", function(src, registerId)
        local reg = Nyx.Laundering.GetRegister(registerId)
        if not reg then return false, "REGISTER_NOT_FOUND" end
        return true, reg
    end)

    exports['nyx_core']:RegisterRPC("factions:processLaunderingTick", function(src, registerId)
        return Nyx.Laundering.ProcessRegisterLaunderingTick(registerId)
    end)

    exports['nyx_core']:RegisterRPC("factions:freezeRegister", function(src, registerId, reason)
        local player = exports['nyx_core']:GetPlayer(src)
        if not player then return false, "UNAUTHENTICATED" end
        return Nyx.Laundering.FreezeRegister(registerId, player.citizenId, reason)
    end)
end)
