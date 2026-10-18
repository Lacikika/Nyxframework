--[[
    Nyxframework: nyx_properties
    File: server/billing.lua
    Description: Automated municipal property millage tax assessment,
                 double-entry treasury collection & delinquency monitoring.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}

-- 1. Periodic Millage Tax Assessment Cycle
function Nyx.Properties.ProcessMillageBillingCycle()
    local intervalHours = Config.Millage.BillingIntervalHours or 24
    local treasuryAccount = Config.Millage.TreasuryAccount or "gov:city:master"

    local propsToBill = MySQL.query.await([[
        SELECT `property_id`, `label`, `owner_citizen_id`, `price`, `millage_tax_rate`
        FROM `nyx_properties`
        WHERE `owner_citizen_id` IS NOT NULL 
          AND (`last_tax_billed_at` IS NULL OR `last_tax_billed_at` <= NOW() - INTERVAL ? HOUR)
    ]], { intervalHours })

    if not propsToBill or #propsToBill == 0 then return end

    local billedCount = 0
    local delinquentCount = 0

    for _, p in ipairs(propsToBill) do
        local price = tonumber(p.price) or 0.00
        local rate = tonumber(p.millage_tax_rate) or (Config.Millage.DefaultMillageRate or 0.0150)
        local taxDue = math.floor((price * rate) * 100) / 100

        if taxDue > 0 then
            local citizenId = p.owner_citizen_id
            local ownerPlayer = exports['nyx_core']:GetPlayerByCitizenId(citizenId)

            local debitSuccess = false
            local bankBal = 0

            if ownerPlayer then
                bankBal = ownerPlayer:getWallet("bank") or 0
                if bankBal >= taxDue then
                    ownerPlayer:removeMoney("bank", taxDue, string.format("Városi Építményadó (Millage Tax): %s", p.label))
                    debitSuccess = true
                end
            else
                -- Offline citizen account check via database
                local charRow = MySQL.single.await("SELECT `money` FROM `nyx_characters` WHERE `citizen_id` = ?", { citizenId })
                if charRow and charRow.money then
                    local moneyData = json.decode(charRow.money) or {}
                    local offlineBank = tonumber(moneyData.bank) or 0
                    if offlineBank >= taxDue then
                        moneyData.bank = offlineBank - taxDue
                        MySQL.prepare("UPDATE `nyx_characters` SET `money` = ? WHERE `citizen_id` = ?", { json.encode(moneyData), citizenId })
                        debitSuccess = true
                    end
                end
            end

            if debitSuccess then
                -- Credit Municipal Treasury via oxmysql prepared statement
                exports['nyx_treasury']:EnsureAccount(treasuryAccount, "City Treasury", "department", 0.00)
                MySQL.prepare([[
                    UPDATE `nyx_treasury_accounts` SET `balance` = `balance` + ? WHERE `account_id` = ?
                ]], { taxDue, treasuryAccount })

                -- Log in treasury ledger
                MySQL.prepare([[
                    INSERT INTO `nyx_treasury_ledger`
                        (`tx_uuid`, `category`, `debit_account`, `credit_account`, `amount`, `memo`)
                    VALUES (UUID(), 'property_tax', ?, ?, ?, ?)
                ]], {
                    string.format("char:%s:bank", citizenId),
                    treasuryAccount,
                    taxDue,
                    string.format("Millage Property Tax: Property #%d (%s)", p.property_id, p.label)
                })

                -- Audit trail
                MySQL.prepare([[
                    INSERT INTO `nyx_property_audit`
                        (`property_id`, `action`, `actor_citizen_id`, `amount`, `notes`)
                    VALUES (?, 'MILLAGE_TAX_DEBIT', ?, ?, 'Statutory property tax collected')
                ]], { p.property_id, citizenId, taxDue })

                MySQL.prepare("UPDATE `nyx_properties` SET `last_tax_billed_at` = NOW() WHERE `property_id` = ?", { p.property_id })
                billedCount = billedCount + 1

                if ownerPlayer then
                    TriggerClientEvent("nyx:ui:notify", ownerPlayer.source, {
                        type = "info",
                        title = "ÉPÍTMÉNYADÓ LEVONVA",
                        message = string.format("Levonva: $%.2f ingatlanadó a(z) %s után.", taxDue, p.label)
                    })
                end
            else
                delinquentCount = delinquentCount + 1
                if Config.Debug then
                    print(string.format("^1[Nyx:Properties] Delinquency Alert: Citizen %s cannot cover $%.2f millage tax for Property #%d^7", citizenId, taxDue, p.property_id))
                end
            end
        end
    end

    if Config.Debug and (billedCount > 0 or delinquentCount > 0) then
        print(string.format("^3[Nyx:Properties:Billing] Tax assessment complete: %d settled, %d delinquent.^7", billedCount, delinquentCount))
    end
end

-- 2. Periodic Millage Heartbeat (Every 30 minutes check)
CreateThread(function()
    while true do
        Wait(1800000) -- 30 minutes tick
        Nyx.Properties.ProcessMillageBillingCycle()
    end
end)
