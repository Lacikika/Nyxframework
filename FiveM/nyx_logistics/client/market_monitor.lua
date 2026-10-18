--[[
    Nyxframework: nyx_logistics
    File: client/market_monitor.lua
    Description: Client-side dispatch, chat commands, and UI bridge for the 3D warehouse matrix
                 visualizer and real-time regional elastic market monitor.
]]

Nyx = Nyx or {}
Nyx.MarketMonitor = Nyx.MarketMonitor or {}

--- Opens the 3D Warehouse Matrix & Elastic Market Monitor UI.
--- @param options table|nil Optional view options (e.g. { activeTab = "matrix", warehouseId = "wh_dock_ls_01" })
function Nyx.MarketMonitor.Open(options)
    options = options or {}
    if exports['nyx_ui'] and exports['nyx_ui'].OpenMarketMonitorUI then
        exports['nyx_ui']:OpenMarketMonitorUI(options)
    elseif exports['nyx_ui'] and exports['nyx_ui'].OpenView then
        exports['nyx_ui']:OpenView("market_monitor", options)
    else
        -- Fallback direct NUI message
        SetNuiFocus(true, true)
        SendNUIMessage({
            app = "logistics",
            action = "LOGISTICS_MATRIX_OPEN",
            payload = options
        })
    end
end

--- Closes the 3D Warehouse Matrix & Elastic Market Monitor UI.
function Nyx.MarketMonitor.Close()
    if exports['nyx_ui'] and exports['nyx_ui'].CloseMarketMonitorUI then
        exports['nyx_ui']:CloseMarketMonitorUI()
    else
        SetNuiFocus(false, false)
        SendNUIMessage({
            app = "logistics",
            action = "LOGISTICS_MATRIX_CLOSE",
            payload = {}
        })
    end
end

-- ----------------------------------------------------------------------------
-- Chat Commands
-- ----------------------------------------------------------------------------
RegisterCommand("marketmonitor", function()
    Nyx.MarketMonitor.Open({ activeTab = "market" })
end, false)

RegisterCommand("warehousematrix", function()
    local currentWh = exports['nyx_logistics']:GetCurrentWarehouse and exports['nyx_logistics']:GetCurrentWarehouse()
    Nyx.MarketMonitor.Open({ activeTab = "matrix", warehouseId = currentWh or "wh_dock_ls_01" })
end, false)

RegisterCommand("market", function()
    Nyx.MarketMonitor.Open({ activeTab = "market" })
end, false)

RegisterCommand("logistics", function()
    Nyx.MarketMonitor.Open({ activeTab = "arbitrage" })
end, false)

-- ----------------------------------------------------------------------------
-- Network Event Handlers
-- ----------------------------------------------------------------------------
RegisterNetEvent("nyx:logistics:client:openMarketMonitor", function(options)
    Nyx.MarketMonitor.Open(options)
end)

-- Register Third-Eye Depot Terminal Interactions
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(200)
    end

    local terminals = {
        {
            coords = vector3(902.5, -2985.2, -3.8),
            label = "Port Warehouse Matrix Terminal",
            warehouseId = "wh_dock_ls_01"
        },
        {
            coords = vector3(1704.1, 3783.2, 34.7),
            label = "Sandy Freight Market Terminal",
            warehouseId = "wh_sandy_dist_01"
        }
    }

    for _, term in ipairs(terminals) do
        exports['nyx_interact']:AddTargetPoint(term.coords, {
            options = {
                {
                    icon = "fa-solid fa-boxes-stacked",
                    label = "3D Raktári Mátrix & Piaci Monitor",
                    action = function()
                        Nyx.MarketMonitor.Open({ activeTab = "matrix", warehouseId = term.warehouseId })
                    end,
                    canInteract = function() return true end
                }
            },
            distance = 2.5
        })
    end
end)

-- ----------------------------------------------------------------------------
-- Public Exports
-- ----------------------------------------------------------------------------
exports("OpenMarketMonitor", function(options)
    Nyx.MarketMonitor.Open(options)
end)

exports("CloseMarketMonitor", function()
    Nyx.MarketMonitor.Close()
end)
