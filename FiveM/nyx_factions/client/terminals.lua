--[[
    Nyxframework: nyx_factions
    File: client/terminals.lua
    Description: City Hall charter registration and corporate management terminal interaction points.
]]

-- Proximity Terminal Interaction Loop (Adaptive: 1000ms idle, 0ms close)
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local pCoords = GetEntityCoords(ped)

            for _, term in ipairs(Config.Terminals or {}) do
                local termVec = vector3(term.coords.x, term.coords.y, term.coords.z)
                local dist = #(pCoords - termVec)

                if dist < 12.0 then
                    sleep = 0
                    DrawMarker(29, term.coords.x, term.coords.y, term.coords.z - 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.6, 0.6, 50, 180, 220, 180, false, false, 2, false, nil, nil, false)

                    if dist <= 1.8 then
                        BeginTextCommandDisplayText("STRING")
                        AddTextComponentSubstringPlayerName(string.format("[~g~E~w~] Access %s", term.label))
                        SetTextFont(0)
                        SetTextScale(0.32, 0.32)
                        SetTextColour(255, 255, 255, 220)
                        SetTextCentre(true)

                        SetDrawOrigin(term.coords.x, term.coords.y, term.coords.z + 0.3, 0)
                        EndTextCommandDisplayText(0.0, 0.0)
                        ClearDrawOrigin()

                        if IsControlJustPressed(0, 38) then -- E key
                            TriggerEvent("nyx:factions:client:openTerminal", term)
                            Wait(500)
                        end
                    end
                elseif dist < 25.0 and sleep > 250 then
                    sleep = 250
                end
            end
        end

        Wait(sleep)
    end
end)

-- Open Commerce Terminal Interface
RegisterNetEvent("nyx:factions:client:openTerminal", function(term)
    if exports['nyx_ui'] then
        exports['nyx_ui']:OpenView("faction_commerce_terminal", { terminal = term })
    else
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = "DEPARTMENT OF COMMERCE",
            message = "Accessing corporate charter and organizational registry terminal."
        })
    end
end)
