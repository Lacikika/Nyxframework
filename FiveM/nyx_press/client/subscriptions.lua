--[[
    Nyxframework: nyx_press
    File: client/subscriptions.lua
    Description: Client-side subscription commands, whistleblower bounty claims at dropboxes,
                 and subscriber issue delivery listeners.
]]

Nyx = Nyx or {}
Nyx.Press = Nyx.Press or {}

-- ----------------------------------------------------------------------------
-- 1. Subscription Chat Commands
-- ----------------------------------------------------------------------------

-- /pressplans [outletId]
RegisterCommand("pressplans", function(source, args)
    local outletId = args[1]
    local p = Nyx.RPC.Call("press:getSubscriptionPlans", outletId)
    p:next(function(plans)
        if plans and #plans > 0 then
            local msg = "Elérhető sajtó előfizetési csomagok:\n"
            for _, pl in ipairs(plans) do
                local typeLabel = pl.plan_type == "print_delivery" and "Nyomtatott Házhozszállítás" or "Digitális Hírfolyam"
                msg = msg .. string.format("• [%s] %s (%s) - $%.2f / hét\n",
                    pl.plan_id, pl.name, typeLabel, tonumber(pl.price) or 25.0)
            end
            TriggerEvent("nyx:ui:notify", {
                type = "info",
                title = "SAJTÓ ELŐFIZETÉSEK",
                message = msg,
                duration = 12000
            })
        else
            TriggerEvent("nyx:ui:notify", {
                type = "warning",
                title = "SAJTÓ ELŐFIZETÉSEK",
                message = "Jelenleg nincsenek aktív előfizetési csomagok.",
                duration = 5000
            })
        end
    end)
end, false)

-- /mysubscriptions
RegisterCommand("mysubscriptions", function()
    local p = Nyx.RPC.Call("press:getMySubscriptions", {})
    p:next(function(subs)
        if subs and #subs > 0 then
            local msg = "Aktív sajtó előfizetéseid:\n"
            for _, s in ipairs(subs) do
                local badge = Nyx.Press.Subscriptions and Nyx.Press.Subscriptions.FormatSubscriptionBadge(s.status) or { text = s.status }
                msg = msg .. string.format("• %s [%s] - Érvényes: %s | Auto-megújítás: %s\n",
                    s.plan_name or s.plan_id, badge.text, s.current_period_end or "N/A", s.auto_renew == 1 and "Igen" or "Nem")
            end
            TriggerEvent("nyx:ui:notify", {
                type = "info",
                title = "ELŐFIZETÉSEIM",
                message = msg,
                duration = 10000
            })
        else
            TriggerEvent("nyx:ui:notify", {
                type = "info",
                title = "ELŐFIZETÉSEIM",
                message = "Nincs aktív újság- vagy média-előfizetésed. Csomagok: /pressplans",
                duration = 6000
            })
        end
    end)
end, false)

-- /subscribepress <planId> [propertyId]
RegisterCommand("subscribepress", function(source, args)
    if #args < 1 then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "SAJTÓ ELŐFIZETÉS",
            message = "Használat: /subscribepress <CsomagID> [IngatlanID nyomtatott szállításhoz]\nPélda: /subscribepress plan_daily_globe_print prop_vinewood_01",
            duration = 8000
        })
        return
    end

    local planId = args[1]
    local propId = args[2]

    local p = Nyx.RPC.Call("press:subscribe", {
        planId = planId,
        deliveryPropertyId = propId
    })

    p:next(function(res)
        if res and res.success then
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "ELŐFIZETÉS AKTIVÁLVA",
                message = string.format("Sikeresen előfizettél: '%s' ($%.2f / hét). Előfizetés azonosító: %s",
                    res.planName, res.price, res.subscriptionId),
                duration = 8000
            })
        else
            local err = res and res.error or "UNKNOWN_ERROR"
            local details = {
                ['PLAN_NOT_FOUND'] = "A megadott előfizetési csomag nem létezik.",
                ['ALREADY_SUBSCRIBED_TO_OUTLET'] = "Már rendelkezel aktív előfizetéssel ehhez a kiadóhoz!",
                ['INSUFFICIENT_FUNDS'] = "Nincs elegendő fedezet a számládon az előfizetéshez.",
                ['TREASURY_SETTLEMENT_FAILED'] = "Pénzügyi tranzakciós hiba a banki levonás során."
            }
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "ELŐFIZETÉS SIKERTELEN",
                message = details[err] or ("Hiba: " .. tostring(err)),
                duration = 6000
            })
        end
    end)
end, false)

-- /cancelsubscription <subId>
RegisterCommand("cancelsubscription", function(source, args)
    if #args < 1 then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "ELŐFIZETÉS LEMONDÁSA",
            message = "Használat: /cancelsubscription <ElőfizetésID>",
            duration = 5000
        })
        return
    end

    local subId = args[1]
    local p = Nyx.RPC.Call("press:cancelSubscription", subId)
    p:next(function(res)
        if res and res.success then
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "ELŐFIZETÉS LEMONDVA",
                message = res.message or "Az automatikus megújítás törölve.",
                duration = 6000
            })
        else
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "LEMONDÁS SIKERTELEN",
                message = "Hiba: " .. tostring(res and res.error or "Ismeretlen hiba"),
                duration = 5000
            })
        end
    end)
end, false)

-- ----------------------------------------------------------------------------
-- 2. Whistleblower Bounty Commands
-- ----------------------------------------------------------------------------

-- /awardbounty <leakId> <amount> (Journalist / Media Leadership only)
RegisterCommand("awardbounty", function(source, args)
    if #args < 2 then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "JUTALÉK KIÍRÁSA",
            message = "Használat: /awardbounty <LeakID> <Összeg>",
            duration = 6000
        })
        return
    end

    local leakId = args[1]
    local amount = tonumber(args[2]) or 0.0

    local p = Nyx.RPC.Call("press:awardBounty", {
        leakId = leakId,
        amount = amount
    })

    p:next(function(res)
        if res and res.success then
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "JUTALÉK KIUTALVA ESCROW-BA",
                message = string.format("Sikeresen kiutaltál $%.2f jutalékot a(z) '%s' kiszivárogtatás forrásának! [Bounty ID: %s]",
                    res.amount, res.leakId, res.bountyId),
                duration = 8000
            })
        else
            local err = res and res.error or "UNKNOWN_ERROR"
            local details = {
                ['PRESS_ACCREDITATION_REQUIRED'] = "Kizárólag akkreditált újságíró vagy sajtóvezető utalhat ki jutalékot!",
                ['INSUFFICIENT_ESCROW_BALANCE'] = "Nincs elegendő fedezet a kiadó oknyomozói escrow számláján!",
                ['BOUNTY_ALREADY_AWARDED_FOR_LEAK'] = "Ehhez a kiszivárogtatáshoz már ki lett írva jutalék!",
                ['INVALID_LEAK_STATUS'] = "A kiszivárogtatásnak vizsgálat alatt vagy publikálva kell lennie!"
            }
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "JUTALÉK KIÍRÁS SIKERTELEN",
                message = details[err] or ("Hiba: " .. tostring(err)),
                duration = 6000
            })
        end
    end)
end, false)

-- /claimbounty <bountyId> <salt> <nonce>
RegisterCommand("claimbounty", function(source, args)
    if #args < 3 then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "JUTALÉK FELVÉTELE",
            message = "Használat: /claimbounty <BountyID> <Salt> <Nonce>\n(A kiszivárogtatáskor kapott titkos salt és nonce szükséges!)",
            duration = 8000
        })
        return
    end

    local bountyId = args[1]
    local salt = args[2]
    local nonce = args[3]

    local p = Nyx.RPC.Call("press:claimBounty", {
        bountyId = bountyId,
        salt = salt,
        nonce = nonce,
        dropboxId = "drop_metro_subway"
    })

    p:next(function(res)
        if res and res.success then
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "JUTALÉK KIFIZETVE",
                message = res.message,
                duration = 9000
            })
        else
            local err = res and res.error or "UNKNOWN_ERROR"
            local details = {
                ['CRYPTOGRAPHIC_PROOF_VERIFICATION_FAILED'] = "Érvénytelen forrásigazolás! A megadott salt/nonce nem egyezik a lenyomattal.",
                ['BOUNTY_ALREADY_CLAIMED_OR_RESOLVED'] = "Ez a jutalék már fel lett véve vagy nem érvényes.",
                ['BOUNTY_NOT_FOUND'] = "A megadott azonosítójú jutalék nem található."
            }
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "JUTALÉK FELVÉTEL SIKERTELEN",
                message = details[err] or ("Hiba: " .. tostring(err)),
                duration = 6000
            })
        end
    end)
end, false)

-- /bounties
RegisterCommand("bounties", function()
    local p = Nyx.RPC.Call("press:getAvailableBounties", {})
    p:next(function(bounties)
        if bounties and #bounties > 0 then
            local msg = "Aktív anonim kiszivárogtatói jutalékok:\n"
            for _, b in ipairs(bounties) do
                msg = msg .. string.format("• [%s] $%.2f (%s) - '%s'\n",
                    b.bounty_id, tonumber(b.bounty_amount) or 0.0, b.outlet_id, b.leak_title or "Bizalmas anyag")
            end
            TriggerEvent("nyx:ui:notify", {
                type = "info",
                title = "OKNYOMOZÓI JUTALÉKOK",
                message = msg,
                duration = 10000
            })
        else
            TriggerEvent("nyx:ui:notify", {
                type = "info",
                title = "OKNYOMOZÓI JUTALÉKOK",
                message = "Jelenleg nincsenek nyitott kiszivárogtatói jutalékok.",
                duration = 5000
            })
        end
    end)
end, false)

-- ----------------------------------------------------------------------------
-- 3. Event Listeners
-- ----------------------------------------------------------------------------

RegisterNetEvent("nyx:press:client:bountyAvailable", function(data)
    if not data then return end
    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = "ÚJ OKNYOMOZÓI JUTALÉK",
        message = string.format("A(z) %s $%.2f jutalékot írt ki a(z) '%s' c. anyag forrásának! [ID: %s]",
            data.outletId or "Sajtó", tonumber(data.amount) or 0.0, data.leakTitle or "Ügy", data.bountyId),
        duration = 8000
    })
end)
