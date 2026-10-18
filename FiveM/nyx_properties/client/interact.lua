--[[
    Nyxframework: nyx_properties
    File: client/interact.lua
    Description: Zero-polling raycast interaction targets (nyx_interact)
                 for entrance doors, interior exits, tax telemetry, and auctions.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}

CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(250)
    end

    -- Query properties list from server
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local data = exports['nyx_core']:TriggerRPCAwait("properties:getProperties")
        if data and data.success and data.properties then
            for _, prop in ipairs(data.properties) do
                local entCoords = vector3(prop.entrance.x, prop.entrance.y, prop.entrance.z)

                -- Register Entrance Target via nyx_interact (0.00 ms Idle)
                exports['nyx_interact']:AddTargetCoords("prop_entrance_" .. prop.id, entCoords, 2.0, {
                    options = {
                        {
                            label = string.format("Belépés: %s", prop.label),
                            icon = "fa-solid fa-door-open",
                            action = function()
                                Nyx.Properties.Enter(prop.id)
                            end
                        },
                        {
                            label = "Zár Kezelése",
                            icon = "fa-solid fa-key",
                            action = function()
                                Nyx.Properties.ToggleLock(prop.id)
                            end
                        },
                        {
                            label = string.format("Megvásárlás ($%s)", prop.price),
                            icon = "fa-solid fa-file-signature",
                            action = function()
                                TriggerServerEvent("nyx:properties:server:promptBuy", prop.id)
                            end,
                            canInteract = function()
                                return prop.owner == nil and not prop.reclaimedForAuction
                            end
                        },
                        {
                            label = "Ingatlan Adó- és Állapotkimutatás",
                            icon = "fa-solid fa-file-invoice-dollar",
                            action = function()
                                Nyx.Properties.ViewTaxAssessment(prop.id)
                            end
                        },
                        {
                            label = "Szerkezeti Felújítás",
                            icon = "fa-solid fa-hammer",
                            action = function()
                                Nyx.Properties.RepairCondition(prop.id)
                            end,
                            canInteract = function()
                                return prop.isOwnedByMe and (prop.maintenanceCondition or 100.0) < 100.0
                            end
                        },
                        {
                            label = "Adóhátralék Befizetése",
                            icon = "fa-solid fa-receipt",
                            action = function()
                                Nyx.Properties.PayArrears(prop.id)
                            end,
                            canInteract = function()
                                return prop.isOwnedByMe and (prop.delinquentAmount or 0.0) > 0.0
                            end
                        },
                        {
                            label = "Árverési Információ",
                            icon = "fa-solid fa-gavel",
                            action = function()
                                Nyx.Properties.ViewTaxAssessment(prop.id)
                            end,
                            canInteract = function()
                                return prop.reclaimedForAuction == true
                            end
                        },
                        {
                            label = "Gondnoksági Áttekintés",
                            icon = "fa-solid fa-user-shield",
                            action = function()
                                Nyx.Properties.ShowStewardshipOverview()
                            end
                        }
                    },
                    distance = 2.0
                })
            end
        end
    end
end)
