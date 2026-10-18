--[[
    Nyxframework: nyx_services
    File: client/metering.lua
    Description: Client-side municipal utility metering, delinquency notifications,
                 sound effects, and chat commands.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}

-- Network Event: Power & Water Cut-off Enforced
RegisterNetEvent("nyx:services:client:utilityCutoffEnforced", function(meterId, propertyId)
    -- Play high-voltage circuit trip sound
    PlaySoundFrontend(-1, "Bed", "WastedSounds", true)

    TriggerEvent("nyx:ui:notify", {
        type = "error",
        title = "KÖZMŰVEK LEKAPCSOLVA",
        message = string.format("Közműtartozás miatt az áram- és vízszolgáltatás lekapcsolásra került! (Mérőóra: %s)", tostring(meterId))
    })
end)

-- Network Event: Service Reconnected & Power Restored
RegisterNetEvent("nyx:services:client:utilityReconnected", function(meterId, propertyId)
    -- Play circuit breaker energize sound
    PlaySoundFrontend(-1, "Hack_Success", "DLC_HEIST_BIOLAB_PREP_TRACKING_SOUNDS", true)

    TriggerEvent("nyx:ui:notify", {
        type = "success",
        title = "KÖZMŰVEK VISSZAKAPCSOLVA",
        message = string.format("A közműtartozás rendezve. Az áram- és vízszolgáltatás helyreállt! (Mérőóra: %s)", tostring(meterId))
    })
end)

-- Chat Command: Query Meter Telemetry
RegisterCommand("checkmeter", function(source, args)
    local meterId = args[1]
    if not meterId or meterId == "" then
        TriggerEvent("chat:addMessage", {
            color = { 255, 180, 0 },
            args = { "Közművek", "Használat: /checkmeter <meter_id vagy property_code>" }
        })
        return
    end

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("services:getMeter", meterId)
        if res and res.success and res.meter then
            local m = res.meter
            local badge, label = "^2[AKTÍV]^7", "Aktív"
            if Nyx.Metering and Nyx.Metering.FormatMeterStatusBadge then
                badge, label = Nyx.Metering.FormatMeterStatusBadge(m.meter_status or "active")
            end

            local msg = string.format([[
^5=== KÖZMŰÓRA TELEMETRIA ===^7
• Mérőóra: ^3%s^7 (%s)
• Ingatlan: ^3%s^7
• Alállomás: ^3%s^7
• Állapot: %s (%s)
• Áramfogyasztás: ^2%.2f kWh^7
• Vízfogyasztás: ^2%.2f Gal^7
• Esedékes Hátralék: ^1$%.2f^7
^5==============================^7]],
                m.meter_id, m.property_type, m.property_label or "N/A", m.linked_substation_id,
                badge, label,
                tonumber(m.kwh_consumed) or 0.0,
                tonumber(m.water_consumed) or 0.0,
                tonumber(m.unpaid_balance) or 0.0)

            TriggerEvent("chat:addMessage", {
                color = { 70, 180, 255 },
                multiline = true,
                args = { "Közművek", msg }
            })
        else
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "MÉRŐÓRA NEM TALÁLHATÓ",
                message = "A megadott mérőóra nem szerepel a nyilvántartásban."
            })
        end
    end
end, false)

-- Chat Command: Pay Utility Arrears
RegisterCommand("payutility", function(source, args)
    local meterId = args[1]
    local amount = tonumber(args[2])

    if not meterId then
        TriggerEvent("chat:addMessage", {
            color = { 255, 180, 0 },
            args = { "Közművek", "Használat: /payutility <meter_id> [összeg]" }
        })
        return
    end

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local res = exports['nyx_core']:TriggerRPCAwait("services:payUtilityBill", meterId, amount)
        if res and res.success and res.data then
            local d = res.data
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "KÖZMŰSZÁMLA BEFIZETVE",
                message = string.format("Befizetve: $%.2f. Hátralévő tartozás: $%.2f.", d.paid or 0.0, d.remaining or 0.0)
            })
            if d.reconnected then
                TriggerEvent("nyx:ui:notify", {
                    type = "success",
                    title = "SZOLGÁLTATÁS HELYREÁLLT",
                    message = "Az áram- és vízszolgáltatás azonnal visszakapcsolásra került!"
                })
            end
        else
            local err = res and res.error or "Ismeretlen hiba történt a befizetés során."
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "SIKERTELEN BEFIZETÉS",
                message = string.format("Hiba: %s", tostring(err))
            })
        end
    end
end, false)
