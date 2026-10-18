--[[
    Nyxframework: nyx_treasury
    File: client/terminals.lua
    Description: Civic public transparency terminals, spatial eye-target registry,
                 and zero-busywait interaction dispatching.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}

-- Register Public Civic Terminals with Third-Eye (LALT) Raycast Engine
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    for idx, term in ipairs(Config.Terminals or {}) do
        exports['nyx_interact']:AddTargetCoords("treasury_terminal_" .. idx, term.coords, Config.TerminalInteractDistance or 2.0, {
            options = {
                {
                    icon = "fa-solid fa-scale-balanced",
                    label = "Access " .. (term.label or "Treasury Terminal"),
                    event = "nyx:treasury:client:openTerminal",
                    canInteract = function(entity, dist)
                        return dist <= (Config.TerminalInteractDistance or 2.0)
                    end
                }
            },
            distance = Config.TerminalInteractDistance or 2.0
        })
    end
end)

-- Event hook for terminal access
RegisterNetEvent("nyx:treasury:client:openTerminal", function()
    Nyx.Treasury.OpenTerminal()
end)

-- Relaxed visual beacon thread (Sleeps 1000ms, zero Wait(0) busy-wait)
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local sleep = 1000

        for _, term in ipairs(Config.Terminals or {}) do
            local dist = #(playerCoords - term.coords)
            if dist <= 12.0 then
                sleep = 250
                DrawMarker(20, term.coords.x, term.coords.y, term.coords.z + 0.1,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.35, 0.35, 0.35, 30, 144, 255, 140,
                    false, true, 2, false, nil, nil, false
                )
            end
        end

        Wait(sleep)
    end
end)
