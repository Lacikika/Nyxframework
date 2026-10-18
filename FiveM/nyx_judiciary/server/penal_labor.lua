--[[
    Nyxframework: nyx_judiciary
    File: server/penal_labor.lua
    Description: Server-side Bolingbroke penitentiary industrial work benches, penal labor execution,
                 material consumption from workshop stashes, sentence reductions, and treasury transfers.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}

local WORKSHOP_STASH = "stash:bolingbroke_workshop"
local CIVIC_OUTPUT_STASH = "stash:bolingbroke_civic_output"
local PENAL_TREASURY_ACC = "gov:corrections:penal_labor"
local CITY_MASTER_ACC = "gov:city:master"

-- Generate UUID helper
local function GenerateUUID()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return (string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end))
end

--- Incarcerate citizen or extend sentence in penal records
--- @param citizenId string
--- @param sentenceMonths number
--- @param cellAssigned string|nil
--- @return boolean success, table|string recordOrError
function Nyx.Judiciary.IncarcerateCitizen(citizenId, sentenceMonths, cellAssigned)
    if not citizenId or type(citizenId) ~= "string" then
        return false, "INVALID_CITIZEN_ID"
    end

    local months = math.max(0, math.floor(tonumber(sentenceMonths) or 0))
    local cell = cellAssigned or "cell_block_a"

    local existing = MySQL.single.await([[
        SELECT `record_id`, `citizen_id`, `original_sentence_months`, `current_sentence_months`,
               `labor_cycles_completed`, `total_reduction_months`, `total_civic_value_generated`,
               `status`, `cell_assigned`
        FROM `nyx_judiciary_penal_records`
        WHERE `citizen_id` = ?
    ]], { citizenId })

    if existing then
        local newOrig = existing.original_sentence_months + months
        local newCur = existing.current_sentence_months + months

        MySQL.prepare.await([[
            UPDATE `nyx_judiciary_penal_records`
            SET `original_sentence_months` = ?,
                `current_sentence_months` = ?,
                `status` = 'incarcerated',
                `cell_assigned` = ?,
                `updated_at` = CURRENT_TIMESTAMP
            WHERE `citizen_id` = ?
        ]], { newOrig, newCur, cell, citizenId })

        existing.original_sentence_months = newOrig
        existing.current_sentence_months = newCur
        existing.status = 'incarcerated'
        existing.cell_assigned = cell
        return true, existing
    else
        MySQL.prepare.await([[
            INSERT INTO `nyx_judiciary_penal_records`
            (`citizen_id`, `original_sentence_months`, `current_sentence_months`, `labor_cycles_completed`,
             `total_reduction_months`, `total_civic_value_generated`, `status`, `cell_assigned`)
            VALUES (?, ?, ?, 0, 0, 0.00, 'incarcerated', ?)
        ]], { citizenId, months, months, cell })

        local rec = {
            citizen_id = citizenId,
            original_sentence_months = months,
            current_sentence_months = months,
            labor_cycles_completed = 0,
            total_reduction_months = 0,
            total_civic_value_generated = 0.00,
            status = 'incarcerated',
            cell_assigned = cell
        }
        return true, rec
    end
end

--- Get inmate custodial and labor record
--- @param citizenId string
--- @return table|nil record
function Nyx.Judiciary.GetPenalRecord(citizenId)
    if not citizenId then return nil end

    return MySQL.single.await([[
        SELECT `record_id`, `citizen_id`, `original_sentence_months`, `current_sentence_months`,
               `labor_cycles_completed`, `total_reduction_months`, `total_civic_value_generated`,
               `status`, `cell_assigned`, `last_labor_at`, `created_at`, `updated_at`
        FROM `nyx_judiciary_penal_records`
        WHERE `citizen_id` = ?
    ]], { citizenId })
end

--- Retrieve material stock quantities in the Bolingbroke workshop stash
--- @param stashId string|nil
--- @return table<string, number>
function Nyx.Judiciary.GetWorkshopSupplies(stashId)
    local targetStash = stashId or WORKSHOP_STASH
    local stock = {}

    -- Direct authoritative query from inventory database
    local rows = MySQL.query.await([[
        SELECT `item_id`, SUM(`amount`) AS `total_amount`
        FROM `nyx_inventory_items`
        WHERE `inventory_id` = ?
        GROUP BY `item_id`
    ]], { targetStash })

    if rows then
        for _, row in ipairs(rows) do
            stock[row.item_id] = tonumber(row.total_amount) or 0
        end
    end

    return stock
end

--- Release inmate upon complete sentence fulfillment
--- @param citizenId string
--- @param optionalSrc number|nil
--- @return boolean success, string|nil message
function Nyx.Judiciary.ReleaseInmate(citizenId, optionalSrc)
    if not citizenId then return false, "INVALID_CITIZEN_ID" end

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_penal_records`
        SET `current_sentence_months` = 0,
            `status` = 'released',
            `updated_at` = CURRENT_TIMESTAMP
        WHERE `citizen_id` = ?
    ]], { citizenId })

    local player = optionalSrc and exports['nyx_core']:GetPlayer(optionalSrc)
    if not player then
        player = Nyx.GetPlayerByCitizenId and Nyx.GetPlayerByCitizenId(citizenId)
    end

    if player then
        player:setMetadata("inJail", false)
        player:setMetadata("prisonSentence", 0)

        -- Restore routing bucket to standard public dimension (0)
        if exports['nyx_core'] and exports['nyx_core'].SetRoutingBucket then
            exports['nyx_core']:SetRoutingBucket(player.source, 0)
        end

        -- Teleport ped to Bolingbroke exterior gate
        local releaseCoords = (Config.Penitentiary and Config.Penitentiary.ReleaseCoords) or vector4(1848.0, 2586.0, 45.6, 270.0)
        local ped = GetPlayerPed(tostring(player.source))
        if DoesEntityExist(ped) then
            SetEntityCoords(ped, releaseCoords.x, releaseCoords.y, releaseCoords.z, false, false, false, true)
            SetEntityHeading(ped, releaseCoords.w or 0.0)
        end

        TriggerClientEvent("nyx:judiciary:client:released", player.source, {
            citizenId = citizenId,
            message = "You have served your custodial sentence and are officially discharged from Bolingbroke State Penitentiary."
        })
    end

    return true, "INMATE_DISCHARGED"
end

--- Execute a complete penal labor cycle at a designated workstation
--- @param src number
--- @param payload table
--- @return table response
function Nyx.Judiciary.ExecuteLaborCycle(src, payload)
    local player = exports['nyx_core']:GetPlayer(src)
    if not player then
        return { success = false, error = "UNAUTHENTICATED" }
    end

    -- 1. Validate payload structure
    local isValid, errCode, sanitized = Nyx.PenalLabor.ValidateLaborPayload(payload)
    if not isValid then
        return { success = false, error = errCode }
    end

    local wsId = sanitized.workstationId
    local recipeId = sanitized.recipeId
    local batchMultiplier = sanitized.batchMultiplier

    local workstation = Nyx.PenalLabor.GetWorkstation(wsId)
    local recipe = Nyx.PenalLabor.GetRecipe(recipeId)

    -- 2. Verify inmate status and eligibility
    local penalRecord = Nyx.Judiciary.GetPenalRecord(player.citizenId)
    local canWork, ineligibilityReason = Nyx.PenalLabor.ValidateLaborEligibility(penalRecord)
    if not canWork then
        return { success = false, error = ineligibilityReason }
    end

    -- 3. Verify proximity to workstation
    local ped = GetPlayerPed(tostring(src))
    if DoesEntityExist(ped) and workstation.coords then
        local pCoords = GetEntityCoords(ped)
        local dist = #(pCoords - workstation.coords)
        local maxDist = (workstation.radius or 2.5) + 5.0 -- generous radius for sync
        if dist > maxDist then
            return { success = false, error = "TOO_FAR_FROM_WORKSTATION", distance = dist }
        end
    end

    -- 4. Check available input materials in workshop stash
    local currentSupplies = Nyx.Judiciary.GetWorkshopSupplies(WORKSHOP_STASH)
    local hasInputs, missingItem, needed, have = Nyx.PenalLabor.ValidateLaborInputs(recipe, currentSupplies, batchMultiplier)
    if not hasInputs then
        return {
            success = false,
            error = "INSUFFICIENT_MATERIALS",
            missingItem = missingItem,
            needed = needed,
            have = have
        }
    end

    -- 5. Consume raw input materials from workshop stash
    for _, input in ipairs(recipe.inputs) do
        local consumeAmount = input.amount * batchMultiplier
        local removed = false

        if exports['nyx_inventory'] and exports['nyx_inventory'].RemoveItem then
            removed = exports['nyx_inventory']:RemoveItem(WORKSHOP_STASH, input.item, consumeAmount)
        end

        if not removed then
            -- Fallback direct database deduction
            MySQL.prepare.await([[
                UPDATE `nyx_inventory_items`
                SET `amount` = `amount` - ?
                WHERE `inventory_id` = ? AND `item_id` = ? AND `amount` >= ?
                LIMIT 1
            ]], { consumeAmount, WORKSHOP_STASH, input.item, consumeAmount })
        end
    end

    -- 6. Deposit produced civic goods into Bolingbroke civic output stash
    local outputs = Nyx.PenalLabor.CalculateLaborOutputs(recipe, batchMultiplier, player.citizenId)
    for _, out in ipairs(outputs) do
        local added = false
        if exports['nyx_inventory'] and exports['nyx_inventory'].AddItem then
            added = exports['nyx_inventory']:AddItem(CIVIC_OUTPUT_STASH, out.item, out.amount, out.metadata)
        end

        if not added then
            -- Fallback direct database insertion
            MySQL.prepare.await([[
                INSERT INTO `nyx_inventory_items`
                (`item_uuid`, `inventory_id`, `item_id`, `slot`, `amount`, `metadata`)
                VALUES (UUID(), ?, ?, (SELECT IFNULL(MAX(i.slot), 0) + 1 FROM `nyx_inventory_items` i WHERE i.inventory_id = ?), ?, ?)
            ]], { CIVIC_OUTPUT_STASH, out.item, CIVIC_OUTPUT_STASH, out.amount, json.encode(out.metadata) })
        end
    end

    -- 7. Calculate sentence reduction and update custodial record
    local totalReduction = recipe.sentenceReductionMonths * batchMultiplier
    local newSentence, actualReduction, isEligibleForRelease = Nyx.PenalLabor.CalculateSentenceReduction(
        penalRecord.current_sentence_months,
        totalReduction
    )
    local civicFunds = Nyx.PenalLabor.CalculateCivicValue(recipe.id, batchMultiplier)

    MySQL.prepare.await([[
        UPDATE `nyx_judiciary_penal_records`
        SET `current_sentence_months` = ?,
            `labor_cycles_completed` = `labor_cycles_completed` + ?,
            `total_reduction_months` = `total_reduction_months` + ?,
            `total_civic_value_generated` = `total_civic_value_generated` + ?,
            `last_labor_at` = CURRENT_TIMESTAMP,
            `updated_at` = CURRENT_TIMESTAMP
        WHERE `citizen_id` = ?
    ]], { newSentence, batchMultiplier, actualReduction, civicFunds, player.citizenId })

    -- Synchronize player metadata
    player:setMetadata("prisonSentence", newSentence)

    -- 8. Credit civic value into Municipal Corrections Treasury account
    if exports['nyx_treasury'] and exports['nyx_treasury'].ExecuteTransfer then
        pcall(function()
            exports['nyx_treasury']:ExecuteTransfer(
                PENAL_TREASURY_ACC,
                CITY_MASTER_ACC,
                civicFunds,
                "penal_labor",
                "inmate:" .. player.citizenId,
                string.format("Penal Labor Civic Production: %s", recipe.label),
                0.0
            )
        end)
    end

    -- 9. Record immutable audit log
    local logUuid = GenerateUUID()
    MySQL.prepare.await([[
        INSERT INTO `nyx_judiciary_penal_labor_logs`
        (`log_uuid`, `citizen_id`, `workstation_id`, `recipe_id`, `sentence_reduced_months`,
         `sentence_remaining_months`, `civic_funds_generated`, `items_consumed_json`, `items_produced_json`, `destination_stash`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        logUuid,
        player.citizenId,
        wsId,
        recipeId,
        actualReduction,
        newSentence,
        civicFunds,
        json.encode(recipe.inputs),
        json.encode(outputs),
        CIVIC_OUTPUT_STASH
    })

    -- 10. Check and trigger discharge if sentence fulfilled
    local discharged = false
    if isEligibleForRelease then
        Nyx.Judiciary.ReleaseInmate(player.citizenId, src)
        discharged = true
    end

    return {
        success = true,
        recipeId = recipeId,
        workstationId = wsId,
        batchMultiplier = batchMultiplier,
        reducedMonths = actualReduction,
        remainingMonths = newSentence,
        civicFundsGenerated = civicFunds,
        isDischarged = discharged,
        itemsProduced = outputs
    }
end

--- Get historical labor logs for an inmate
--- @param citizenId string
--- @param limit number|nil
--- @return table logs
function Nyx.Judiciary.GetPenalLaborLogs(citizenId, limit)
    local maxLimit = math.min(100, math.max(1, tonumber(limit) or 20))
    local rows = MySQL.query.await([[
        SELECT `log_id`, `log_uuid`, `citizen_id`, `workstation_id`, `recipe_id`,
               `sentence_reduced_months`, `sentence_remaining_months`, `civic_funds_generated`,
               `destination_stash`, `created_at`
        FROM `nyx_judiciary_penal_labor_logs`
        WHERE `citizen_id` = ?
        ORDER BY `log_id` DESC
        LIMIT ?
    ]], { citizenId, maxLimit })

    return rows or {}
end

-- ----------------------------------------------------------------------------
-- RPC Endpoints Registration on nyx_core Bus
-- ----------------------------------------------------------------------------
CreateThread(function()
    if exports['nyx_core'] and exports['nyx_core'].RegisterRPC then
        -- Inmate overview telemetry: status, sentence, recipes, and workshop stock
        exports['nyx_core']:RegisterRPC("judiciary:getPenalOverview", function(src)
            local player = exports['nyx_core']:GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local penalRecord = Nyx.Judiciary.GetPenalRecord(player.citizenId)
            local supplies = Nyx.Judiciary.GetWorkshopSupplies(WORKSHOP_STASH)
            local recipes = Nyx.PenalLabor.GetAllRecipes()
            local workstations = Nyx.PenalLabor.GetAllWorkstations()

            local statusBadge = penalRecord and Nyx.PenalLabor.FormatPenalStatusBadge(
                penalRecord.status,
                penalRecord.current_sentence_months
            ) or nil

            return {
                success = true,
                penalRecord = penalRecord,
                statusBadge = statusBadge,
                supplies = supplies,
                recipes = recipes,
                workstations = workstations,
                workshopStash = WORKSHOP_STASH,
                civicOutputStash = CIVIC_OUTPUT_STASH
            }
        end)

        -- Execute penal labor at workstation
        exports['nyx_core']:RegisterRPC("judiciary:executePenalLabor", function(src, payload)
            return Nyx.Judiciary.ExecuteLaborCycle(src, payload)
        end)

        -- Request inmate discharge if sentence reaches 0
        exports['nyx_core']:RegisterRPC("judiciary:requestPenalRelease", function(src)
            local player = exports['nyx_core']:GetPlayer(src)
            if not player then return { success = false, error = "UNAUTHENTICATED" } end

            local penalRecord = Nyx.Judiciary.GetPenalRecord(player.citizenId)
            if not penalRecord then
                return { success = false, error = "NOT_INCARCERATED" }
            end

            if penalRecord.status ~= "incarcerated" then
                return { success = false, error = "ALREADY_RELEASED" }
            end

            if penalRecord.current_sentence_months > 0 then
                return {
                    success = false,
                    error = "SENTENCE_NOT_COMPLETED",
                    remaining = penalRecord.current_sentence_months
                }
            end

            local ok, msg = Nyx.Judiciary.ReleaseInmate(player.citizenId, src)
            return { success = ok, message = msg }
        end)

        -- Get workstation definitions
        exports['nyx_core']:RegisterRPC("judiciary:getPenalWorkstations", function(src)
            return {
                success = true,
                workstations = Nyx.PenalLabor.GetAllWorkstations()
            }
        end)
    end
end)

-- ----------------------------------------------------------------------------
-- Logistics Delivery Hook: Materials Delivered to Bolingbroke Workshop Stash
-- ----------------------------------------------------------------------------
RegisterNetEvent("nyx:judiciary:server:workshopMaterialsDelivered", function(destStashId, contractId, itemId, quantity)
    if destStashId ~= WORKSHOP_STASH and destStashId ~= CIVIC_OUTPUT_STASH then return end

    if Config.Debug then
        print(string.format("^2[Nyx:Judiciary]^7 Bolingbroke logistics delivery: %d units of %s received at %s (Contract: %s)^7",
            quantity, itemId, destStashId, tostring(contractId)))
    end

    -- Broadcast to active prison inmates that materials have been replenished
    TriggerClientEvent("nyx:judiciary:client:workshopStockUpdated", -1, {
        stashId = destStashId,
        itemId = itemId,
        quantity = quantity
    })
end)
