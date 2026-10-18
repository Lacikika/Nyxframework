--[[
    Nyxframework: nyx_vehicles
    File: client/diagnostics.lua
    Description: Client-side diagnostics terminal dispatcher, Third-Eye interact points,
                 mechanic bay integrations, and NUI bridge triggering.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}

local isTerminalOpen = false

--- Opens the Vehicle Terminal UI (Diagnostics, Impound Lot, or Compliance)
--- @param options table|nil ({ activeTab = "diagnostics"|"impound"|"compliance", vin = "..." })
function Nyx.Vehicles.OpenTerminal(options)
    local opts = options or {}

    -- Auto-detect seated vehicle if no VIN provided
    if not opts.vin then
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            opts.plate = GetVehicleNumberPlateText(veh)
            opts.vin = opts.plate
        end
    end

    if exports['nyx_ui'] and exports['nyx_ui'].OpenVehicleTerminalUI then
        exports['nyx_ui']:OpenVehicleTerminalUI(opts)
        isTerminalOpen = true
    elseif exports['nyx_ui'] and exports['nyx_ui'].Send then
        exports['nyx_ui']:SetFocus(true, true)
        exports['nyx_ui']:Send("vehicle", "VEHICLE_TERMINAL_OPEN", opts)
        isTerminalOpen = true
    else
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "JÁRMŰ TERMINÁL",
            message = "A kezelőfelület (nyx_ui) nem érhető el."
        })
    end
end

--- Closes the Vehicle Terminal UI
function Nyx.Vehicles.CloseTerminal()
    if exports['nyx_ui'] and exports['nyx_ui'].CloseVehicleTerminalUI then
        exports['nyx_ui']:CloseVehicleTerminalUI()
    elseif exports['nyx_ui'] and exports['nyx_ui'].Send then
        exports['nyx_ui']:SetFocus(false, false)
        exports['nyx_ui']:Send("vehicle", "VEHICLE_TERMINAL_CLOSE", {})
    end
    isTerminalOpen = false
end

-- Commands
RegisterCommand("diagnostics", function(source, args)
    local vin = args[1]
    Nyx.Vehicles.OpenTerminal({
        activeTab = "diagnostics",
        vin = vin
    })
end, false)

RegisterCommand("mechanic", function(source, args)
    Nyx.Vehicles.OpenTerminal({
        activeTab = "diagnostics",
        vin = args[1]
    })
end, false)

RegisterCommand("impound", function(source, args)
    Nyx.Vehicles.OpenTerminal({
        activeTab = "impound",
        lotId = args[1]
    })
end, false)

RegisterCommand("vehiclerotary", function(source, args)
    Nyx.Vehicles.OpenTerminal({
        activeTab = "compliance",
        vin = args[1]
    })
end, false)

-- Net Events
RegisterNetEvent("nyx:vehicles:client:openTerminal", function(data)
    Nyx.Vehicles.OpenTerminal(data)
end)

RegisterNetEvent("nyx:vehicles:client:closeTerminal", function()
    Nyx.Vehicles.CloseTerminal()
end)

-- Register Third-Eye (LALT) Interact Targets on Municipal Repair Bays
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(1000)
    end

    local repairDepots = {
        { id = "repair_depot_ls", label = "Los Santos Municipal Repair Depot", coords = vector3(-338.4, -136.2, 39.0) },
        { id = "repair_sandy_shores", label = "Sandy Shores Auto Maintenance Bay", coords = vector3(1735.6, 3311.2, 41.2) },
        { id = "repair_paleto_bay", label = "Paleto Bay Public Service Maintenance Stall", coords = vector3(110.8, 6626.5, 31.8) }
    }

    for _, depot in ipairs(repairDepots) do
        exports['nyx_interact']:AddTargetCoords("depot_" .. depot.id, depot.coords, 3.0, {
            options = {
                {
                    icon = "fa-solid fa-screwdriver-wrench",
                    label = "Mechanikai Diagnosztika & Műszaki Átvizsgálás",
                    event = "nyx:vehicles:client:openTerminal",
                    args = { activeTab = "diagnostics" },
                    canInteract = function(entity, dist)
                        return dist <= 3.0
                    end
                },
                {
                    icon = "fa-solid fa-file-invoice",
                    label = "Forgalmi Engedély & Hatósági Műszaki",
                    event = "nyx:vehicles:client:openTerminal",
                    args = { activeTab = "compliance" },
                    canInteract = function(entity, dist)
                        return dist <= 3.0
                    end
                }
            },
            distance = 3.0
        })
    end
end)

-- Exports
exports("OpenVehicleTerminal", function(options)
    Nyx.Vehicles.OpenTerminal(options)
end)

exports("CloseVehicleTerminal", function()
    Nyx.Vehicles.CloseTerminal()
end)
