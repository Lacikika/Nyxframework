--[[
    Nyxframework: nyx_services
    File: server/main.lua
    Description: Core server initialization, background grid ticks, utility billing schedules,
                 and RPC registration.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}

CreateThread(function()
    print("^4[Nyx:Services]^7 Initializing Civil Infrastructure & Public Utilities...^7")

    -- 1. Load substations and hospitals from database
    Nyx.Services.LoadSubstations()
    Nyx.Services.LoadHospitals()

    -- 2. Register RPC routes
    if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
        -- Query substations
        exports['nyx_core']:RegisterRPC("services:getSubstations", function(src)
            return { success = true, substations = Nyx.Services.GetAllSubstations() }
        end)

        -- Refuel substation
        exports['nyx_core']:RegisterRPC("services:refuelSubstation", function(src, substationId)
            local ok, res = Nyx.Services.RefuelSubstation(src, substationId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Repair substation
        exports['nyx_core']:RegisterRPC("services:repairSubstation", function(src, substationId)
            local ok, res = Nyx.Services.RepairSubstation(src, substationId)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Query hospitals
        exports['nyx_core']:RegisterRPC("services:getHospitals", function(src)
            return { success = true, hospitals = Nyx.Services.GetAllHospitals() }
        end)

        -- Process patient revival
        exports['nyx_core']:RegisterRPC("services:processRevival", function(src, hospitalId, requiresSurgery)
            local ok, res = Nyx.Services.ProcessRevival(src, hospitalId, requiresSurgery)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Restock hospital
        exports['nyx_core']:RegisterRPC("services:restockHospital", function(src, hospitalId, item, amount)
            local ok, res = Nyx.Services.RestockHospital(src, hospitalId, item, amount)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Pay utility arrears
        exports['nyx_core']:RegisterRPC("services:payUtilityBill", function(src, meterId, amount)
            local ok, res = Nyx.Services.PayUtilityBill(src, meterId, amount)
            return { success = ok, data = res, error = (not ok and res or nil) }
        end)

        -- Query utility meter
        exports['nyx_core']:RegisterRPC("services:getMeter", function(src, meterId)
            local m = Nyx.Services.GetMeter(meterId)
            return { success = (m ~= nil), meter = m }
        end)
    end

    -- 3. Power Grid Consumption Tick Loop (Every 60 seconds)
    CreateThread(function()
        while true do
            Wait(60000)
            Nyx.Services.PowerGridTick()
        end
    end)

    -- 4. Metered Utility Billing Cycle Loop (Every 30 minutes)
    CreateThread(function()
        while true do
            Wait(Config.Billing and (Config.Billing.BillingCycleInterval * 1000) or 1800000)
            Nyx.Services.ProcessUtilityBillingCycle()
        end
    end)

    print("^2[Nyx:Services]^7 Online and authoritative.^7")
end)

-- Sync active blackout zones to connecting client
RegisterNetEvent("nyx:services:server:requestGridSync", function()
    local src = source
    local blackouts = {}
    for id, s in pairs(Nyx.Services.Substations) do
        if s.isBlackout then
            table.insert(blackouts, {
                substationId = id,
                coords = { x = s.coords.x, y = s.coords.y, z = s.coords.z },
                radius = s.radius
            })
        end
    end
    TriggerClientEvent("nyx:services:client:initialGridSync", src, blackouts)
end)
