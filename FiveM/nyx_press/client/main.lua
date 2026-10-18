--[[
    Nyxframework: nyx_press
    File: client/main.lua
    Description: Client-side lifecycle, broadcast listeners, and state tracking.
]]

Nyx = Nyx or {}
Nyx.Press = Nyx.Press or {}
Nyx.Press.CurrentReaderPub = nil

-- Standardized Client RPC Bridge
Nyx.RPC = Nyx.RPC or {
    Call = function(route, payload)
        if exports['nyx_core'] and exports['nyx_core'].CallRPC then
            return exports['nyx_core']:CallRPC(route, payload)
        end
        local p = promise.new()
        p:resolve(nil)
        return p
    end
}

-- Broadcast Event: New Article Published
RegisterNetEvent("nyx:press:client:newPublicationAvailable", function(pub)
    if not pub then return end
    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = "EXTRA! RENDKÍVÜLI HÍRKIADÁS",
        message = string.format("[%s] %s (Szerző: %s)", pub.outletId, pub.headline, pub.byline),
        duration = 7500
    })
end)

-- Broadcast Event: New Whistleblower Leak (Only alerts accredited media)
RegisterNetEvent("nyx:press:client:newWhistleblowerLeak", function(leak)
    if not leak then return end
    -- Check local player state bag or notify
    TriggerEvent("nyx:ui:notify", {
        type = "warning",
        title = "TITKOSÍTOTT KISZIVÁROGTATÁS ÉRKEZETT",
        message = string.format("Új tényfeltáró forrásanyag érkezett a(z) %s postaládába: '%s'",
            leak.dropboxId, leak.title),
        duration = 9000
    })
end)

-- Broadcast Event: Publication Retracted by Court Order
RegisterNetEvent("nyx:press:client:publicationRetracted", function(data)
    if not data then return end
    TriggerEvent("nyx:ui:notify", {
        type = "error",
        title = "BÍRÓSÁGI HELYREIGAZÍTÁS & BETILTÁS",
        message = string.format("A bíróság visszavonta a(z) '%s' cikket. Indoklás: %s",
            data.headline, data.reason),
        duration = 8000
    })
end)
