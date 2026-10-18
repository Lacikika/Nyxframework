--[[
    Nyxframework: nyx_parliament
    File: client/booths.lua
    Description: Physical civic voting booths, spatial Third-Eye (LALT) target registry,
                 and zero-busywait interaction dispatching.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- Register Voting Booths with Third-Eye (LALT) Raycast Engine
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    for idx, booth in ipairs(Config.Booths or {}) do
        exports['nyx_interact']:AddTargetCoords("parliament_booth_" .. idx, booth.coords, Config.BoothInteractDistance or 2.0, {
            options = {
                {
                    icon = "fa-solid fa-check-to-slot",
                    label = "Access " .. (booth.label or "Voting Station"),
                    event = "nyx:parliament:client:openVoting",
                    canInteract = function(entity, dist)
                        return dist <= (Config.BoothInteractDistance or 2.0)
                    end
                }
            },
            distance = Config.BoothInteractDistance or 2.0
        })
    end
end)

-- Event hook for voting booth access
RegisterNetEvent("nyx:parliament:client:openVoting", function()
    Nyx.Parliament.OpenVotingUI()
end)

-- Relaxed visual beacon thread (Sleeps 1000ms, zero Wait(0) busy-wait)
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local sleep = 1000

        for _, booth in ipairs(Config.Booths or {}) do
            local dist = #(playerCoords - booth.coords)
            if dist <= 12.0 then
                sleep = 250
                DrawMarker(27, booth.coords.x, booth.coords.y, booth.coords.z - 0.9,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    1.2, 1.2, 0.5, 65, 105, 225, 140,
                    false, false, 2, false, nil, nil, false
                )
            end
        end

        Wait(sleep)
    end
end)
