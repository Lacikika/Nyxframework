--[[
    Nyxframework: nyx_logistics
    File: server/facilities.lua
    Description: Industrial processing facilities, conversion queue runner,
                 power grid substation integration, and physical pallet packaging.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.Facilities = {} -- [facilityId] = facilityState

-- Helper to safely parse JSON coords
local function parseCoordsJson(jsonVal)
    if not jsonVal then return nil end
    if type(jsonVal) == "table" then return jsonVal end
    if type(jsonVal) == "string" then
        local ok, parsed = pcall(json.decode, jsonVal)
        if ok and type(parsed) == "table" then return parsed end
    end
    return nil
end

-- 1. Bootloader: Load facilities from database into memory
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end

    local rows = MySQL.query.await("SELECT * FROM `nyx_logistics_facilities`")
    if rows then
        -- Performance: Batch pre-load all facility input & output stashes in one array query
        local stashIds = {}
        for _, row in ipairs(rows) do
            if row.input_inventory_id and row.input_inventory_id ~= "" then
                stashIds[#stashIds + 1] = row.input_inventory_id
            end
            if row.output_inventory_id and row.output_inventory_id ~= "" then
                stashIds[#stashIds + 1] = row.output_inventory_id
            end
        end

        if #stashIds > 0 and exports['nyx_inventory'] and exports['nyx_inventory'].BatchLoadInventories then
            exports['nyx_inventory']:BatchLoadInventories(stashIds, 'stash')
        end

        for _, row in ipairs(rows) do
            local coords = parseCoordsJson(row.coords)
            local dockCoords = parseCoordsJson(row.pallet_dock_coords)

            Nyx.Logistics.Facilities[row.facility_id] = {
                id = row.facility_id,
                owner = row.owner_faction_id,
                type = row.type,
                coords = coords,
                input_inv = row.input_inventory_id,
                output_inv = row.output_inventory_id,
                power_grid = row.power_grid_id,
                power_status = row.power_status or "online",
                power_consumption_kw = tonumber(row.power_consumption_kw) or 0.0,
                total_energy_consumed_kwh = tonumber(row.total_energy_consumed_kwh) or 0.0,
                pallet_dock_coords = dockCoords,
                pallet_dock_heading = tonumber(row.pallet_dock_heading) or 0.0,
                output_mode = row.output_mode or "inventory",
                is_active = (tonumber(row.is_active) == 1),
                active_recipe = row.active_recipe,
                progress = tonumber(row.progress) or 0.0,
                batches = 1
            }

            -- Ensure input and output stashes exist in nyx_inventory
            if exports['nyx_inventory'] then
                exports['nyx_inventory']:GetInventory(row.input_inventory_id)
                exports['nyx_inventory']:GetInventory(row.output_inventory_id)
            end
        end
        print(string.format("^2[Nyx:Logistics] Loaded %d industrial refining and assembly facilities into memory.^7", #rows))
    end
end)

--- Query if a facility currently has active electrical power from its regional substation
--- @param facilityId string
--- @return boolean isPowered, string reasonCode, table|nil substationData
function Nyx.Logistics.IsFacilityPowered(facilityId)
    local fac = Nyx.Logistics.Facilities[facilityId]
    if not fac then return false, "FACILITY_NOT_FOUND", nil end

    if exports['nyx_services'] then
        local sub = exports['nyx_services']:GetSubstation(fac.power_grid)
        if sub then
            local ok, reason = Nyx.Assembly.EvaluatePowerStatus(sub, fac.power_consumption_kw)
            return ok, reason, sub
        elseif fac.coords then
            local powered = exports['nyx_services']:IsCoordsPowered(fac.coords)
            if not powered then
                return false, Nyx.Assembly.PowerStates.GRID_BLACKOUT, nil
            end
        end
    end

    return true, Nyx.Assembly.PowerStates.OPTIMAL, nil
end

-- 2. RPC: Query Facility State & Diagnostics
Nyx.RPC.Register("logistics:getFacilityState", function(src, facilityId)
    local fac = Nyx.Logistics.Facilities[facilityId]
    if not fac then
        return nil, "FACILITY_NOT_FOUND"
    end

    local isPowered, powerReason, sub = Nyx.Logistics.IsFacilityPowered(facilityId)

    local inputInv = exports['nyx_inventory'] and exports['nyx_inventory']:GetInventory(fac.input_inv)
    local outputInv = exports['nyx_inventory'] and exports['nyx_inventory']:GetInventory(fac.output_inv)

    return {
        id = fac.id,
        type = fac.type,
        owner = fac.owner,
        isActive = fac.is_active,
        activeRecipe = fac.active_recipe,
        progress = fac.progress,
        batchesRemaining = fac.batches,
        powerGridId = fac.power_grid,
        powerStatus = isPowered and "online" or "offline",
        powerReason = powerReason,
        powerConsumptionKw = fac.power_consumption_kw,
        totalEnergyConsumedKwh = fac.total_energy_consumed_kwh,
        outputMode = fac.output_mode,
        palletDockCoords = fac.pallet_dock_coords,
        substationDetails = sub and {
            label = sub.label,
            fuelLevel = sub.fuelLevel,
            conditionHealth = sub.conditionHealth,
            breakerTripped = sub.breakerTripped,
            isBlackout = sub.isBlackout
        } or nil,
        inputSnapshot = inputInv and inputInv:getSnapshot() or nil,
        outputSnapshot = outputInv and outputInv:getSnapshot() or nil
    }
end)

-- 3. RPC: Start Manufacturing Batch with Power Grid Verification
Nyx.RPC.Register("logistics:startProduction", function(src, facilityId, recipeKey, batchCount)
    local fac = Nyx.Logistics.Facilities[facilityId]
    if not fac then return { success = false, error = "FACILITY_NOT_FOUND" } end

    if fac.is_active then
        return { success = false, error = "FACILITY_ALREADY_ACTIVE" }
    end

    local recipe = Nyx.Logistics.GetRecipe(recipeKey)
    if not recipe then
        return { success = false, error = "INVALID_RECIPE" }
    end

    if recipe.facilityType ~= fac.type then
        return { success = false, error = "INCOMPATIBLE_FACILITY_TYPE" }
    end

    -- Strike Picket Line Interlock: If facility owner faction is under active strike, reject production
    if fac.owner and exports['nyx_factions'] and exports['nyx_factions'].IsEnterpriseOnStrike then
        local onStrike = exports['nyx_factions']:IsEnterpriseOnStrike(fac.owner)
        if onStrike then
            return { success = false, error = "ENTERPRISE_FACILITY_PICKET_LOCKED" }
        end
    end

    batchCount = math.max(1, math.min(10, tonumber(batchCount) or 1))

    -- Power Grid Pre-flight Interlock: verify power availability before consuming items
    local isPowered, powerErr, sub = Nyx.Logistics.IsFacilityPowered(facilityId)
    if not isPowered then
        return { success = false, error = powerErr or "POWER_GRID_OFFLINE" }
    end

    -- Validate all required inputs in input inventory
    for _, input in ipairs(recipe.inputs) do
        local requiredTotal = input.amount * batchCount
        local has = exports['nyx_inventory']:HasItem(fac.input_inv, input.item, requiredTotal)
        if not has then
            return { success = false, error = string.format("INSUFFICIENT_INPUTS: %s (need %d)", input.item, requiredTotal) }
        end
    end

    -- Consume inputs from input inventory
    for _, input in ipairs(recipe.inputs) do
        local requiredTotal = input.amount * batchCount
        exports['nyx_inventory']:RemoveItem(fac.input_inv, input.item, requiredTotal)
    end

    -- High-power equipment load spike on connected substation
    local powerKw = recipe.powerRequirementKw or 15
    if exports['nyx_services'] and exports['nyx_services'].SimulateGridOverload and fac.power_grid then
        local spikeMw = Nyx.Assembly.CalculateGridLoadSpike(powerKw, batchCount)
        if spikeMw >= 0.030 then -- Significant load spike (30 kW+)
            exports['nyx_services']:SimulateGridOverload(fac.power_grid, spikeMw)
        end
    end

    -- Activate facility production
    fac.is_active = true
    fac.active_recipe = recipeKey
    fac.progress = 0.0
    fac.batches = batchCount
    fac.power_status = "online"
    fac.power_consumption_kw = powerKw * batchCount

    MySQL.prepare([[
        UPDATE `nyx_logistics_facilities`
        SET `is_active` = 1, `active_recipe` = ?, `progress` = 0.00,
            `power_status` = 'online', `power_consumption_kw` = ?
        WHERE `facility_id` = ?
    ]], { recipeKey, fac.power_consumption_kw, facilityId })

    TriggerClientEvent("nyx:logistics:client:facilityStarted", -1, {
        facilityId = facilityId,
        recipeKey = recipeKey,
        batches = batchCount,
        powerKw = fac.power_consumption_kw
    })

    return { success = true, powerKw = fac.power_consumption_kw }
end)

-- 4. RPC: Configure Facility Output Mode (Inventory Stash vs Direct Pallet Dock)
Nyx.RPC.Register("logistics:setOutputMode", function(src, facilityId, mode)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    local fac = Nyx.Logistics.Facilities[facilityId]
    if not fac then return { success = false, error = "FACILITY_NOT_FOUND" } end

    if mode ~= "inventory" and mode ~= "pallet" then
        return { success = false, error = "INVALID_OUTPUT_MODE" }
    end

    if mode == "pallet" and not fac.pallet_dock_coords then
        return { success = false, error = "FACILITY_NO_PALLET_DOCK" }
    end

    fac.output_mode = mode

    MySQL.prepare([[
        UPDATE `nyx_logistics_facilities`
        SET `output_mode` = ?
        WHERE `facility_id` = ?
    ]], { mode, facilityId })

    return { success = true, outputMode = mode }
end)

-- 5. Facility Queue Runner (Runs every Config.FacilityTickInterval seconds)
CreateThread(function()
    local tickSec = Config.FacilityTickInterval or 5
    while true do
        Wait(tickSec * 1000)

        for facilityId, fac in pairs(Nyx.Logistics.Facilities) do
            if fac.is_active and fac.active_recipe then
                local recipe = Nyx.Logistics.GetRecipe(fac.active_recipe)
                if recipe then
                    local isPowered, powerReason = Nyx.Logistics.IsFacilityPowered(facilityId)

                    if not isPowered then
                        -- Substation failure / blackout: halt machinery immediately
                        if fac.power_status ~= "offline" then
                            fac.power_status = "offline"
                            MySQL.prepare([[
                                UPDATE `nyx_logistics_facilities`
                                SET `power_status` = 'offline'
                                WHERE `facility_id` = ?
                            ]], { facilityId })

                            TriggerClientEvent("nyx:logistics:client:facilityPowerLost", -1, facilityId, fac.power_grid, powerReason)
                            print(string.format("^1[Nyx:Logistics] Facility '%s' HALTED: power grid outage on '%s' (%s)^7",
                                facilityId, tostring(fac.power_grid), powerReason))
                        end
                        -- Frozen: 0% progress step while power is out
                    else
                        -- Grid is energized: resume if previously halted
                        if fac.power_status == "offline" then
                            fac.power_status = "online"
                            MySQL.prepare([[
                                UPDATE `nyx_logistics_facilities`
                                SET `power_status` = 'online'
                                WHERE `facility_id` = ?
                            ]], { facilityId })

                            TriggerClientEvent("nyx:logistics:client:facilityPowerRestored", -1, facilityId, fac.power_grid)
                            print(string.format("^2[Nyx:Logistics] Facility '%s' RESUMED: power restored from '%s'^7",
                                facilityId, tostring(fac.power_grid)))
                        end

                        -- Metered Electrical Utility Consumption (kWh)
                        local powerKw = recipe.powerRequirementKw or 15
                        local kwh = Nyx.Assembly.CalculateEnergyUsageKwh(powerKw, tickSec)
                        fac.total_energy_consumed_kwh = (fac.total_energy_consumed_kwh or 0.0) + kwh

                        if exports['nyx_services'] and exports['nyx_services'].RecordUtilityConsumption then
                            exports['nyx_services']:RecordUtilityConsumption("meter:facility:" .. fac.id, kwh, 0.0)
                        end

                        -- Advance queue progress
                        local progressStep = Nyx.Assembly.CalculateProgressStep(recipe.processingTime or 30, tickSec, true)
                        fac.progress = math.min(100.0, fac.progress + progressStep)

                        if fac.progress >= 100.0 then
                            -- Generate batch output items
                            local batchOutputs = Nyx.Assembly.CalculateBatchOutputs(recipe, 1, os.time())
                            local totalWeight = Nyx.Assembly.CalculateTotalOutputWeight(batchOutputs)
                            local shouldPallet = Nyx.Assembly.ShouldAutoPalletize(fac.output_mode, totalWeight, 1)

                            if shouldPallet and fac.pallet_dock_coords then
                                -- Directly spawn and load onto physical freight pallet at loading bay
                                local dockCoords = fac.pallet_dock_coords
                                local dockHeading = fac.pallet_dock_heading or 0.0
                                local newPallet = Nyx.Logistics.CreateFreightPallet(
                                    dockCoords,
                                    dockHeading,
                                    0,
                                    batchOutputs,
                                    fac.owner or "industrial_assembly",
                                    string.format("%s Batch", recipe.label or "Finished Freight")
                                )
                                print(string.format("^2[Nyx:Logistics] Facility '%s' completed batch -> spawned freight pallet '%s' at loading dock.^7",
                                    facilityId, newPallet.id))
                            else
                                -- Standard loose item output into facility stash
                                for _, out in ipairs(batchOutputs) do
                                    exports['nyx_inventory']:AddItem(fac.output_inv, out.item, out.amount, out.metadata)
                                end
                            end

                            if fac.batches > 1 then
                                fac.batches = fac.batches - 1
                                fac.progress = 0.0
                            else
                                fac.is_active = false
                                fac.active_recipe = nil
                                fac.progress = 0.0
                                fac.batches = 1
                                fac.power_consumption_kw = 0.0

                                MySQL.prepare([[
                                    UPDATE `nyx_logistics_facilities`
                                    SET `is_active` = 0, `active_recipe` = NULL, `progress` = 0.00,
                                        `power_consumption_kw` = 0.00, `total_energy_consumed_kwh` = ?
                                    WHERE `facility_id` = ?
                                ]], { fac.total_energy_consumed_kwh, facilityId })

                                TriggerClientEvent("nyx:logistics:client:facilityCompleted", -1, facilityId)
                            end
                        end
                    end
                end
            end
        end
    end
end)
