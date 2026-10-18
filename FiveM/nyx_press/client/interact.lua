--[[
    Nyxframework: nyx_press
    File: client/interact.lua
    Description: Third-Eye (LALT) Raycasting Integration for public newsstands,
                 encrypted whistleblower dropboxes, and printing press machinery.
]]

Nyx = Nyx or {}
Nyx.Press = Nyx.Press or {}

CreateThread(function()
    while GetResourceState("nyx_interact") ~= "started" do
        Wait(100)
    end

    -- 1. Third-Eye Raycasting on Public Newsstands
    if exports['nyx_interact'] and exports['nyx_interact'].AddTargetModel then
        exports['nyx_interact']:AddTargetModel(Config.Models.Newsstands, {
            options = {
                {
                    name = "press:buy_newspaper",
                    label = "Újság Vásárlása",
                    icon = "fa-solid fa-newspaper",
                    distance = 2.5,
                    canInteract = function(entity, distance, coords)
                        return true
                    end,
                    onSelect = function(data)
                        -- Find nearest newsstand identifier
                        local pCoords = GetEntityCoords(PlayerPedId())
                        local standId = "stand_legion_square" -- Fallback
                        local minDist = 9999.0

                        for sId, s in pairs(Nyx.Press.NewsstandsCache or {}) do
                            local d = #(pCoords - s.coords)
                            if d < minDist then
                                minDist = d
                                standId = sId
                            end
                        end

                        Nyx.Press.PurchaseAtStand(standId)
                    end
                },
                {
                    name = "press:view_headline",
                    label = "Legfrissebb Címlap Megtekintése",
                    icon = "fa-solid fa-book-open",
                    distance = 2.5,
                    canInteract = function(entity, distance, coords)
                        return true
                    end,
                    onSelect = function(data)
                        local p = Nyx.RPC.Call("press:getRecentPublications", { limit = 1 })
                        p:next(function(pubs)
                            if pubs and #pubs > 0 then
                                Nyx.Press.OpenPublicationReader(pubs[1])
                            else
                                TriggerEvent("nyx:ui:notify", {
                                    type = "warning",
                                    title = "ÜRES HÍRÁLLVÁNY",
                                    message = "Jelenleg nincs friss kiadás a standon.",
                                    duration = 5000
                                })
                            end
                        end)
                    end
                }
            },
            distance = 2.5
        })

        -- 2. Third-Eye Raycasting on Encrypted Whistleblower Dropboxes
        exports['nyx_interact']:AddTargetModel(Config.Models.Dropboxes, {
            options = {
                {
                    name = "press:whistleblower_drop",
                    label = "Névtelen Kiszivárogtatás Leadása",
                    icon = "fa-solid fa-user-secret",
                    distance = 2.0,
                    canInteract = function(entity, distance, coords)
                        return true
                    end,
                    onSelect = function(data)
                        TriggerEvent("nyx:ui:notify", {
                            type = "info",
                            title = "TITKOSÍTOTT DROPBOX",
                            message = "Használd a /whistleblow <Cím> <Kategória> <Információ> parancsot a védett adatok leadásához.",
                            duration = 8000
                        })
                    end
                },
                {
                    name = "press:whistleblower_claim",
                    label = "Kiszivárogtatások Vizsgálata (Sajtó)",
                    icon = "fa-solid fa-folder-open",
                    distance = 2.0,
                    canInteract = function(entity, distance, coords)
                        return true
                    end,
                    onSelect = function(data)
                        local p = Nyx.RPC.Call("press:getAvailableLeaks", {})
                        p:next(function(leaks)
                            if leaks and #leaks > 0 then
                                local count = #leaks
                                TriggerEvent("nyx:ui:notify", {
                                    type = "info",
                                    title = "KISZIVÁROGTATÁSI AKTA",
                                    message = string.format("%d feldolgozandó kiszivárogtatott anyag vár kivizsgálásra. Legfrissebb: '%s'",
                                        count, leaks[1].title),
                                    duration = 9000
                                })
                            else
                                TriggerEvent("nyx:ui:notify", {
                                    type = "warning",
                                    title = "NINCS ELÉRHETŐ ANYAG",
                                    message = "Nincs nyitott kiszivárogtatási bejelentés a postaládában vagy nem rendelkezel sajtóigazolvánnyal.",
                                    duration = 5000
                                })
                            end
                        end)
                    end
                }
            },
            distance = 2.0
        })

        -- 3. Third-Eye Raycasting on Industrial Printing Press
        exports['nyx_interact']:AddTargetModel(Config.Models.PrintingPress, {
            options = {
                {
                    name = "press:use_printing_press",
                    label = "Kiadás Nyomtatása (Nyomdagép)",
                    icon = "fa-solid fa-print",
                    distance = 2.0,
                    canInteract = function(entity, distance, coords)
                        return true
                    end,
                    onSelect = function(data)
                        TriggerEvent("nyx:ui:notify", {
                            type = "info",
                            title = "IPARI NYOMDAGÉP",
                            message = "A nyomdagép üzemkész. A kiadások terjesztéséhez és nyomtatásához használd a szerkesztőségi munkaállomást.",
                            duration = 6000
                        })
                    end
                }
            },
            distance = 2.0
        })
    end
end)
