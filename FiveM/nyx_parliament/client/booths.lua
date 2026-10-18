--[[
    Nyxframework: nyx_parliament
    File: client/booths.lua
    Description: Physical civic voting booth terminals, spatial Third-Eye (LALT) target registry,
                 station beacon markers, and zero-busywait interaction dispatching.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- Register Voting Booths with Third-Eye (LALT) Raycast Engine
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    for idx, booth in ipairs(Config.Booths or {}) do
        local bId = booth.id or ("booth_" .. idx)
        local bLabel = booth.label or "Voting Station"

        exports['nyx_interact']:AddTargetCoords("parliament_booth_" .. idx, booth.coords, Config.BoothInteractDistance or 2.5, {
            options = {
                {
                    icon = "fa-solid fa-check-to-slot",
                    label = "Szavazás: " .. bLabel,
                    event = "nyx:parliament:client:openBoothTerminal",
                    action = function()
                        Nyx.Parliament.OpenVotingUI({
                            boothId = bId,
                            boothLabel = bLabel,
                            activeTab = "ballot"
                        })
                    end,
                    canInteract = function(entity, dist)
                        return dist <= (Config.BoothInteractDistance or 2.5)
                    end
                },
                {
                    icon = "fa-solid fa-user-tie",
                    label = "Jelöltállítás & Ajánlóívek (" .. bLabel .. ")",
                    event = "nyx:parliament:client:openBoothNominations",
                    action = function()
                        Nyx.Parliament.OpenVotingUI({
                            boothId = bId,
                            boothLabel = bLabel,
                            activeTab = "candidates"
                        })
                    end,
                    canInteract = function(entity, dist)
                        return dist <= (Config.BoothInteractDistance or 2.5)
                    end
                },
                {
                    icon = "fa-solid fa-file-signature",
                    label = "Visszahívási Népszavazások (" .. bLabel .. ")",
                    event = "nyx:parliament:client:openBoothRecall",
                    action = function()
                        Nyx.Parliament.OpenVotingUI({
                            boothId = bId,
                            boothLabel = bLabel,
                            activeTab = "candidates"
                        })
                    end,
                    canInteract = function(entity, dist)
                        return dist <= (Config.BoothInteractDistance or 2.5)
                    end
                }
            },
            distance = Config.BoothInteractDistance or 2.5
        })
    end
end)

-- Event hooks for voting booth access
RegisterNetEvent("nyx:parliament:client:openVoting", function(data)
    local bId = data and data.boothId or nil
    local bLabel = data and data.boothLabel or nil
    Nyx.Parliament.OpenVotingUI({
        boothId = bId,
        boothLabel = bLabel,
        activeTab = data and data.activeTab or "ballot"
    })
end)

RegisterNetEvent("nyx:parliament:client:openBoothTerminal", function(data)
    local bId = data and data.boothId or "booth:city_hall"
    local bLabel = data and data.boothLabel or "City Hall Council Voting Booth"
    Nyx.Parliament.OpenVotingUI({
        boothId = bId,
        boothLabel = bLabel,
        activeTab = "ballot"
    })
end)

-- Relaxed visual beacon thread (Sleeps 1000ms when far, zero Wait(0) busy-wait)
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local sleep = 1000

        for _, booth in ipairs(Config.Booths or {}) do
            local dist = #(playerCoords - booth.coords)
            if dist <= 15.0 then
                sleep = 250
                -- Pulsing civic ballot cylinder marker
                DrawMarker(27, booth.coords.x, booth.coords.y, booth.coords.z - 0.9,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    1.4, 1.4, 0.6, 65, 105, 225, 160,
                    false, false, 2, false, nil, nil, false
                )
            end
        end

        Wait(sleep)
    end
end)
