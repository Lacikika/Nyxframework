--[[
    Nyxframework: nyx_judiciary
    File: client/main.lua
    Description: Client event listeners, notifications, prison timer display, and judicial broadcasts.
]]

-- 1. Warrant Broadcasts (MDT Integration)
RegisterNetEvent("nyx:judiciary:client:warrantIssued", function(warrant)
    TriggerEvent("nyx:ui:notify", {
        type = "warning",
        title = "JUDICIAL WARRANT ISSUED",
        message = string.format("Warrant #%s issued for Citizen ID %s (%s).",
            tostring(warrant.warrantId), tostring(warrant.targetCitizenId), string.upper(warrant.type or "arrest"))
    })
end)

RegisterNetEvent("nyx:judiciary:client:warrantUpdated", function(data)
    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = "WARRANT STATUS UPDATED",
        message = string.format("Warrant #%s status changed to: %s.",
            tostring(data.warrantId), string.upper(data.status or "executed"))
    })
end)

-- 2. Verdict Announcements
RegisterNetEvent("nyx:judiciary:client:verdictAnnounced", function(verdict)
    TriggerEvent("nyx:ui:notify", {
        type = (verdict.ruling == "guilty") and "error" or "success",
        title = "COURT VERDICT RENDERED",
        message = string.format("Case %s: Ruling: %s | Fines: $%.2f | Sentence: %d months",
            verdict.docketId, string.upper(verdict.ruling), verdict.fine + verdict.restitution, verdict.sentenceMonths)
    })
end)

RegisterNetEvent("nyx:judiciary:client:juryVerdictReached", function(juryData)
    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = "JURY VERDICT REACHED",
        message = string.format("The jury has concluded deliberations on %s with outcome: %s.",
            juryData.docketId, string.upper(juryData.ruling))
    })
end)

-- 3. Incarceration Handler
RegisterNetEvent("nyx:judiciary:client:sentenced", function(data)
    TriggerEvent("nyx:ui:notify", {
        type = "error",
        title = "INCARCERATED",
        message = string.format("You have been committed to Bolingbroke State Penitentiary for %d months.", data.sentenceMonths)
    })
end)
