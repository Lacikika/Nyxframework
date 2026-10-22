--[[
    Nyxframework: nyx_services
    File: server/water_utility.lua
    Description: Authoritative server engine for municipal water reservoirs, contamination
                 diffusion, pump station power grid monitoring, and fire hydrant pressure dynamics.
]]

Nyx = Nyx or {}
Nyx.WaterUtility = Nyx.WaterUtility or {}

Nyx.Services = Nyx.Services or {}
Nyx.Services.WaterReservoirs = {}
Nyx.Services.WaterPumpStations = {}
Nyx.Services.FireHydrants = {}
Nyx.Services.ActiveDrafts = {} -- [hydrantId] = activeDraftCount

-- Load active reservoirs, pump stations, and hydrants from DB
local function LoadWaterUtilityState()
    MySQL.query("SELECT * FROM `nyx_water_reservoirs`", {}, function(reservoirs)
        if reservoirs then
            for _, r in ipairs(reservoirs) do
                Nyx.Services.WaterReservoirs[r.reservoir_id] = {
                    id = r.reservoir_id,
                    label = r.label,
                    waterLevelLiters = tonumber(r.water_level_liters) or 5000000.00,
                    maxCapacityLiters = tonumber(r.max_capacity_liters) or 10000000.00,
                    purityPercentage = tonumber(r.purity_percentage) or 100.00,
                    contaminationPpm = tonumber(r.contamination_ppm) or 0.00,
                    substationId = r.substation_id,
                    coords = vec3(tonumber(r.coords_x) or 0.0, tonumber(r.coords_y) or 0.0, tonumber(r.coords_z) or 0.0)
                }
            end
        end

        MySQL.query("SELECT * FROM `nyx_water_pump_stations`", {}, function(pumps)
            if pumps then
                for _, p in ipairs(pumps) do
                    Nyx.Services.WaterPumpStations[p.pump_id] = {
                        id = p.pump_id,
                        reservoirId = p.reservoir_id,
                        substationId = p.substation_id,
                        pumpStatus = p.pump_status or "ONLINE",
                        flowRateLps = tonumber(p.flow_rate_lps) or 150.00,
                        powerDrawKw = tonumber(p.power_draw_kw) or 750.00
                    }
                end
            end

            MySQL.query("SELECT * FROM `nyx_fire_hydrants`", {}, function(hydrants)
                if hydrants then
                    for _, h in ipairs(hydrants) do
                        Nyx.Services.FireHydrants[h.hydrant_id] = {
                            id = h.hydrant_id,
                            reservoirId = h.reservoir_id,
                            coords = vec3(tonumber(h.coords_x) or 0.0, tonumber(h.coords_y) or 0.0, tonumber(h.coords_z) or 0.0),
                            pressurePsi = tonumber(h.pressure_psi) or 85.00,
                            isActive = (h.is_active == 1 or h.is_active == true)
                        }
                    end
                end

                Nyx.Services.UpdateWaterSystemTelemetry()
            end)
        end)
    end)
end

-- Refresh pump statuses based on power grid substations & compute hydrant pressures
function Nyx.Services.UpdateWaterSystemTelemetry()
    for pumpId, pump in pairs(Nyx.Services.WaterPumpStations) do
        local sub = Nyx.Services.Substations and Nyx.Services.Substations[pump.substationId]
        if sub and (sub.isBlackout or sub.breakerTripped or sub.conditionHealth <= 0) then
            pump.pumpStatus = "OFFLINE_POWER"
        else
            if pump.pumpStatus == "OFFLINE_POWER" then
                pump.pumpStatus = "ONLINE"
            end
        end

        MySQL.update("UPDATE `nyx_water_pump_stations` SET `pump_status` = ? WHERE `pump_id` = ?", {
            pump.pumpStatus, pumpId
        })
    end

    for hydrantId, hydrant in pairs(Nyx.Services.FireHydrants) do
        local res = Nyx.Services.WaterReservoirs[hydrant.reservoirId]
        if res then
            -- Find linked pump station status
            local pumpStatus = "ONLINE"
            for _, pump in pairs(Nyx.Services.WaterPumpStations) do
                if pump.reservoirId == res.id then
                    pumpStatus = pump.pumpStatus
                    break
                end
            end

            local draftCount = Nyx.Services.ActiveDrafts[hydrantId] or 0
            hydrant.pressurePsi = Nyx.WaterUtility.CalculateHydrantPressure(res.waterLevelLiters, res.maxCapacityLiters, pumpStatus, draftCount)

            MySQL.update("UPDATE `nyx_fire_hydrants` SET `pressure_psi` = ? WHERE `hydrant_id` = ?", {
                hydrant.pressurePsi, hydrantId
            })
        end
    end

    GlobalState.waterReservoirs = Nyx.Services.WaterReservoirs
    GlobalState.fireHydrants = Nyx.Services.FireHydrants
end

--- Add contaminant grams to reservoir
function Nyx.Services.ContaminateReservoir(reservoirId, contaminantType, grams, sourceCitizenId)
    local res = Nyx.Services.WaterReservoirs[reservoirId]
    if not res then return false, "RESERVOIR_NOT_FOUND" end

    local newPpm, newPurity = Nyx.WaterUtility.CalculateContaminationDiffusion(res.contaminationPpm, res.waterLevelLiters, grams)
    res.contaminationPpm = newPpm
    res.purityPercentage = newPurity

    MySQL.update("UPDATE `nyx_water_reservoirs` SET `contamination_ppm` = ?, `purity_percentage` = ? WHERE `reservoir_id` = ?", {
        res.contaminationPpm, res.purityPercentage, reservoirId
    })

    MySQL.insert("INSERT INTO `nyx_water_contamination_events` (`reservoir_id`, `contaminant_type`, `ppm_added`, `reported_by`) VALUES (?, ?, ?, ?)", {
        reservoirId, contaminantType, grams, sourceCitizenId or "SYSTEM"
    })

    Nyx.Services.UpdateWaterSystemTelemetry()
    return true, { ppm = newPpm, purity = newPurity }
end

--- Purify reservoir with chemical agent
function Nyx.Services.PurifyReservoir(reservoirId, treatmentKg, chemicalEfficiency, sourceCitizenId)
    local res = Nyx.Services.WaterReservoirs[reservoirId]
    if not res then return false, "RESERVOIR_NOT_FOUND" end

    local newPpm, newPurity = Nyx.WaterUtility.CalculatePurificationTreatment(res.contaminationPpm, treatmentKg, chemicalEfficiency or 50.0, res.waterLevelLiters)
    res.contaminationPpm = newPpm
    res.purityPercentage = newPurity

    MySQL.update("UPDATE `nyx_water_reservoirs` SET `contamination_ppm` = ?, `purity_percentage` = ? WHERE `reservoir_id` = ?", {
        res.contaminationPpm, res.purityPercentage, reservoirId
    })

    Nyx.Services.UpdateWaterSystemTelemetry()
    return true, { ppm = newPpm, purity = newPurity }
end

--- Draft water from a hydrant into a fire vehicle or tank
function Nyx.Services.DraftFromHydrant(hydrantId, requestedLiters)
    local hydrant = Nyx.Services.FireHydrants[hydrantId]
    if not hydrant then return false, "HYDRANT_NOT_FOUND" end
    if not hydrant.isActive then return false, "HYDRANT_INACTIVE" end

    local res = Nyx.Services.WaterReservoirs[hydrant.reservoirId]
    if not res then return false, "RESERVOIR_NOT_FOUND" end

    if hydrant.pressurePsi < 5.0 then
        return false, "INSUFFICIENT_PRESSURE"
    end

    local actualDrawn = math.min(requestedLiters, res.waterLevelLiters)
    res.waterLevelLiters = Nyx.WaterUtility.CalculateWaterConsumption(res.waterLevelLiters, actualDrawn, 0, 0)

    MySQL.update("UPDATE `nyx_water_reservoirs` SET `water_level_liters` = ? WHERE `reservoir_id` = ?", {
        res.waterLevelLiters, res.id
    })

    Nyx.Services.UpdateWaterSystemTelemetry()
    return true, { litersDrawn = actualDrawn, remainingLevel = res.waterLevelLiters, pressurePsi = hydrant.pressurePsi, purity = res.purityPercentage }
end

-- Hook database readiness
AddEventHandler("nyx:core:dbReady", function()
    LoadWaterUtilityState()
end)

CreateThread(function()
    while true do
        Wait(60000) -- Refresh water system telemetry every 60s
        if Nyx.Services.WaterReservoirs and next(Nyx.Services.WaterReservoirs) then
            Nyx.Services.UpdateWaterSystemTelemetry()
        end
    end
end)

-- RPC Registrations
if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
    exports['nyx_core']:RegisterRPC("services:getWaterReservoirs", function(src)
        return Nyx.Services.WaterReservoirs
    end)

    exports['nyx_core']:RegisterRPC("services:getFireHydrants", function(src)
        return Nyx.Services.FireHydrants
    end)

    exports['nyx_core']:RegisterRPC("services:draftHydrant", function(src, hydrantId, liters)
        return Nyx.Services.DraftFromHydrant(hydrantId, liters)
    end)

    exports['nyx_core']:RegisterRPC("services:contaminateReservoir", function(src, reservoirId, contaminantType, grams)
        local player = Nyx.GetPlayer and Nyx.GetPlayer(src)
        local citizenId = player and player.citizenId or "UNKNOWN"
        return Nyx.Services.ContaminateReservoir(reservoirId, contaminantType, grams, citizenId)
    end)

    exports['nyx_core']:RegisterRPC("services:purifyReservoir", function(src, reservoirId, treatmentKg)
        local player = Nyx.GetPlayer and Nyx.GetPlayer(src)
        local citizenId = player and player.citizenId or "UNKNOWN"
        return Nyx.Services.PurifyReservoir(reservoirId, treatmentKg, 50.0, citizenId)
    end)
end
