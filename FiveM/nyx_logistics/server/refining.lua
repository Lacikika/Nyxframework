--[[
    Nyxframework: nyx_logistics
    File: server/refining.lua
    Description: Authoritative industrial refining subsystem, sawmill & foundry batch processing,
                 audit logging, substation power interlocks, and RPC registration.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.Refining = {}

--- Generate a cryptographically secure or pseudo-random UUID for refining audits
--- @return string uuid
local function generateAuditUuid()
    if Nyx.RPC and Nyx.RPC.GenerateNonce then
        return string.format("ref-%s", Nyx.RPC.GenerateNonce():sub(1, 16))
    end
    return string.format("ref-%d-%06d", os.time(), math.random(100000, 999999))
end

--- Inserts an immutable record into the nyx_logistics_refining_audits ledger
--- @param facilityId string
--- @param citizenId string
--- @param action string
--- @param recipeKey string
--- @param batchCount number
--- @param inputs table|nil
--- @param outputs table|nil
--- @param powerKwh number
--- @param substationId string|nil
--- @param notes string|nil
--- @return string auditUuid
function Nyx.Logistics.LogRefiningAudit(facilityId, citizenId, action, recipeKey, batchCount, inputs, outputs, powerKwh, substationId, notes)
    local uuid = generateAuditUuid()
    local inputsJson = inputs and json.encode(inputs) or "{}"
    local outputsJson = outputs and json.encode(outputs) or "{}"
    local kwh = tonumber(powerKwh) or 0.0

    pcall(function()
        MySQL.prepare([[
            INSERT INTO `nyx_logistics_refining_audits`
                (`audit_uuid`, `facility_id`, `citizen_id`, `action`, `recipe_key`, `batch_count`,
                 `inputs_consumed`, `outputs_generated`, `power_kwh_consumed`, `substation_id`, `notes`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            uuid,
            facilityId,
            citizenId,
            action,
            recipeKey,
            batchCount or 1,
            inputsJson,
            outputsJson,
            kwh,
            substationId,
            notes or ""
        })
    end)

    return uuid
end

--- Retrieves all registered industrial refining facilities formatted for telemetry
--- @return table facilities
function Nyx.Logistics.GetRefiningFacilities()
    local list = {}
    if Nyx.Logistics.Facilities then
        for facId, fac in pairs(Nyx.Logistics.Facilities) do
            local isPowered, powerReason = Nyx.Logistics.IsFacilityPowered(facId)
            local activeRecipe = fac.active_recipe and Nyx.Logistics.GetRecipe(fac.active_recipe) or nil
            list[#list + 1] = Nyx.Refining.FormatFacilityTelemetry(fac, activeRecipe, isPowered, powerReason)
        end
    end
    return list
end

--- Retrieves a single refining facility by ID formatted for telemetry
--- @param facilityId string
--- @return table|nil telemetry
function Nyx.Logistics.GetRefiningFacility(facilityId)
    local fac = Nyx.Logistics.Facilities and Nyx.Logistics.Facilities[facilityId]
    if not fac then return nil end

    local isPowered, powerReason = Nyx.Logistics.IsFacilityPowered(facilityId)
    local activeRecipe = fac.active_recipe and Nyx.Logistics.GetRecipe(fac.active_recipe) or nil
    return Nyx.Refining.FormatFacilityTelemetry(fac, activeRecipe, isPowered, powerReason)
end

--- Authoritative batch execution starter with distance, power, and inventory validation
--- @param src number
--- @param facilityId string
--- @param recipeKey string
--- @param batchCount number
--- @return table result
function Nyx.Logistics.StartRefiningBatch(src, facilityId, recipeKey, batchCount)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then
        return { success = false, error = "UNAUTHENTICATED" }
    end

    local fac = Nyx.Logistics.Facilities and Nyx.Logistics.Facilities[facilityId]
    if not fac then
        return { success = false, error = "FACILITY_NOT_FOUND" }
    end

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

    -- Proximity verification (within 4.5m of facility coordinates)
    local ped = GetPlayerPed(tostring(src))
    local playerCoords = GetEntityCoords(ped)
    if fac.coords then
        local isNear, dist = Nyx.Refining.IsPointNearFacility(playerCoords, fac.coords, 4.5)
        if not isNear then
            return { success = false, error = "OUT_OF_RANGE", distance = dist }
        end
    end

    -- Trade Union Strike Interlock
    if fac.owner and exports['nyx_factions'] and exports['nyx_factions'].IsEnterpriseOnStrike then
        local onStrike = exports['nyx_factions']:IsEnterpriseOnStrike(fac.owner)
        if onStrike then
            return { success = false, error = "ENTERPRISE_FACILITY_PICKET_LOCKED" }
        end
    end

    batchCount = math.max(1, math.min(20, tonumber(batchCount) or 1))

    -- Power Grid Interlock: verify connected substation power
    local isPowered, powerErr, sub = Nyx.Logistics.IsFacilityPowered(facilityId)
    if not isPowered then
        return { success = false, error = powerErr or "POWER_GRID_OFFLINE" }
    end

    -- Input Inventory Validation: check facility input stash
    local inputInv = exports['nyx_inventory'] and exports['nyx_inventory']:GetInventory(fac.input_inv)
    if not inputInv then
        return { success = false, error = "INPUT_INVENTORY_UNAVAILABLE" }
    end

    local availableItems = {}
    for _, input in ipairs(recipe.inputs) do
        availableItems[input.item] = exports['nyx_inventory']:GetItemCount(fac.input_inv, input.item)
    end

    local okInputs, errInput, missingItem, needed, have = Nyx.Refining.ValidateRefiningInputs(recipe, availableItems, batchCount)
    if not okInputs then
        return {
            success = false,
            error = errInput,
            missingItem = missingItem,
            needed = needed,
            have = have
        }
    end

    -- Deduct inputs from input inventory
    for _, input in ipairs(recipe.inputs) do
        local requiredTotal = input.amount * batchCount
        exports['nyx_inventory']:RemoveItem(fac.input_inv, input.item, requiredTotal)
    end

    -- Calculate processing duration, power, and expected energy
    local durationSec, powerKw, expectedKwh = Nyx.Refining.CalculateRefiningEnergyAndDuration(recipe, batchCount)

    -- Substation load spike simulation
    if exports['nyx_services'] and exports['nyx_services'].SimulateGridOverload and fac.power_grid then
        local spikeMw = Nyx.Assembly.CalculateGridLoadSpike(powerKw, batchCount)
        if spikeMw >= 0.025 then
            exports['nyx_services']:SimulateGridOverload(fac.power_grid, spikeMw)
        end
    end

    -- Update facility state in memory and database
    fac.is_active = true
    fac.active_recipe = recipeKey
    fac.progress = 0.0
    fac.batches = batchCount
    fac.power_status = "online"
    fac.power_consumption_kw = powerKw

    MySQL.prepare([[
        UPDATE `nyx_logistics_facilities`
        SET `is_active` = 1, `active_recipe` = ?, `progress` = 0.00,
            `power_status` = 'online', `power_consumption_kw` = ?
        WHERE `facility_id` = ?
    ]], { recipeKey, powerKw, facilityId })

    -- Log audit entry
    local auditUuid = Nyx.Logistics.LogRefiningAudit(
        facilityId,
        player.citizenId,
        Nyx.Refining.Actions.REFINING_STARTED,
        recipeKey,
        batchCount,
        recipe.inputs,
        recipe.outputs,
        expectedKwh,
        fac.power_grid,
        string.format("Started %d batch(es) of %s by citizen %s", batchCount, recipeKey, player.citizenId)
    )

    TriggerClientEvent("nyx:logistics:client:facilityStarted", -1, {
        facilityId = facilityId,
        recipeKey = recipeKey,
        batches = batchCount,
        powerKw = powerKw,
        durationSeconds = durationSec,
        auditUuid = auditUuid
    })

    return {
        success = true,
        auditUuid = auditUuid,
        facilityId = facilityId,
        recipeKey = recipeKey,
        batchCount = batchCount,
        powerKw = powerKw,
        durationSeconds = durationSec
    }
end

--- Aborts an active batch at a facility and logs an audit record
--- @param src number
--- @param facilityId string
--- @return table result
function Nyx.Logistics.CancelRefiningBatch(src, facilityId)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then return { success = false, error = "UNAUTHENTICATED" } end

    local fac = Nyx.Logistics.Facilities and Nyx.Logistics.Facilities[facilityId]
    if not fac then return { success = false, error = "FACILITY_NOT_FOUND" } end

    if not fac.is_active then
        return { success = false, error = "FACILITY_NOT_ACTIVE" }
    end

    local prevRecipe = fac.active_recipe
    local prevBatches = fac.batches or 1

    fac.is_active = false
    fac.active_recipe = nil
    fac.progress = 0.0
    fac.batches = 1
    fac.power_consumption_kw = 0.0

    MySQL.prepare([[
        UPDATE `nyx_logistics_facilities`
        SET `is_active` = 0, `active_recipe` = NULL, `progress` = 0.00,
            `power_consumption_kw` = 0.00
        WHERE `facility_id` = ?
    ]], { facilityId })

    local auditUuid = Nyx.Logistics.LogRefiningAudit(
        facilityId,
        player.citizenId,
        Nyx.Refining.Actions.REFINING_HALTED_BLACKOUT,
        prevRecipe or "unknown",
        prevBatches,
        {},
        {},
        0.0,
        fac.power_grid,
        string.format("Aborted active refining batch by citizen %s", player.citizenId)
    )

    TriggerClientEvent("nyx:logistics:client:facilityCompleted", -1, facilityId)

    return {
        success = true,
        auditUuid = auditUuid,
        facilityId = facilityId
    }
end

-- ==============================================================================
-- RPC Registrations
-- ==============================================================================

Nyx.RPC.Register("logistics:getRefiningFacilities", function(src)
    return Nyx.Logistics.GetRefiningFacilities()
end)

Nyx.RPC.Register("logistics:getRefiningFacilityTelemetry", function(src, facilityId)
    return Nyx.Logistics.GetRefiningFacility(facilityId)
end)

Nyx.RPC.Register("logistics:startRefiningBatch", function(src, facilityId, recipeKey, batchCount)
    return Nyx.Logistics.StartRefiningBatch(src, facilityId, recipeKey, batchCount)
end)

Nyx.RPC.Register("logistics:cancelRefiningBatch", function(src, facilityId)
    return Nyx.Logistics.CancelRefiningBatch(src, facilityId)
end)
