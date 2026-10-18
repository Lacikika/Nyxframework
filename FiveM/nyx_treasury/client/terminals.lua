--[[
    Nyxframework: nyx_treasury
    File: client/terminals.lua
    Description: Civic public transparency terminals, spatial proximity detection, and interaction prompts.
]]

Nyx = Nyx or {}
Nyx.Treasury = Nyx.Treasury or {}

-- Proximity and Interaction Loop for Civic Terminals
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local nearTerminal = false
        local interactDist = Config.TerminalInteractDistance or 2.0

        for _, term in ipairs(Config.Terminals or {}) do
            local dist = #(playerCoords - term.coords)
            if dist <= 15.0 then
                -- Draw subtle civic marker
                DrawMarker(20, term.coords.x, term.coords.y, term.coords.z + 0.1,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.4, 0.4, 0.4, 30, 144, 255, 180,
                    false, true, 2, false, nil, nil, false
                )

                if dist <= interactDist then
                    nearTerminal = true
                    BeginTextCommandDisplayHelp("STRING")
                    AddTextComponentSubstringPlayerName(string.format("Press ~INPUT_CONTEXT~ to access ~b~%s~s~", term.label))
                    EndTextCommandDisplayHelp(0, false, true, -1)

                    if IsControlJustPressed(0, 38) then -- INPUT_CONTEXT (E)
                        Nyx.Treasury.OpenTerminal()
                    end
                end
            end
        end

        if nearTerminal then
            Wait(0)
        else
            Wait(500)
        end
    end
end)
