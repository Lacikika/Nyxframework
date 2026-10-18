--[[
    Nyxframework: nyx_factions
    File: client/terminals.lua
    Description: City Hall charter registration and corporate management terminal interaction points,
                 Third-Eye (LALT) target registration, and zero-busywait dispatching.
]]

-- Register Commerce Terminals with Third-Eye (LALT) Raycast Engine
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    for idx, term in ipairs(Config.Terminals or {}) do
        exports['nyx_interact']:AddTargetCoords("faction_terminal_" .. idx, term.coords, 2.0, {
            options = {
                {
                    icon = "fa-solid fa-building-columns",
                    label = "Access " .. (term.label or "Commerce Terminal"),
                    event = "nyx:factions:client:openTerminal",
                    args = { terminal = term },
                    canInteract = function(entity, dist)
                        return dist <= 2.0
                    end
                }
            },
            distance = 2.0
        })
    end
end)

-- Relaxed visual beacon thread (Sleeps 1000ms, zero Wait(0) busy-wait)
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
                    sleep = 250
                    DrawMarker(29, term.coords.x, term.coords.y, term.coords.z - 0.2,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        0.6, 0.6, 0.6, 50, 180, 220, 140,
                        false, false, 2, false, nil, nil, false
                    )
                end
            end
        end

        Wait(sleep)
    end
end)

-- Open Commerce Terminal & Corporate Management Interface
RegisterNetEvent("nyx:factions:client:openTerminal", function(data)
    local term = (type(data) == "table" and data.terminal) or data
    local activeTab = (type(data) == "table" and data.activeTab) or "overview"
    local factionId = (type(data) == "table" and data.factionId) or nil

    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local factionsRes = exports['nyx_core']:TriggerRPCAwait("factions:getCitizenFactions")
        local overviewRes = exports['nyx_core']:TriggerRPCAwait("factions:getOverview", factionId)
        local overviewData = (overviewRes and overviewRes.success and overviewRes.overview) or nil

        if exports['nyx_ui'] and exports['nyx_ui'].OpenFactionDashboard then
            exports['nyx_ui']:OpenFactionDashboard({
                terminal = term,
                activeTab = activeTab,
                factions = (factionsRes and factionsRes.success and factionsRes.factions) or {},
                overview = overviewData
            })
            return
        end
    end

    if exports['nyx_ui'] then
        exports['nyx_ui']:OpenView("faction_commerce_terminal", { terminal = term, activeTab = activeTab })
    else
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = "DEPARTMENT OF COMMERCE",
            message = "Accessing corporate charter and organizational registry terminal."
        })
    end
end)

-- Player Commands for Corporate Dashboard
RegisterCommand("corporate", function(_, args)
    local targetFactionId = args and args[1]
    TriggerEvent("nyx:factions:client:openTerminal", { factionId = targetFactionId })
end, false)

RegisterCommand("faction", function(_, args)
    local targetFactionId = args and args[1]
    TriggerEvent("nyx:factions:client:openTerminal", { factionId = targetFactionId })
end, false)

RegisterCommand("org", function(_, args)
    local targetFactionId = args and args[1]
    TriggerEvent("nyx:factions:client:openTerminal", { factionId = targetFactionId })
end, false)
