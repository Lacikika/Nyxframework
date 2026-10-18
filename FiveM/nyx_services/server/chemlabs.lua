--[[
    Nyxframework: nyx_services
    File: server/chemlabs.lua
    Description: Authoritative server engine for pharmaceutical refining, bio-chemical synthesis,
                 autoclave sterilization cycles, substation power grid monitoring, and regulatory audits.
]]

Nyx = Nyx or {}
Nyx.Services = Nyx.Services or {}
Nyx.Services.ChemicalLabs = {}

-- Helper to safely parse JSON coords
local function parseCoordsJson(jsonVal)
    if not jsonVal then return vector3(0.0, 0.0, 0.0) end
    if type(jsonVal) == "vector3" then return jsonVal end
    if type(jsonVal) == "table" then
        return vector3(tonumber(jsonVal.x or jsonVal[1]) or 0.0, tonumber(jsonVal.y or jsonVal[2]) or 0.0, tonumber(jsonVal.z or jsonVal[3]) or 0.0)
    end
    if type(jsonVal) == "string" then
        local ok, parsed = pcall(json.decode, jsonVal)
        if ok and type(parsed) == "table" then
            return vector3(tonumber(parsed.x or parsed[1]) or 0.0, tonumber(parsed.y or parsed[2]) or 0.0, tonumber(parsed.z or parsed[3]) or 0.0)
        end
    end
    return vector3(0.0, 0.0, 0.0)
end

-- Helper to generate unique UUIDs
local function generateUuid()
    if exports['nyx_core'] and exports['nyx_core'].GenerateNonce then
        return exports['nyx_core']:GenerateNonce()
    end
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return (string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end))
end

-- 1. Bootloader Cache Hydration
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end

    local rows = MySQL.query.await("SELECT * FROM `nyx_services_chemical_labs`")
    if rows then
        for _, r in ipairs(rows) do
            local coords = parseCoordsJson(r.coords)
            Nyx.Services.ChemicalLabs[r.lab_id] = {
                lab_id = r.lab_id,
                lab_label = r.lab_label,
                substation_id = r.substation_id,
                coords = coords,
                heading = tonumber(r.heading) or 0.0,
                power_draw_kw = tonumber(r.power_draw_kw) or 15.0,
                sterility_level = tonumber(r.sterility_level) or 100.0,
                autoclave_status = r.autoclave_status or "idle",
                active_batch_recipe = r.active_batch_recipe,
                active_batch_citizen_id = r.active_batch_citizen_id,
                active_batch_start_time = tonumber(r.active_batch_start_time),
                active_batch_duration = tonumber(r.active_batch_duration) or 0,
                active_batch_quantity = tonumber(r.active_batch_quantity) or 1,
                total_batches_produced = tonumber(r.total_batches_produced) or 0
            }
        end
        print(string.format("^2[Nyx:Services]^7 Loaded %d chemical and pharmaceutical synthesis laboratories into memory.^7", #rows))
    end
end)

-- 2. Power Grid Substation Check Helper
function Nyx.Services.IsLabPowered(lab)
    if not lab then return false end

    -- Check if substation is alive in nyx_services powergrid
    if Nyx.Services.Substations and Nyx.Services.Substations[lab.substation_id] then
        local sub = Nyx.Services.Substations[lab.substation_id]
        if sub.status == "blackout" or sub.status == "offline" or (tonumber(sub.health) or 0) <= 0 then
            return false
        end
    elseif exports['nyx_services'] and exports['nyx_services'].GetSubstation then
        local sub = exports['nyx_services']:GetSubstation(lab.substation_id)
        if sub and (sub.status == "blackout" or sub.status == "offline" or (tonumber(sub.health) or 0) <= 0) then
            return false
        end
    end

    -- Direct coordinate power check fallback
    if exports['nyx_services'] and exports['nyx_services'].IsCoordsPowered and lab.coords then
        local powered = exports['nyx_services']:IsCoordsPowered(lab.coords)
        if not powered then return false end
    end

    return true
end

-- 3. Log Immutable Regulatory Audit Ledger
function Nyx.Services.LogChemlabAudit(labId, citizenId, action, recipeKey, inputs, outputs, sterilityBefore, sterilityAfter, notes)
    local auditUuid = generateUuid()
    local inputsJson = inputs and json.encode(inputs) or nil
    local outputsJson = outputs and json.encode(outputs) or nil

    MySQL.query([[
        INSERT INTO `nyx_services_chemlab_audits`
          (`audit_uuid`, `lab_id`, `citizen_id`, `action`, `recipe_key`, `inputs_consumed`, `outputs_generated`, `sterility_before`, `sterility_after`, `notes`)
        VALUES
          (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        auditUuid,
        labId,
        citizenId or "SYSTEM",
        action,
        recipeKey,
        inputsJson,
        outputsJson,
        tonumber(sterilityBefore) or 100.0,
        tonumber(sterilityAfter) or 100.0,
        notes
    })
end

-- 4. Background Active Batch & Sterilization Runner (Runs every 1000ms)
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()

        for labId, lab in pairs(Nyx.Services.ChemicalLabs) do
            local isPowered = Nyx.Services.IsLabPowered(lab)

            -- Ongoing Synthesis Batch Runner
            if lab.autoclave_status == Nyx.ChemicalLabs.Statuses.SYNTHESIZING then
                if not isPowered then
                    -- Electrical Grid Failure Interruption
                    lab.autoclave_status = Nyx.ChemicalLabs.Statuses.OFFLINE_POWER
                    local prevSterility = lab.sterility_level
                    lab.sterility_level = math.max(0.0, lab.sterility_level - 15.0) -- Rapid temperature drop contamination
                    Nyx.Services.LogChemlabAudit(labId, lab.active_batch_citizen_id, 'POWER_LOST', lab.active_batch_recipe, nil, nil, prevSterility, lab.sterility_level, "Synthesis interrupted by substation electrical blackout.")

                    MySQL.query("UPDATE `nyx_services_chemical_labs` SET `autoclave_status` = ?, `sterility_level` = ? WHERE `lab_id` = ?", {
                        lab.autoclave_status, lab.sterility_level, labId
                    })
                    TriggerClientEvent("nyx:services:client:chemlabStatusChanged", -1, labId, Nyx.ChemicalLabs.FormatLabDisplay(lab))
                else
                    local startTime = lab.active_batch_start_time or now
                    local duration = lab.active_batch_duration or 10

                    if now >= (startTime + duration) then
                        -- Batch Completed!
                        local recipe = Nyx.ChemicalLabs.GetRecipe(lab.active_batch_recipe)
                        local citizenId = lab.active_batch_citizen_id
                        local quantity = lab.active_batch_quantity or 1
                        local sterilityBefore = lab.sterility_level

                        if recipe and citizenId then
                            local yieldUnits, grade, meta = Nyx.ChemicalLabs.CalculateBatchYield(recipe, sterilityBefore, quantity)
                            local sterilityAfter = Nyx.ChemicalLabs.CalculateSterilityDegradation(sterilityBefore, recipe, quantity)
                            lab.sterility_level = sterilityAfter

                            -- Grant synthesized items to player character inventory if online
                            local targetInv = "char:" .. citizenId .. ":main"
                            local outputsMap = {}

                            for outItem, outQty in pairs(recipe.outputs) do
                                local totalOut = outQty * quantity
                                outputsMap[outItem] = totalOut
                                if exports['nyx_inventory'] and exports['nyx_inventory'].AddItem then
                                    exports['nyx_inventory']:AddItem(targetInv, outItem, totalOut, meta)
                                end
                            end

                            lab.total_batches_produced = (lab.total_batches_produced or 0) + quantity

                            if sterilityAfter < Nyx.ChemicalLabs.CriticalSterilityThreshold then
                                lab.autoclave_status = Nyx.ChemicalLabs.Statuses.CONTAMINATED
                                Nyx.Services.LogChemlabAudit(labId, citizenId, 'CONTAMINATION_OCCURRED', recipe.key, nil, outputsMap, sterilityBefore, sterilityAfter, "Critical bio-chemical contamination threshold reached.")
                            else
                                lab.autoclave_status = Nyx.ChemicalLabs.Statuses.IDLE
                            end

                            Nyx.Services.LogChemlabAudit(labId, citizenId, 'SYNTHESIS_COMPLETED', recipe.key, nil, outputsMap, sterilityBefore, sterilityAfter, string.format("Batch completed: %s (%s). Yield: %d units.", recipe.label, grade, yieldUnits))

                            -- Find player source to notify
                            local targetPlayer = exports['nyx_core']:GetPlayerByCitizenId(citizenId)
                            if targetPlayer and targetPlayer.source then
                                TriggerClientEvent("nyx:core:client:notify", targetPlayer.source, {
                                    type = "success",
                                    message = string.format("Gyógyszerszintézis sikeres: %s [%d db] elkészült!", recipe.label, yieldUnits)
                                })
                            end
                        else
                            lab.autoclave_status = Nyx.ChemicalLabs.Statuses.IDLE
                        end

                        lab.active_batch_recipe = nil
                        lab.active_batch_citizen_id = nil
                        lab.active_batch_start_time = nil
                        lab.active_batch_duration = 0
                        lab.active_batch_quantity = 1

                        MySQL.query([[
                            UPDATE `nyx_services_chemical_labs`
                            SET `autoclave_status` = ?, `sterility_level` = ?, `total_batches_produced` = ?,
                                `active_batch_recipe` = NULL, `active_batch_citizen_id` = NULL, `active_batch_start_time` = NULL,
                                `active_batch_duration` = 0, `active_batch_quantity` = 1
                            WHERE `lab_id` = ?
                        ]], { lab.autoclave_status, lab.sterility_level, lab.total_batches_produced, labId })

                        TriggerClientEvent("nyx:services:client:chemlabStatusChanged", -1, labId, Nyx.ChemicalLabs.FormatLabDisplay(lab))
                    end
                end

            -- Ongoing Autoclave Sterilization Cycle Runner
            elseif lab.autoclave_status == Nyx.ChemicalLabs.Statuses.STERILIZING then
                local startTime = lab.active_batch_start_time or now
                local duration = lab.active_batch_duration or Nyx.ChemicalLabs.DefaultSterilizationDuration

                if now >= (startTime + duration) then
                    local sterilityBefore = lab.sterility_level
                    lab.sterility_level = 100.00
                    lab.autoclave_status = Nyx.ChemicalLabs.Statuses.IDLE

                    local citizenId = lab.active_batch_citizen_id or "SYSTEM"
                    Nyx.Services.LogChemlabAudit(labId, citizenId, 'STERILIZATION_CYCLE', nil, nil, nil, sterilityBefore, 100.00, "High-pressure thermal autoclave sanitization cycle completed. Sterility restored to 100.0%.")

                    lab.active_batch_citizen_id = nil
                    lab.active_batch_start_time = nil
                    lab.active_batch_duration = 0

                    MySQL.query([[
                        UPDATE `nyx_services_chemical_labs`
                        SET `autoclave_status` = 'idle', `sterility_level` = 100.00,
                            `active_batch_citizen_id` = NULL, `active_batch_start_time` = NULL, `active_batch_duration` = 0
                        WHERE `lab_id` = ?
                    ]], { labId })

                    TriggerClientEvent("nyx:services:client:chemlabStatusChanged", -1, labId, Nyx.ChemicalLabs.FormatLabDisplay(lab))

                    local targetPlayer = exports['nyx_core']:GetPlayerByCitizenId(citizenId)
                    if targetPlayer and targetPlayer.source then
                        TriggerClientEvent("nyx:core:client:notify", targetPlayer.source, {
                            type = "success",
                            message = "A laboratóriumi autokláv sterilizálása sikeresen befejeződött (100.0% sterilitás)!"
                        })
                    end
                end

            -- Re-evaluate power restoration if lab was offline
            elseif lab.autoclave_status == Nyx.ChemicalLabs.Statuses.OFFLINE_POWER and isPowered then
                lab.autoclave_status = (lab.sterility_level < Nyx.ChemicalLabs.CriticalSterilityThreshold) and Nyx.ChemicalLabs.Statuses.CONTAMINATED or Nyx.ChemicalLabs.Statuses.IDLE
                MySQL.query("UPDATE `nyx_services_chemical_labs` SET `autoclave_status` = ? WHERE `lab_id` = ?", { lab.autoclave_status, labId })
                TriggerClientEvent("nyx:services:client:chemlabStatusChanged", -1, labId, Nyx.ChemicalLabs.FormatLabDisplay(lab))
            end
        end
    end
end)

-- 5. Start Chemical Synthesis RPC Handler
function Nyx.Services.StartChemicalSynthesis(source, labId, recipeKey, quantity)
    local player = exports['nyx_core']:GetPlayer(source)
    if not player or not player.citizenId then
        return false, "UNAUTHORIZED", "Érvénytelen azonosítás."
    end

    local lab = Nyx.Services.ChemicalLabs[labId]
    if not lab then
        return false, "LAB_NOT_FOUND", "A megadott laboratóriumi munkaállomás nem létezik."
    end

    -- Zero-trust distance verification
    local ped = GetPlayerPed(source)
    local pedCoords = GetEntityCoords(ped)
    if not Nyx.ChemicalLabs.IsPointNearLab(pedCoords, lab.coords, Nyx.ChemicalLabs.MaxInteractionDistance + 1.5) then
        return false, "TOO_FAR", "Túl messze vagy a laboratóriumi munkaállomástól."
    end

    local isPowered = Nyx.Services.IsLabPowered(lab)
    quantity = math.max(1, math.min(10, tonumber(quantity) or 1))

    -- Query player inventory items
    local invId = "char:" .. player.citizenId .. ":main"
    local playerItemCounts = {}
    local recipe = Nyx.ChemicalLabs.GetRecipe(recipeKey)
    if not recipe then
        return false, "INVALID_RECIPE", "Ismeretlen gyógyszerészeti recept."
    end

    for reqItem, _ in pairs(recipe.inputs) do
        if exports['nyx_inventory'] and exports['nyx_inventory'].GetItemCount then
            playerItemCounts[reqItem] = exports['nyx_inventory']:GetItemCount(invId, reqItem) or 0
        else
            playerItemCounts[reqItem] = 0
        end
    end

    local ok, reasonCode, details = Nyx.ChemicalLabs.EvaluateRecipeEligibility(lab, recipeKey, isPowered, playerItemCounts, quantity)
    if not ok then
        return false, reasonCode, details.message or "A szintézis nem indítható el."
    end

    -- Debit required input items from player inventory
    for itemId, neededQty in pairs(details.requiredInputs) do
        local removed = exports['nyx_inventory']:RemoveItem(invId, itemId, neededQty)
        if not removed then
            return false, "ITEM_DEBIT_FAILED", "Hiba történt a kiindulási anyagok levonásakor."
        end
    end

    -- Set active synthesis batch
    lab.autoclave_status = Nyx.ChemicalLabs.Statuses.SYNTHESIZING
    lab.active_batch_recipe = recipeKey
    lab.active_batch_citizen_id = player.citizenId
    lab.active_batch_start_time = os.time()
    lab.active_batch_duration = details.durationSeconds
    lab.active_batch_quantity = quantity

    MySQL.query([[
        UPDATE `nyx_services_chemical_labs`
        SET `autoclave_status` = 'synthesizing', `active_batch_recipe` = ?, `active_batch_citizen_id` = ?,
            `active_batch_start_time` = ?, `active_batch_duration` = ?, `active_batch_quantity` = ?
        WHERE `lab_id` = ?
    ]], { recipeKey, player.citizenId, lab.active_batch_start_time, lab.active_batch_duration, quantity, labId })

    Nyx.Services.LogChemlabAudit(labId, player.citizenId, 'SYNTHESIS_STARTED', recipeKey, details.requiredInputs, nil, lab.sterility_level, lab.sterility_level, string.format("Synthesis batch started: %s (x%d). Duration: %ds.", recipe.label, quantity, details.durationSeconds))

    TriggerClientEvent("nyx:services:client:chemlabStatusChanged", -1, labId, Nyx.ChemicalLabs.FormatLabDisplay(lab))

    return true, "SYNTHESIS_STARTED", {
        labId = labId,
        recipeLabel = recipe.label,
        quantity = quantity,
        durationSeconds = details.durationSeconds
    }
end

-- 6. Start Autoclave Sterilization Cycle RPC Handler
function Nyx.Services.StartLabSterilization(source, labId)
    local player = exports['nyx_core']:GetPlayer(source)
    if not player or not player.citizenId then
        return false, "UNAUTHORIZED", "Érvénytelen azonosítás."
    end

    local lab = Nyx.Services.ChemicalLabs[labId]
    if not lab then
        return false, "LAB_NOT_FOUND", "A laboratóriumi munkaállomás nem található."
    end

    local ped = GetPlayerPed(source)
    local pedCoords = GetEntityCoords(ped)
    if not Nyx.ChemicalLabs.IsPointNearLab(pedCoords, lab.coords, Nyx.ChemicalLabs.MaxInteractionDistance + 1.5) then
        return false, "TOO_FAR", "Túl messze vagy a laboratóriumtól."
    end

    local invId = "char:" .. player.citizenId .. ":main"
    local playerItemCounts = {
        ['item_disinfectant'] = exports['nyx_inventory'] and exports['nyx_inventory']:GetItemCount(invId, 'item_disinfectant') or 0,
        ['bleach'] = exports['nyx_inventory'] and exports['nyx_inventory']:GetItemCount(invId, 'bleach') or 0
    }

    local ok, reasonCode, itemToConsume, _ = Nyx.ChemicalLabs.EvaluateSterilizationCycle(lab, playerItemCounts)
    if not ok then
        if reasonCode == "ALREADY_STERILE" then
            return false, reasonCode, "A laboratórium jelenleg maximális (100%) sterilitási szinten áll."
        elseif reasonCode == "MISSING_DISINFECTANT" then
            return false, reasonCode, "Nincs nálad Klinikai Fertőtlenítőszer (item_disinfectant) vagy Ipari Fehérítő (bleach)!"
        else
            return false, reasonCode, "Az autokláv jelenleg nem sterilizálható."
        end
    end

    local removed = exports['nyx_inventory']:RemoveItem(invId, itemToConsume, 1)
    if not removed then
        return false, "DEBIT_FAILED", "Hiba történt a fertőtlenítőszer levonásakor."
    end

    lab.autoclave_status = Nyx.ChemicalLabs.Statuses.STERILIZING
    lab.active_batch_citizen_id = player.citizenId
    lab.active_batch_start_time = os.time()
    lab.active_batch_duration = Nyx.ChemicalLabs.DefaultSterilizationDuration

    MySQL.query([[
        UPDATE `nyx_services_chemical_labs`
        SET `autoclave_status` = 'sterilizing', `active_batch_citizen_id` = ?,
            `active_batch_start_time` = ?, `active_batch_duration` = ?
        WHERE `lab_id` = ?
    ]], { player.citizenId, lab.active_batch_start_time, lab.active_batch_duration, labId })

    Nyx.Services.LogChemlabAudit(labId, player.citizenId, 'STERILIZATION_CYCLE', nil, { [itemToConsume] = 1 }, nil, lab.sterility_level, lab.sterility_level, "Sterilization cycle initiated with " .. itemToConsume)

    TriggerClientEvent("nyx:services:client:chemlabStatusChanged", -1, labId, Nyx.ChemicalLabs.FormatLabDisplay(lab))

    return true, "STERILIZATION_STARTED", {
        labId = labId,
        consumedItem = itemToConsume,
        durationSeconds = Nyx.ChemicalLabs.DefaultSterilizationDuration
    }
end

-- 7. Register RPC Bus Endpoints
CreateThread(function()
    while exports['nyx_core'] == nil or exports['nyx_core'].RegisterRPC == nil do
        Wait(50)
    end

    -- Return all chemical labs summary
    exports['nyx_core']:RegisterRPC("services:getChemicalLabs", function(source)
        local list = {}
        for _, lab in pairs(Nyx.Services.ChemicalLabs) do
            table.insert(list, Nyx.ChemicalLabs.FormatLabDisplay(lab))
        end
        return { success = true, labs = list }
    end)

    -- Return specific lab details with available recipes
    exports['nyx_core']:RegisterRPC("services:getChemicalLabDetails", function(source, labId)
        local lab = Nyx.Services.ChemicalLabs[labId]
        if not lab then
            return { success = false, message = "Laboratórium nem található." }
        end

        local isPowered = Nyx.Services.IsLabPowered(lab)
        local recipes = Nyx.ChemicalLabs.GetAllRecipes()

        return {
            success = true,
            lab = Nyx.ChemicalLabs.FormatLabDisplay(lab),
            coords = { x = lab.coords.x, y = lab.coords.y, z = lab.coords.z },
            isPowered = isPowered,
            recipes = recipes
        }
    end)

    -- Start synthesis
    exports['nyx_core']:RegisterRPC("services:startChemicalSynthesis", function(source, labId, recipeKey, quantity)
        local ok, code, data = Nyx.Services.StartChemicalSynthesis(source, labId, recipeKey, quantity)
        return { success = ok, code = code, data = data }
    end)

    -- Start sterilization
    exports['nyx_core']:RegisterRPC("services:startLabSterilization", function(source, labId)
        local ok, code, data = Nyx.Services.StartLabSterilization(source, labId)
        return { success = ok, code = code, data = data }
    end)
end)
