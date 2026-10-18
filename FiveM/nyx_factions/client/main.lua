--[[
    Nyxframework: nyx_factions
    File: client/main.lua
    Description: Client notification bridging, vault state synchronization, and faction lifecycle event handlers.
]]

-- 1. Multi-Sig Disbursement Announcement
RegisterNetEvent("nyx:factions:client:multisigDisbursed", function(data)
    TriggerEvent("nyx:ui:notify", {
        type = "success",
        title = "MULTI-SIG DISBURSED",
        message = string.format("Disbursement of $%.2f was approved and executed from corporate vaults.", tonumber(data.amount) or 0.00)
    })
end)

-- 2. Vault Lockdown / Emergency Freeze Event
RegisterNetEvent("nyx:factions:client:vaultFreezeChanged", function(data)
    local isFrozen = data.isFrozen
    TriggerEvent("nyx:ui:notify", {
        type = isFrozen and "error" or "success",
        title = isFrozen and "VAULT LOCKDOWN ACTIVATED" or "VAULT LOCKDOWN LIFTED",
        message = string.format("Vault %s was %s. Reason: %s",
            tostring(data.vaultId), isFrozen and "frozen" or "restored", tostring(data.reason or "Administrative Action"))
    })
end)

-- 3. In-Game Informational Commands for Members
RegisterCommand("corp_vaults", function(source, args)
    local factionId = args[1]
    if not factionId or factionId == "" then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "CORPORATE VAULTS",
            message = "Usage: /corp_vaults <factionId>"
        })
        return
    end

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("factions:getVaults", factionId, function(response)
            if response and response.success and response.vaults then
                TriggerEvent("nyx:ui:notify", {
                    type = "info",
                    title = "CORPORATE VAULTS",
                    message = string.format("Retrieved %d corporate vault(s) for %s.", #response.vaults, factionId)
                })
            else
                TriggerEvent("nyx:ui:notify", {
                    type = "error",
                    title = "VAULT ERROR",
                    message = "Failed to retrieve corporate vaults."
                })
            end
        end)
    end
end, false)
