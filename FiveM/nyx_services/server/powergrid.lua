--[[
    Nyxframework: nyx_services
    File: server/powergrid.lua
    Description: Regional power grid state engine, fuel consumption ticks, mechanical wear,
                 circuit breaker mechanics, failure simulation, diagnostics, and logistics sync.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.Substations = {}

-- Helper to synchronize server-authoritative GlobalState for 0.00ms client reads
local function syncGlobalGridState()
    local blackouts = {}
    local summary = {}

    for id, s in pairs(Nyx.Services.Substations) do
        summary[id] = {
            id = id,
            label = s.label,
            fuelLevel = s.fuelLevel,
            conditionHealth = s.conditionHealth,
            isBlackout = s.isBlackout,
            breakerTripped = s.breakerTripped,
            failureReason = s.failureReason,
            peakLoadMw = s.peakLoadMw,
            coords = { x = s.coords.x, y = s.coords.y, z = s.coords.z },
            radius = s.radius
        }

        if s.isBlackout then
            blackouts[id] = {
                substationId = id,
                coords = { x = s.coords.x, y = s.coords.y, z = s.coords.z },
                radius = s.radius,
                reason = s.failureReason or "system_failure"
            }
        end
    end

    GlobalState.blackoutZones = blackouts
    GlobalState.substations = summary
end

-- Check and dispatch emergency logistics hauling contracts when reserves hit critical
local function checkEmergencyLogisticsContracts(s)
    local critThresh = Config.PowerGrid.CriticalWarningThreshold or 20.00
    local destShelfId = "substation:" .. s.id

    -- 1. Emergency Fuel Dispatch
    if s.fuelLevel <= critThresh then
        local count = MySQL.scalar.await([[
            SELECT COUNT(*) FROM `nyx_logistics_contracts`
            WHERE `dest_shelf_id` = ? AND `item_id` = 'industrial_fuel' AND `status` IN ('available', 'in_transit')
        ]], { destShelfId })

        if (tonumber(count) or 0) == 0 then
            local qty = Config.PowerGrid.EmergencyFuelContract and Config.PowerGrid.EmergencyFuelContract.Quantity or 4
            local payout = Config.PowerGrid.EmergencyFuelContract and Config.PowerGrid.EmergencyFuelContract.PayoutPerUnit or 200.00

            MySQL.prepare.await([[
                INSERT INTO `nyx_logistics_contracts`
                    (`source_inventory_id`, `dest_shelf_id`, `item_id`, `quantity`, `payout_per_unit`, `issuer_faction_id`, `status`)
                VALUES (?, ?, 'industrial_fuel', ?, ?, 'gov:dept:works', 'available')
            ]], { "stash:oil_refinery", destShelfId, qty, payout })

            TriggerClientEvent("nyx:logistics:client:newContractAvailable", -1, destShelfId, qty, payout)
            print(string.format("^3[Nyx:Services] Emergency fuel freight contract dispatched for Substation '%s' (%dx Fuel Drums)^7",
                s.id, qty))
        end
    end

    -- 2. Emergency Replacement Components / Repair Kits
    if s.conditionHealth <= critThresh then
        local count = MySQL.scalar.await([[
            SELECT COUNT(*) FROM `nyx_logistics_contracts`
            WHERE `dest_shelf_id` = ? AND `item_id` = 'tool_repairkit' AND `status` IN ('available', 'in_transit')
        ]], { destShelfId })

        if (tonumber(count) or 0) == 0 then
            local qty = Config.PowerGrid.EmergencyRepairContract and Config.PowerGrid.EmergencyRepairContract.Quantity or 3
            local payout = Config.PowerGrid.EmergencyRepairContract and Config.PowerGrid.EmergencyRepairContract.PayoutPerUnit or 250.00

            MySQL.prepare.await([[
                INSERT INTO `nyx_logistics_contracts`
                    (`source_inventory_id`, `dest_shelf_id`, `item_id`, `quantity`, `payout_per_unit`, `issuer_faction_id`, `status`)
                VALUES (?, ?, 'tool_repairkit', ?, ?, 'gov:dept:works', 'available')
            ]], { "stash:hardware_depot", destShelfId, qty, payout })

            TriggerClientEvent("nyx:logistics:client:newContractAvailable", -1, destShelfId, qty, payout)
            print(string.format("^3[Nyx:Services] Emergency turbine repair contract dispatched for Substation '%s' (%dx Repair Kits)^7",
                s.id, qty))
        end
    end
end

-- 1. Authoritative Pure Substation Hydration Evaluator
-- Handles DB row decoding and enforces database hydration fallback:
-- Default / uninitialized substations start at 100.0% fuel and turbine integrity.
function Nyx.Services.HydrateSubstationRecord(subId, dbRow, cfgSub)
    cfgSub = cfgSub or (Config.PowerGrid and Config.PowerGrid.Substations and Config.PowerGrid.Substations[subId]) or {}

    local coords = { x = 0.0, y = 0.0, z = 0.0 }
    if dbRow and dbRow.coords then
        if type(dbRow.coords) == "string" then
            local ok, parsed = pcall(json.decode, dbRow.coords)
            if ok and type(parsed) == "table" then coords = parsed end
        elseif type(dbRow.coords) == "table" then
            coords = dbRow.coords
        end
    elseif cfgSub and cfgSub.coords then
        coords = { x = cfgSub.coords.x, y = cfgSub.coords.y, z = cfgSub.coords.z }
    end

    local vecCoords = vector3(coords.x or 0.0, coords.y or 0.0, coords.z or 0.0)
    local tCoords = (cfgSub and cfgSub.transformerCoords) or vecCoords
    local radius = tonumber(dbRow and dbRow.bounding_radius) or (cfgSub and cfgSub.radius) or 1600.00
    local label = (dbRow and dbRow.label) or (cfgSub and cfgSub.label) or "Regional Substation"
    local districts = (cfgSub and cfgSub.connectedDistricts) or "Municipal Grid"
    local peakMw = tonumber(dbRow and dbRow.peak_load_mw) or 45.00
    local totalBlackouts = tonumber(dbRow and dbRow.total_blackouts_count) or 0

    local fuelLevel = 100.00
    local conditionHealth = 100.00
    local isBlackout = false
    local breakerTripped = false
    local failureReason = nil
    local blackoutStartedAt = nil
    local needsDbPersist = false

    if not dbRow then
        -- Complete database hydration fallback from Config:
        -- Default substation starts at 100.0% fuel and turbine integrity.
        needsDbPersist = true
    else
        local rawFuel = tonumber(dbRow.fuel_level)
        local rawHealth = tonumber(dbRow.condition_health)
        local rawBlackout = (tonumber(dbRow.is_blackout) == 1)
        local rawBreaker = (tonumber(dbRow.breaker_tripped) == 1)
        local rawReason = dbRow.failure_reason
        if rawReason == "" then rawReason = nil end

        -- Check for zero-state cascade bug on startup:
        -- Substation initialized with 0.0% fuel and health (or missing/nil values) without an intentional in-game failure reason
        local isCorruptZeroState = (rawFuel == nil or rawFuel <= 0.00) and (rawHealth == nil or rawHealth <= 0.00) and (not rawReason)
        local isMissingFuel = (rawFuel == nil) or (rawFuel <= 0.00 and not rawBlackout and not rawBreaker and not rawReason)
        local isMissingHealth = (rawHealth == nil) or (rawHealth <= 0.00 and not rawBlackout and not rawBreaker and not rawReason)

        if isCorruptZeroState then
            -- Reset corrupt zero-state to healthy 100% baseline
            fuelLevel = 100.00
            conditionHealth = 100.00
            isBlackout = false
            breakerTripped = false
            failureReason = nil
            needsDbPersist = true
        else
            if isMissingFuel then
                fuelLevel = 100.00
                needsDbPersist = true
            else
                fuelLevel = math.max(0.00, math.min(100.00, rawFuel))
            end

            if isMissingHealth then
                conditionHealth = 100.00
                needsDbPersist = true
            else
                conditionHealth = math.max(0.00, math.min(100.00, rawHealth))
            end

            isBlackout = rawBlackout
            breakerTripped = rawBreaker
            failureReason = rawReason
            blackoutStartedAt = dbRow.blackout_started_at
        end
    end

    local record = {
        id = subId,
        label = label,
        fuelLevel = fuelLevel,
        conditionHealth = conditionHealth,
        isBlackout = isBlackout,
        failureReason = failureReason,
        blackoutStartedAt = blackoutStartedAt,
        peakLoadMw = peakMw,
        breakerTripped = breakerTripped,
        totalBlackoutsCount = totalBlackouts,
        coords = vecCoords,
        radius = radius,
        transformerCoords = tCoords,
        connectedDistricts = districts
    }

    return record, needsDbPersist
end

-- 2. Initialize and load all regional substations from database with config fallback
function Nyx.Services.LoadSubstations()
    local rows = MySQL.query.await("SELECT * FROM `nyx_services_substations`")
    local loadedFromDb = {}

    if rows and #rows > 0 then
        for _, r in ipairs(rows) do
            local cfgSub = Config.PowerGrid.Substations and Config.PowerGrid.Substations[r.substation_id]
            local record, needsDbPersist = Nyx.Services.HydrateSubstationRecord(r.substation_id, r, cfgSub)

            Nyx.Services.Substations[r.substation_id] = record
            loadedFromDb[r.substation_id] = true

            if needsDbPersist then
                MySQL.prepare.await([[
                    UPDATE `nyx_services_substations`
                    SET `fuel_level` = ?,
                        `condition_health` = ?,
                        `is_blackout` = ?,
                        `breaker_tripped` = ?,
                        `failure_reason` = ?
                    WHERE `substation_id` = ?
                ]], {
                    record.fuelLevel,
                    record.conditionHealth,
                    record.isBlackout and 1 or 0,
                    record.breakerTripped and 1 or 0,
                    record.failureReason,
                    r.substation_id
                })
            end
        end
    end

    -- Database Hydration Fallback: ensure all default substations from Config exist and start at 100%
    if Config.PowerGrid and Config.PowerGrid.Substations then
        for subId, cfgSub in pairs(Config.PowerGrid.Substations) do
            if not loadedFromDb[subId] then
                local record, _ = Nyx.Services.HydrateSubstationRecord(subId, nil, cfgSub)
                Nyx.Services.Substations[subId] = record

                local coordsJson = json.encode({ x = record.coords.x, y = record.coords.y, z = record.coords.z })

                MySQL.prepare.await([[
                    INSERT INTO `nyx_services_substations`
                        (`substation_id`, `label`, `fuel_level`, `condition_health`, `is_blackout`, `coords`, `bounding_radius`, `peak_load_mw`, `breaker_tripped`, `total_blackouts_count`)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        `fuel_level` = VALUES(`fuel_level`),
                        `condition_health` = VALUES(`condition_health`),
                        `is_blackout` = VALUES(`is_blackout`),
                        `breaker_tripped` = VALUES(`breaker_tripped`)
                ]], {
                    subId,
                    record.label,
                    record.fuelLevel,
                    record.conditionHealth,
                    record.isBlackout and 1 or 0,
                    coordsJson,
                    record.radius,
                    record.peakLoadMw,
                    record.breakerTripped and 1 or 0,
                    record.totalBlackoutsCount
                })

                if Config.Debug then
                    print(string.format("^3[Nyx:Services] Hydrated missing default substation '%s' (100.0%% fuel, 100.0%% integrity).^7", subId))
                end
            end
        end
    end

    syncGlobalGridState()

    local count = 0
    for _ in pairs(Nyx.Services.Substations) do count = count + 1 end

    if Config.Debug then
        print(string.format("^2[Nyx:Services]^7 Loaded %d regional substations from database / config fallback.^7", count))
    end
end

-- 2. Authoritative Substation State Evaluator
local function evaluateSubstationState(s, triggerAuditLog)
    local fuelThreshold = Config.PowerGrid.BlackoutFuelThreshold or 0.00
    local healthThreshold = Config.PowerGrid.BlackoutHealthThreshold or 10.00

    local shouldBlackout = (s.fuelLevel <= fuelThreshold or s.conditionHealth <= healthThreshold or s.breakerTripped)

    if shouldBlackout and not s.isBlackout then
        s.isBlackout = true
        s.breakerTripped = true
        s.totalBlackoutsCount = (s.totalBlackoutsCount or 0) + 1

        if not s.failureReason or s.failureReason == "" then
            if s.fuelLevel <= fuelThreshold then
                s.failureReason = "fuel_exhaustion"
            elseif s.conditionHealth <= healthThreshold then
                s.failureReason = "mechanical_breakdown"
            elseif s.breakerTripped then
                s.failureReason = "overload_trip"
            else
                s.failureReason = "system_failure"
            end
        end

        -- Update substation record
        MySQL.prepare.await([[
            UPDATE `nyx_services_substations`
            SET `is_blackout` = 1,
                `failure_reason` = ?,
                `blackout_started_at` = CURRENT_TIMESTAMP,
                `breaker_tripped` = 1,
                `total_blackouts_count` = ?
            WHERE `substation_id` = ?
        ]], { s.failureReason, s.totalBlackoutsCount, s.id })

        -- Insert audit log
        if triggerAuditLog ~= false then
            MySQL.prepare.await([[
                INSERT INTO `nyx_services_blackout_logs`
                    (`substation_id`, `failure_reason`, `started_at`)
                VALUES (?, ?, CURRENT_TIMESTAMP)
            ]], { s.id, s.failureReason })
        end

        -- Dispatch emergency logistics contracts
        checkEmergencyLogisticsContracts(s)

        -- Broadcast state change to all clients
        TriggerClientEvent("nyx:services:client:blackoutChanged", -1, {
            substationId = s.id,
            label = s.label,
            isBlackout = true,
            breakerTripped = true,
            reason = s.failureReason,
            coords = { x = s.coords.x, y = s.coords.y, z = s.coords.z },
            transformerCoords = { x = s.transformerCoords.x, y = s.transformerCoords.y, z = s.transformerCoords.z },
            radius = s.radius
        })

        syncGlobalGridState()

        print(string.format("^1[Nyx:Services] BLACKOUT CASCADE: Substation '%s' failed! Reason: %s (Fuel: %.1f%%, Health: %.1f%%)^7",
            s.id, s.failureReason, s.fuelLevel, s.conditionHealth))

    elseif not shouldBlackout and s.isBlackout then
        s.isBlackout = false
        s.breakerTripped = false
        local prevReason = s.failureReason
        s.failureReason = nil
        s.blackoutStartedAt = nil

        -- Update substation record
        MySQL.prepare.await([[
            UPDATE `nyx_services_substations`
            SET `is_blackout` = 0,
                `failure_reason` = NULL,
                `blackout_started_at` = NULL,
                `breaker_tripped` = 0
            WHERE `substation_id` = ?
        ]], { s.id })

        -- Resolve active audit log
        MySQL.prepare.await([[
            UPDATE `nyx_services_blackout_logs`
            SET `restored_at` = CURRENT_TIMESTAMP,
                `duration_seconds` = TIMESTAMPDIFF(SECOND, `started_at`, CURRENT_TIMESTAMP)
            WHERE `substation_id` = ? AND `restored_at` IS NULL
        ]], { s.id })

        -- Broadcast state change to all clients
        TriggerClientEvent("nyx:services:client:blackoutChanged", -1, {
            substationId = s.id,
            label = s.label,
            isBlackout = false,
            breakerTripped = false,
            coords = { x = s.coords.x, y = s.coords.y, z = s.coords.z },
            transformerCoords = { x = s.transformerCoords.x, y = s.transformerCoords.y, z = s.transformerCoords.z },
            radius = s.radius
        })

        syncGlobalGridState()

        print(string.format("^2[Nyx:Services] GRID RESTORED: Substation '%s' is re-energized and back online! (Fuel: %.1f%%, Health: %.1f%%)^7",
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

        evaluateSubstationState(s, true)

        -- If reserves approach critical warning threshold, dispatch logistics hauling contracts
        if s.fuelLevel <= (Config.PowerGrid.CriticalWarningThreshold or 20.00) or
           s.conditionHealth <= (Config.PowerGrid.CriticalWarningThreshold or 20.00) then
            checkEmergencyLogisticsContracts(s)
        end

        -- Persist current levels
        MySQL.prepare.await([[
            UPDATE `nyx_services_substations`
            SET `fuel_level` = ?, `condition_health` = ?
            WHERE `substation_id` = ?
        ]], { s.fuelLevel, s.conditionHealth, id })
    end

    syncGlobalGridState()
end

-- 4. Manual / Scripted Substation Failure Simulation
function Nyx.Services.TriggerSubstationFailure(substationId, reason, citizenId)
    local s = Nyx.Services.Substations[substationId]
    if not s then return false, "SUBSTATION_NOT_FOUND" end

    s.breakerTripped = true
    s.failureReason = reason or "sabotage"

    evaluateSubstationState(s, true)

    return true, {
        substationId = substationId,
        isBlackout = s.isBlackout,
        failureReason = s.failureReason,
        breakerTripped = s.breakerTripped
    }
end

-- 5. Circuit Breaker Reset Mechanics
function Nyx.Services.ResetCircuitBreaker(src, substationId)
    local player = Nyx.GetPlayer(src)
    if not player then return false, "UNAUTHENTICATED" end

    local s = Nyx.Services.Substations[substationId]
    if not s then return false, "SUBSTATION_NOT_FOUND" end

    if not s.breakerTripped and not s.isBlackout then
        return false, "BREAKER_NOT_TRIPPED"
    end

    local fuelThreshold = Config.PowerGrid.BlackoutFuelThreshold or 0.00
    local healthThreshold = Config.PowerGrid.BlackoutHealthThreshold or 10.00

    -- Safety Interlocks: Cannot re-energize if fuel is exhausted or generator has catastrophic structural damage
    if s.fuelLevel <= fuelThreshold then
        return false, "CANNOT_RESET_FUEL_DEPLETED"
    end

    if s.conditionHealth <= healthThreshold then
        return false, "CANNOT_RESET_CRITICAL_DAMAGE"
    end

    -- Clear trip state
    s.breakerTripped = false
    s.failureReason = nil

    evaluateSubstationState(s, false)

    -- Record restorer in audit log
    MySQL.prepare.await([[
        UPDATE `nyx_services_blackout_logs`
        SET `restored_by_citizen_id` = ?
        WHERE `substation_id` = ? AND `restored_at` = CURRENT_TIMESTAMP
    ]], { player.citizenId, substationId })

    return true, {
        substationId = substationId,
        isBlackout = s.isBlackout,
        breakerTripped = s.breakerTripped,
        fuelLevel = s.fuelLevel,
        conditionHealth = s.conditionHealth
    }
end

-- 6. Grid Load Surge / Overload Simulation
function Nyx.Services.SimulateGridOverload(substationId, spikeMw)
    local s = Nyx.Services.Substations[substationId]
    if not s then return false, "SUBSTATION_NOT_FOUND" end

    local spike = math.max(0.00, tonumber(spikeMw) or 10.00)
    local totalLoad = s.peakLoadMw + spike
    local maxCapacity = Config.PowerGrid.MaxRatedCapacityMw or 75.00

    if totalLoad > maxCapacity then
        -- Damaging overload surge: Wear down turbine and trip circuit breaker
        s.conditionHealth = math.max(0.00, s.conditionHealth - 15.00)
        s.breakerTripped = true
        s.failureReason = "overload_trip"

        evaluateSubstationState(s, true)

        return true, {
            tripped = true,
            totalLoad = totalLoad,
            capacity = maxCapacity,
            substationId = substationId,
            conditionHealth = s.conditionHealth
        }
    end

    return true, {
        tripped = false,
        totalLoad = totalLoad,
        capacity = maxCapacity,
        substationId = substationId
    }
end

-- 7. Player Maintenance: Refuel Substation Generator
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

    -- If restored above critical threshold, mark matching open logistics contracts fulfilled
    if s.fuelLevel > (Config.PowerGrid.CriticalWarningThreshold or 20.00) then
        local destShelfId = "substation:" .. substationId
        MySQL.prepare.await([[
            UPDATE `nyx_logistics_contracts`
            SET `status` = 'fulfilled'
            WHERE `dest_shelf_id` = ? AND `item_id` = 'industrial_fuel' AND `status` IN ('available', 'in_transit')
        ]], { destShelfId })
    end

    -- If failure was solely fuel exhaustion and health is intact, attempt re-energization
    if s.failureReason == "fuel_exhaustion" and s.conditionHealth > (Config.PowerGrid.BlackoutHealthThreshold or 10.00) then
        s.breakerTripped = false
        s.failureReason = nil
    end

    evaluateSubstationState(s, true)

    return true, {
        substationId = substationId,
        fuelLevel = s.fuelLevel,
        isBlackout = s.isBlackout,
        breakerTripped = s.breakerTripped
    }
end

-- 8. Player Maintenance: Mechanical Repair
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

    -- If restored above critical threshold, mark matching open logistics contracts fulfilled
    if s.conditionHealth > (Config.PowerGrid.CriticalWarningThreshold or 20.00) then
        local destShelfId = "substation:" .. substationId
        MySQL.prepare.await([[
            UPDATE `nyx_logistics_contracts`
            SET `status` = 'fulfilled'
            WHERE `dest_shelf_id` = ? AND `item_id` = 'tool_repairkit' AND `status` IN ('available', 'in_transit')
        ]], { destShelfId })
    end

    -- If failure was solely mechanical breakdown and fuel is intact, attempt re-energization
    if s.failureReason == "mechanical_breakdown" and s.fuelLevel > (Config.PowerGrid.BlackoutFuelThreshold or 0.00) then
        s.breakerTripped = false
        s.failureReason = nil
    end

    evaluateSubstationState(s, true)

    return true, {
        substationId = substationId,
        conditionHealth = s.conditionHealth,
        isBlackout = s.isBlackout,
        breakerTripped = s.breakerTripped
    }
end

-- 9. Comprehensive Substation Diagnostics Query
function Nyx.Services.GetSubstationDiagnostics(substationId)
    local s = Nyx.Services.Substations[substationId]
    if not s then return nil end

    local burnRate = Config.PowerGrid.FuelConsumptionPerMinute or 0.50
    local estHours = (burnRate > 0) and ((s.fuelLevel / burnRate) / 60.0) or 999.0

    local status = "OPTIMAL"
    if s.isBlackout then
        status = "BLACKOUT"
    elseif s.fuelLevel <= 30.00 or s.conditionHealth <= 30.00 then
        status = "WARNING"
    end

    return {
        substationId = s.id,
        label = s.label,
        status = status,
        fuelLevel = s.fuelLevel,
        conditionHealth = s.conditionHealth,
        isBlackout = s.isBlackout,
        breakerTripped = s.breakerTripped,
        failureReason = s.failureReason,
        blackoutStartedAt = s.blackoutStartedAt,
        peakLoadMw = s.peakLoadMw,
        totalBlackoutsCount = s.totalBlackoutsCount,
        estimatedRuntimeHours = math.floor(estHours * 100) / 100,
        connectedDistricts = s.connectedDistricts,
        coords = { x = s.coords.x, y = s.coords.y, z = s.coords.z },
        radius = s.radius
    }
end

-- 10. Spatial Query: Is a coordinate currently energized?
function Nyx.Services.IsCoordsPowered(coords)
    if not coords then return true, nil end
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

-- 11. Query specific substation status
function Nyx.Services.GetSubstation(substationId)
    return Nyx.Services.Substations[substationId]
end

-- 12. Query all substations
function Nyx.Services.GetAllSubstations()
    return Nyx.Services.Substations
end
