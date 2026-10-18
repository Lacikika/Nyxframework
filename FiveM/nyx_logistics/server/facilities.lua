--[[
    Nyxframework: nyx_logistics
    File: server/facilities.lua
    Description: Industrial processing facilities, conversion queue runner, and inventory integration.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.Facilities = {} -- [facilityId] = facilityState

-- Load facilities from database into memory on boot
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end

    local rows = MySQL.query.await("SELECT * FROM `nyx_logistics_facilities`")
    if rows then
        for _, row in ipairs(rows) do
            Nyx.Logistics.Facilities[row.facility_id] = {
                id = row.facility_id,
                owner = row.owner_faction_id,
                type = row.type,
                input_inv = row.input_inventory_id,
                output_inv = row.output_inventory_id,
                power_grid = row.power_grid_id,
                is_active = (tonumber(row.is_active) == 1),
                active_recipe = row.active_recipe,
                progress = tonumber(row.progress) or 0.0,
                batches = 1
            }
            -- Ensure input and output stashes exist in nyx_inventory
            exports['nyx_inventory']:GetInventory(row.input_inventory_id)
            exports['nyx_inventory']:GetInventory(row.output_inventory_id)
        end
        print(string.format("^2[Nyx:Logistics] Loaded %d industrial refining and assembly facilities.^7", #rows))
    end
end)

-- RPC: Query Facility State
Nyx.RPC.Register("logistics:getFacilityState", function(src, facilityId)
    local fac = Nyx.Logistics.Facilities[facilityId]
    if not fac then
        return nil, "FACILITY_NOT_FOUND"
    end

    local inputInv = exports['nyx_inventory']:GetInventory(fac.input_inv)
    local outputInv = exports['nyx_inventory']:GetInventory(fac.output_inv)

    return {
        id = fac.id,
        type = fac.type,
        isActive = fac.is_active,
        activeRecipe = fac.active_recipe,
        progress = fac.progress,
        batchesRemaining = fac.batches,
        inputSnapshot = inputInv and inputInv:getSnapshot() or nil,
        outputSnapshot = outputInv and outputInv:getSnapshot() or nil
    }
end)

-- RPC: Start Manufacturing Batch
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

    batchCount = math.max(1, math.min(10, tonumber(batchCount) or 1))

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

    -- Activate facility production
    fac.is_active = true
    fac.active_recipe = recipeKey
    fac.progress = 0.0
    fac.batches = batchCount

    MySQL.prepare([[
        UPDATE `nyx_logistics_facilities`
        SET `is_active` = 1, `active_recipe` = ?, `progress` = 0.00
        WHERE `facility_id` = ?
    ]], { recipeKey, facilityId })

    return { success = true }
end)

-- Facility Queue Runner (Runs every Config.FacilityTickInterval seconds)
CreateThread(function()
    local tickSec = Config.FacilityTickInterval or 5
    while true do
        Wait(tickSec * 1000)

        for facilityId, fac in pairs(Nyx.Logistics.Facilities) do
            if fac.is_active and fac.active_recipe then
                local recipe = Nyx.Logistics.GetRecipe(fac.active_recipe)
                if recipe then
                    local totalTime = math.max(5, recipe.processingTime or 30)
                    local progressStep = (tickSec / totalTime) * 100.0
                    fac.progress = math.min(100.0, fac.progress + progressStep)

                    if fac.progress >= 100.0 then
                        -- Output produced items into output inventory
                        for _, out in ipairs(recipe.outputs) do
                            local meta = out.metadata or { quality = 1.0, createdAt = os.time() }
                            exports['nyx_inventory']:AddItem(fac.output_inv, out.item, out.amount, meta)
                        end

                        if fac.batches > 1 then
                            fac.batches = fac.batches - 1
                            fac.progress = 0.0
                        else
                            fac.is_active = false
                            fac.active_recipe = nil
                            fac.progress = 0.0
                            fac.batches = 1

                            MySQL.prepare([[
                                UPDATE `nyx_logistics_facilities`
                                SET `is_active` = 0, `active_recipe` = NULL, `progress` = 0.00
                                WHERE `facility_id` = ?
                            ]], { facilityId })
                        end
                    end
                end
            end
        end
    end
end)
