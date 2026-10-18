--[[
    Nyxframework: nyx_press
    File: client/press.lua
    Description: Client reader views, newsstand transactions, and chat command interfaces.
]]

Nyx = Nyx or {}
Nyx.Press = Nyx.Press or {}

-- 1. Open Publication Reading Viewer
function Nyx.Press.OpenPublicationReader(pubData)
    if not pubData then return end
    Nyx.Press.CurrentReaderPub = pubData

    -- Trigger UI reader view via Master SPA bridge or chat/notification
    TriggerEvent("nyx:ui:notify", {
        type = "info",
        title = string.format("ÚJSÁG: %s", pubData.headline),
        message = string.format("Kiadó: %s | Szerző: %s | Rovat: %s\n\n%s",
            pubData.outlet_id or "Független",
            pubData.author_byline or "Névtelen",
            pubData.category:upper(),
            pubData.content),
        duration = 15000
    })
end

-- 2. Purchase Newspaper at Stand
function Nyx.Press.PurchaseAtStand(standId)
    if not standId then return end

    local p = Nyx.RPC.Call("press:purchasePaper", standId)
    p:next(function(res)
        if res and res.success then
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "ÚJSÁG MEGVÁSÁROLVA",
                message = string.format("Sikeresen megvásároltad: '%s' ($%.2f). Hátramaradt készlet: %d db.",
                    res.headline, res.coverPrice, res.copiesRemaining),
                duration = 6000
            })
        else
            local err = res and res.error or "UNKNOWN_ERROR"
            local details = {
                ['INSUFFICIENT_FUNDS'] = "Nincs elegendő fedezet a számládon az újság megvásárlásához.",
                ['NEWSSTAND_OUT_OF_STOCK'] = "A stand kifogyott az újságokból.",
                ['NEWSSTAND_EMPTY_NO_EDITION'] = "Ezen a standon jelenleg nem kapható kiadás.",
                ['PUBLICATION_RETRACTED_BY_COURT_ORDER'] = "Ez a kiadás bírósági határozat alapján be van tiltva!"
            }
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "VÁSÁRLÁS SIKERTELEN",
                message = details[err] or ("Hiba: " .. tostring(err)),
                duration = 6000
            })
        end
    end)
end

-- ----------------------------------------------------------------------------
-- Chat Commands
-- ----------------------------------------------------------------------------

-- /readpaper [pubId]
RegisterCommand("readpaper", function(source, args)
    local pubId = args[1]
    if not pubId then
        -- Default: inspect current newspaper in inventory or nearest stand
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = "ÚJSÁGOLVASÁS",
            message = "Használat: /readpaper <kiadás_azonosító> vagy használd a Third-Eye (LALT) gombot az újságosstandnál.",
            duration = 6000
        })
        return
    end

    local p = Nyx.RPC.Call("press:getPublication", pubId)
    p:next(function(pub)
        if pub then
            Nyx.Press.OpenPublicationReader(pub)
        else
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "KIADÁS NEM TALÁLHATÓ",
                message = "A megadott azonosítójú kiadás nem található az archívumban.",
                duration = 5000
            })
        end
    end)
end, false)

-- /pressoutlets
RegisterCommand("pressoutlets", function()
    local p = Nyx.RPC.Call("press:getOutlets", {})
    p:next(function(outlets)
        if outlets and #outlets > 0 then
            local msg = "Akkreditált sajtóorgánumok:\n"
            for _, o in ipairs(outlets) do
                msg = msg .. string.format("• %s (%s) - Ár: $%.2f\n", o.name, o.outlet_id, tonumber(o.cover_price_default) or 10.0)
            end
            TriggerEvent("nyx:ui:notify", {
                type = "info",
                title = "SAJTÓKÖNYVTÁR",
                message = msg,
                duration = 10000
            })
        else
            TriggerEvent("nyx:ui:notify", {
                type = "warning",
                title = "SAJTÓKÖNYVTÁR",
                message = "Jelenleg nincsenek aktív bejegyzett sajtóorgánumok.",
                duration = 5000
            })
        end
    end)
end, false)

-- /whistleblow [title] [category] [payload...]
RegisterCommand("whistleblow", function(source, args)
    if #args < 3 then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "TITKOSÍTOTT KISZIVÁROGTATÁS",
            message = "Használat: /whistleblow <Cím> <Kategória> <Bizalmas Információ>\nKategóriák: treasury_fraud, police_brutality, corporate_bribery, election_tampering, general_corruption",
            duration = 9000
        })
        return
    end

    local title = args[1]
    local cat = args[2]
    local words = {}
    for i = 3, #args do
        words[#words + 1] = args[i]
    end
    local payload = table.concat(words, " ")

    local p = Nyx.RPC.Call("press:depositLeak", {
        title = title,
        category = cat,
        encryptedPayload = payload,
        dropboxId = "drop_metro_subway"
    })

    p:next(function(res)
        if res and res.success then
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "KISZIVÁROGTATÁS RÖGZÍTVE",
                message = string.format("Anyag leadva! Titkosítási lenyomat: %s...\nŐrizd meg a nonce-t a forrásigazoláshoz!",
                    res.sourceHash:sub(1, 16)),
                duration = 10000
            })
        else
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "KISZIVÁROGTATÁS SIKERTELEN",
                message = "Hiba: " .. tostring(res and res.error or "Hálózati hiba"),
                duration = 6000
            })
        end
    end)
end, false)

-- /retractpaper <pubId> <reason...> (Judicial authority only)
RegisterCommand("retractpaper", function(source, args)
    if #args < 2 then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "BÍRÓSÁGI HELYREIGAZÍTÁS",
            message = "Használat: /retractpaper <KiadásID> <Hivatalos Indoklás>",
            duration = 5000
        })
        return
    end

    local pubId = args[1]
    local reasonWords = {}
    for i = 2, #args do
        reasonWords[#reasonWords + 1] = args[i]
    end
    local reason = table.concat(reasonWords, " ")

    local p = Nyx.RPC.Call("press:retractPublication", {
        publicationId = pubId,
        reason = reason
    })

    p:next(function(res)
        if res and res.success then
            TriggerEvent("nyx:ui:notify", {
                type = "success",
                title = "BÍRÓSÁGI PARANCS KIADVA",
                message = string.format("A(z) '%s' kiadás terjesztése azonnali hatállyal felfüggesztve és betiltva.", pubId),
                duration = 7000
            })
        else
            TriggerEvent("nyx:ui:notify", {
                type = "error",
                title = "BÍRÓSÁGI PARANCS SIKERTELEN",
                message = "Hiba: " .. tostring(res and res.error or "Jogosulatlan kérelem"),
                duration = 5000
            })
        end
    end)
end, false)
