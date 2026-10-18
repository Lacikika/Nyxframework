--[[
    Nyxframework: nyx_parliament
    File: client/booths.lua
    Description: Physical civic voting booths, 3D markers, and interaction prompts.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

-- Proximity loop for physical voting stations
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local nearBooth = false
        local interactDist = Config.BoothInteractDistance or 2.0

        for _, booth in ipairs(Config.Booths or {}) do
            local dist = #(playerCoords - booth.coords)

            if dist <= 15.0 then
                -- Draw patriotic/civic station marker
                DrawMarker(27, booth.coords.x, booth.coords.y, booth.coords.z - 0.9,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    1.2, 1.2, 0.5, 65, 105, 225, 180,
                    false, false, 2, false, nil, nil, false
                )

                if dist <= interactDist then
                    nearBooth = true
                    BeginTextCommandDisplayHelp("STRING")
                    AddTextComponentSubstringPlayerName(string.format("Press ~INPUT_CONTEXT~ to access ~b~%s~s~", booth.label))
                    EndTextCommandDisplayHelp(0, false, true, -1)

                    if IsControlJustPressed(0, 38) then -- INPUT_CONTEXT (E)
                        Nyx.Parliament.OpenVotingUI()
                    end
                end
            end
        end

        if nearBooth then
            Wait(0)
        else
            Wait(500)
        end
    end
end)
