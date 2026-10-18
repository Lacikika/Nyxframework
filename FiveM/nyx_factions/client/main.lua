--[[
    Nyxframework: nyx_factions
    File: client/main.lua
    Description: Client notification bridging and faction lifecycle event handlers.
]]

-- 1. Multi-Sig Disbursement Announcement
RegisterNetEvent("nyx:factions:client:multisigDisbursed", function(data)
    TriggerEvent("nyx:ui:notify", {
        type = "success",
        title = "MULTI-SIG DISBURSED",
        message = string.format("High-tier withdrawal of $%.2f was approved by certified quorum.", data.amount)
    })
end)
