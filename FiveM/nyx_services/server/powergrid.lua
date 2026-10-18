--[[
    Nyxframework: nyx_services
    File: server/powergrid.lua
    Description: Regional power grid state engine, fuel consumption ticks,
                 mechanical wear, blackout evaluation, and player maintenance.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.Substations = {}

-- 1. Initialize and load all regional substations from database
function Nyx.Services.LoadSubstations()
    local rows = MySQL.query.await("SELECT * FROM `nyx_services_substations`")
    if rows then
        for _, r in ipairs(rows) do
            local coords = { x = 0.0, y = 0.0, z = 0.0 }
            if type(r.coords) == "string" then
                local ok, parsed = pcall(json.decode, r.coords)
                if ok and type(parsed) == "table" then coords = parsed end
            elseif type(r.coords) == "table" then
                coords = r.coords
            end

            Nyx.Services.Substations[r.substation_id] = {
                id = r.substation_id,
                label = r.label,
                fuelLevel = tonumber(r.fuel_level) or 100.00,
                conditionHealth = tonumber(r.condition_health) or 100.00,
                isBlackout = (tonumber(r.is_blackout) == 1),
                coords = vector3(coords.x, coords.y, coords.z),
                radius = tonumber(r.bounding_radius) or 1600.00
            }
        end
        if Config.Debug then
            print(string.format("^2[Nyx:Services]^7 Loaded %d regional substations from database.^7", #rows))
        end
    end
end

-- 2. Evaluate blackout state for a substation
local function evaluateSubstationState(s)
    local fuelThreshold = Config.PowerGrid.BlackoutFuelThreshold or 0.00
    local healthThreshold = Config.PowerGrid.BlackoutHealthThreshold or 10.00

    local shouldBlackout = (s.fuelLevel <= fuelThreshold or s.conditionHealth <= healthThreshold)

    if shouldBlackout and not s.isBlackout then
        s.isBlackout = true
        MySQL.prepare.await("UPDATE `nyx_services_substations` SET `is_blackout` = 1 WHERE `substation_id` = ?", { s.id })

        TriggerClientEvent("nyx:services:client:blackoutChanged", -1, {
            substationId = s.id,
            isBlackout = true,
            coords = { x = s.coords.x, y = s.coords.y, z = s.coords.z },
            radius = s.radius
        })

        print(string.format("^1[Nyx:Services] BLACKOUT CASCADE: Substation '%s' failed! (Fuel: %.1f%%, Health: %.1f%%)^7",
            s.id, s.fuelLevel, s.conditionHealth))
    elseif not shouldBlackout and s.isBlackout then
        s.isBlackout = false
        MySQL.prepare.await("UPDATE `nyx_services_substations` SET `is_blackout` = 0 WHERE `substation_id` = ?", { s.id })

        TriggerClientEvent("nyx:services:client:blackoutChanged", -1, {
            substationId = s.id,
            isBlackout = false,
            coords = { x = s.coords.x, y = s.coords.y, z = s.coords.z },
            radius = s.radius
        })

        print(string.format("^2[Nyx:Services] GRID RESTORED: Substation '%s' is back online! (Fuel: %.1f%%, Health: %.1f%%)^7",
            s.id, s.fuelLevel, s.conditionHealth))
    end
end

-- 3. Background Power Grid Consumption Tick (Runs every 60 seconds)
function Nyx.Services.PowerGridTick()
    local fuelBurn = Config.PowerGrid.FuelConsumptionPerMinute or 0.50
    local healthWear = Config.PowerGrid.HealthDegradationPerMinute or 0.15

    for id, s in pairs(Nyx.Services.Substations) do
        s.fuelLevel = math.max(0.00, s.fuelLevel - fuelBurn)
        s.conditionHealth = math.max(0.00, s.conditionHealth - healthWear)

        evaluateSubstationState(s)

        -- Persist current levels
        MySQL.prepare.await([[
            UPDATE `nyx_services_substations`
            SET `fuel_level` = ?, `condition_health` = ?
            WHERE `substation_id` = ?
        ]], { s.fuelLevel, s.conditionHealth, id })
    end
end

-- 4. Player Maintenance: Refuel Substation Generator
function Nyx.Services.RefuelSubstation(src, substationId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local s = Nyx.Services.Substations[substationId]
    if not s then return false, "SUBSTATION_NOT_FOUND" end

    if s.fuelLevel >= 100.00 then
        return false, "FUEL_TANK_FULL"
    end

    local invId = "citizen:" .. player.citizenId
    local removed, remErr = exports['nyx_inventory']:RemoveItem(invId, "industrial_fuel", 1)
    if not removed then
        return false, "NO_INDUSTRIAL_FUEL"
    end

    local restoreAmount = Config.PowerGrid.FuelDrumRefuelAmount or 25.00
    s.fuelLevel = math.min(100.00, s.fuelLevel + restoreAmount)

    MySQL.prepare.await([[
        UPDATE `nyx_services_substations`
        SET `fuel_level` = ?, `last_maintained_at` = CURRENT_TIMESTAMP
        WHERE `substation_id` = ?
    ]], { s.fuelLevel, substationId })

    evaluateSubstationState(s)

    return true, {
        substationId = substationId,
        fuelLevel = s.fuelLevel,
        isBlackout = s.isBlackout
    }
end

-- 5. Player Maintenance: Mechanical Repair
function Nyx.Services.RepairSubstation(src, substationId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local s = Nyx.Services.Substations[substationId]
    if not s then return false, "SUBSTATION_NOT_FOUND" end

    if s.conditionHealth >= 100.00 then
        return false, "MAINTENANCE_OPTIMAL"
    end

    local invId = "citizen:" .. player.citizenId
    local removed, remErr = exports['nyx_inventory']:RemoveItem(invId, "tool_repairkit", 1)
    if not removed then
        return false, "NO_REPAIR_KIT"
    end

    local restoreHealth = Config.PowerGrid.RepairKitRestoreAmount or 30.00
    s.conditionHealth = math.min(100.00, s.conditionHealth + restoreHealth)

    MySQL.prepare.await([[
        UPDATE `nyx_services_substations`
        SET `condition_health` = ?, `last_maintained_at` = CURRENT_TIMESTAMP
        WHERE `substation_id` = ?
    ]], { s.conditionHealth, substationId })

    evaluateSubstationState(s)

    return true, {
        substationId = substationId,
        conditionHealth = s.conditionHealth,
        isBlackout = s.isBlackout
    }
end

-- 6. Spatial Query: Is a coordinate currently energized?
function Nyx.Services.IsCoordsPowered(coords)
    if not coords then return true end
    local targetVec = vector3(coords.x, coords.y, coords.z)

    for _, s in pairs(Nyx.Services.Substations) do
        local dist = #(targetVec - s.coords)
        if dist <= s.radius then
            if s.isBlackout then
                return false, s.id
            end
        end
    end

    return true, nil
end

-- 7. Query specific substation status
function Nyx.Services.GetSubstation(substationId)
    return Nyx.Services.Substations[substationId]
end

-- 8. Query all substations
function Nyx.Services.GetAllSubstations()
    return Nyx.Services.Substations
end
