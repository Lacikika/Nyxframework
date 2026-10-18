--[[
    Nyxframework: nyx_treasury
    File: client/subpoena_audit.lua
    Description: Client-side commands and inspection view for judicial subpoena audits.
]]

Nyx = Nyx or {}
Nyx.SubpoenaAudit = Nyx.SubpoenaAudit or {}

-- Execute Forensic Subpoena Audit Command: /subpoenaaudit [warrantId] [targetId] [targetType]
RegisterCommand("subpoenaaudit", function(_, args)
    local warrantId = args[1]
    local targetId = args[2]
    local targetType = args[3] or "faction"

    if not warrantId or not targetId then
        TriggerEvent("chat:addMessage", {
            color = { 255, 120, 0 },
            multiline = true,
            args = { "[Bírósági Idézés]", "Használat: /subpoenaaudit [warrantId] [targetId] [faction/register]" }
        })
        return
    end

    if exports['nyx_core'] and exports['nyx_core'].CallRPC then
        TriggerEvent("chat:addMessage", {
            color = { 200, 200, 200 },
            multiline = true,
            args = { "[Igazságügy]", string.format("Főkönyvi auditálás folyamatban a(z) '%s' célszemély/szervezet ellen...", targetId) }
        })

        local success, result = exports['nyx_core']:CallRPC("treasury:executeSubpoenaAudit", {
            warrantId = warrantId,
            targetType = targetType,
            targetId = targetId
        })

        if success and type(result) == "table" then
            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
            TriggerEvent("chat:addMessage", {
                color = { 100, 255, 150 },
                multiline = true,
                args = {
                    "[Audit Eredmény]",
                    string.format("Cél: %s (%s) | Kockázati szint: %s\nAnomália pontszám: %.2f/100.00 | Készpénz arány: %.1f%%\nSHA-256 Jelzés: %s\nAjánlás: %s",
                        result.targetId, result.businessType or targetType,
                        string.upper(result.suspicionLevel or "clean"),
                        result.anomalyScore or 0.0,
                        result.cashRatioPct or 0.0,
                        (result.reportHash or ""):sub(1, 16) .. "...",
                        result.recommendation or "N/A"
                    )
                }
            })
        else
            TriggerEvent("chat:addMessage", {
                color = { 255, 80, 80 },
                multiline = true,
                args = { "[Audit Sikertelen]", string.format("Hiba történt: %s", tostring(result)) }
            })
        end
    end
end, false)

-- Freeze Commercial Target Command: /freezebusiness [warrantId] [targetId] [reason]
RegisterCommand("freezebusiness", function(_, args)
    local warrantId = args[1]
    local targetId = args[2]
    local reason = args[3] or "Bírósági vagyonzár / Idézési határozat"

    if not warrantId or not targetId then
        TriggerEvent("chat:addMessage", {
            color = { 255, 120, 0 },
            multiline = true,
            args = { "[Igazságügy]", "Használat: /freezebusiness [warrantId] [targetId] [indoklás]" }
        })
        return
    end

    if exports['nyx_core'] and exports['nyx_core'].CallRPC then
        local success, result = exports['nyx_core']:CallRPC("treasury:freezeCommercialTarget", {
            warrantId = warrantId,
            targetType = "faction",
            targetId = targetId,
            reason = reason
        })

        if success then
            TriggerEvent("chat:addMessage", {
                color = { 255, 100, 100 },
                multiline = true,
                args = { "[Vagyonzár]", string.format("A(z) %s kereskedelmi számlái és pénztárgépei sikeresen zárolva bírósági végzéssel.", targetId) }
            })
        else
            TriggerEvent("chat:addMessage", {
                color = { 255, 80, 80 },
                multiline = true,
                args = { "[Zárolás Sikertelen]", string.format("Hiba: %s", tostring(result)) }
            })
        end
    end
end, false)
