--[[
    Nyxframework: nyx_properties
    File: client/inactivity.lua
    Description: Client-side stewardship delegate interface, dormancy status inspection,
                 and anti-monopoly reclamation audit reporting.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}

-- 1. Display Stewardship Overview & Managed Assets
function Nyx.Properties.ShowStewardshipOverview()
    if not exports['nyx_core'] or not exports['nyx_core'].TriggerRPCAwait then return end

    local overview = exports['nyx_core']:TriggerRPCAwait("properties:getMyStewardship")
    if not overview then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "GONDNOKSÁGI ADATOK",
            message = "Nem sikerült lekérni a gondnoki adatokat."
        })
        return
    end

    local delegatesCount = #overview.delegates
    local managedCount = #overview.managedProperties
    local ownedCount = #overview.ownedProperties

    local summary = string.format("Kinevezett megbízottak: %d | Gondnokolt ingatlanok: %d | Saját ingatlanok: %d",
        delegatesCount, managedCount, ownedCount)

    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = "INGATLAN GONDNOKSÁGI RENDSZER",
        message = summary
    })
end

-- 2. Chat Commands
RegisterCommand("setdelegate", function(_, args)
    local delegateCitizenId = args[1]
    local scope = args[2] or "all"

    if not delegateCitizenId or #delegateCitizenId < 3 then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "HIÁNYZÓ CITIZEN ID",
            message = "Használat: /setdelegate <citizenId> [all|properties|factions]"
        })
        return
    end

    local ok, res = pcall(function()
        return exports['nyx_core']:TriggerRPCAwait("properties:registerStewardDelegate", {
            delegateCitizenId = delegateCitizenId,
            scope = scope,
            notes = "Kijelölt gondnoki meghatalmazás"
        })
    end)

    if ok and res and res.ownerCitizenId then
        TriggerEvent("nyx:ui:notify", {
            type = "success",
            title = "MEGHATALMAZÁS RÖGZÍTVE",
            message = string.format("Gondnok kinevezve: %s (%s, hatókör: %s).",
                res.delegateName or delegateCitizenId, res.delegateCitizenId, res.scope)
        })
    else
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "HIBA A KINEVEZÉSKOR",
            message = tostring(res or "A meghatalmazás sikertelen.")
        })
    end
end, false)

RegisterCommand("revokedelegate", function(_, args)
    local delegateCitizenId = args[1]
    local scope = args[2] or "all"

    if not delegateCitizenId then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "HIÁNYZÓ CITIZEN ID",
            message = "Használat: /revokedelegate <citizenId> [all|properties|factions]"
        })
        return
    end

    local ok, res = pcall(function()
        return exports['nyx_core']:TriggerRPCAwait("properties:revokeStewardDelegate", {
            delegateCitizenId = delegateCitizenId,
            scope = scope
        })
    end)

    if ok and res then
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = "MEGHATALMAZÁS VISSZAVONVA",
            message = string.format("%s gondnoki meghatalmazása visszavonva.", delegateCitizenId)
        })
    end
end, false)

RegisterCommand("assignsteward", function(_, args)
    local propId = tonumber(args[1])
    local delegateCitizenId = args[2]

    if not propId or not delegateCitizenId then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "HIÁNYZÓ ADATOK",
            message = "Használat: /assignsteward <propertyId> <citizenId>"
        })
        return
    end

    local ok, res = pcall(function()
        return exports['nyx_core']:TriggerRPCAwait("properties:assignPropertySteward", {
            propertyId = propId,
            delegateCitizenId = delegateCitizenId
        })
    end)

    if ok and res and res.propertyId then
        TriggerEvent("nyx:ui:notify", {
            type = "success",
            title = "INGATLAN GONDNOK KIJELÖLVE",
            message = string.format("Ingatlan #%d gondnoka: %s.", propId, delegateCitizenId)
        })
    else
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "KIJELÖLÉS SIKERTELEN",
            message = tostring(res or "Nem sikerült a kijelölés.")
        })
    end
end, false)

RegisterCommand("mystewardship", function()
    Nyx.Properties.ShowStewardshipOverview()
end, false)
