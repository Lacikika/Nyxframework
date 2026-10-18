--[[
    Nyxframework: nyx_judiciary
    File: shared/penal_labor.lua
    Description: Pure Lua 5.4 deterministic algorithms for Bolingbroke correctional labor,
                 workstation blueprints, sentence reductions, and civic treasury accounting.
]]

Nyx = Nyx or {}
Nyx.Judiciary = Nyx.Judiciary or {}
Nyx.PenalLabor = {}

-- 1. Workstations Registry
Nyx.PenalLabor.Workstations = {
    ['bolingbroke_metalwork'] = {
        id = 'bolingbroke_metalwork',
        label = 'Bolingbroke Sheet Metal & Stamping Press',
        category = 'metalwork',
        allowedRecipes = { ['license_plates'] = true, ['road_barriers'] = true },
        coords = vector3(1692.5, 2568.2, 45.5),
        radius = 2.5,
        animDict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
        anim = 'machinic_loop_mechandplayer'
    },
    ['bolingbroke_textile'] = {
        id = 'bolingbroke_textile',
        label = 'Bolingbroke Industrial Textile Loom',
        category = 'textile',
        allowedRecipes = { ['inmate_uniforms'] = true },
        coords = vector3(1696.8, 2568.2, 45.5),
        radius = 2.5,
        animDict = 'anim@amb@business@weed@weed_inspecting_high_dry@',
        anim = 'weed_inspecting_high_base_inspector'
    },
    ['bolingbroke_carpentry'] = {
        id = 'bolingbroke_carpentry',
        label = 'Bolingbroke Carpentry & Assembly Station',
        category = 'carpentry',
        allowedRecipes = { ['emergency_cots'] = true, ['wooden_pallets'] = true },
        coords = vector3(1700.5, 2568.2, 45.5),
        radius = 2.5,
        animDict = 'mini@repair',
        anim = 'fixing_a_ped'
    },
    ['bolingbroke_general'] = {
        id = 'bolingbroke_general',
        label = 'Bolingbroke Civic Packaging Station',
        category = 'packaging',
        allowedRecipes = {
            ['license_plates'] = true,
            ['road_barriers'] = true,
            ['inmate_uniforms'] = true,
            ['emergency_cots'] = true,
            ['wooden_pallets'] = true
        },
        coords = vector3(1704.2, 2568.2, 45.5),
        radius = 2.5,
        animDict = 'anim@heists@prison_heiststation@cop_reactions',
        anim = 'cop_b_idle'
    }
}

-- 2. Declarative Penal Labor Recipes
Nyx.PenalLabor.Recipes = {
    ['license_plates'] = {
        id = 'license_plates',
        key = 'license_plates',
        label = 'State License Plates (x2)',
        category = 'metalwork',
        workstationCategory = 'metalwork',
        inputs = {
            { item = 'refined_iron', amount = 1 }
        },
        outputs = {
            { item = 'civic_license_plate', amount = 2 }
        },
        sentenceReductionMonths = 2,
        civicFundsGenerated = 120.00,
        durationSeconds = 15,
        description = 'Stamp standard aluminum state vehicle registration plates.'
    },
    ['road_barriers'] = {
        id = 'road_barriers',
        key = 'road_barriers',
        label = 'Welded Road Barrier (x1)',
        category = 'metalwork',
        workstationCategory = 'metalwork',
        inputs = {
            { item = 'refined_iron', amount = 2 },
            { item = 'plastic_polymer', amount = 1 }
        },
        outputs = {
            { item = 'civic_road_barrier', amount = 1 }
        },
        sentenceReductionMonths = 3,
        civicFundsGenerated = 250.00,
        durationSeconds = 25,
        description = 'Weld and coat a high-visibility steel traffic barricade.'
    },
    ['inmate_uniforms'] = {
        id = 'inmate_uniforms',
        key = 'inmate_uniforms',
        label = 'Penal Workwear Jumpsuit (x1)',
        category = 'textile',
        workstationCategory = 'textile',
        inputs = {
            { item = 'raw_fabric', amount = 2 }
        },
        outputs = {
            { item = 'civic_inmate_uniform', amount = 1 }
        },
        sentenceReductionMonths = 1,
        civicFundsGenerated = 100.00,
        durationSeconds = 10,
        description = 'Stitch and hem standard-issue high-visibility inmate workwear.'
    },
    ['emergency_cots'] = {
        id = 'emergency_cots',
        key = 'emergency_cots',
        label = 'Emergency Field Cot (x1)',
        category = 'carpentry',
        workstationCategory = 'carpentry',
        inputs = {
            { item = 'refined_iron', amount = 1 },
            { item = 'raw_fabric', amount = 1 },
            { item = 'raw_timber', amount = 1 }
        },
        outputs = {
            { item = 'civic_emergency_cot', amount = 1 }
        },
        sentenceReductionMonths = 4,
        civicFundsGenerated = 350.00,
        durationSeconds = 30,
        description = 'Assemble a collapsible steel and canvas emergency relief bed.'
    },
    ['wooden_pallets'] = {
        id = 'wooden_pallets',
        key = 'wooden_pallets',
        label = 'Standard Freight Pallet (x1)',
        category = 'carpentry',
        workstationCategory = 'carpentry',
        inputs = {
            { item = 'raw_timber', amount = 2 },
            { item = 'refined_iron', amount = 1 }
        },
        outputs = {
            { item = 'civic_wooden_pallet', amount = 1 }
        },
        sentenceReductionMonths = 2,
        civicFundsGenerated = 180.00,
        durationSeconds = 20,
        description = 'Nail and reinforce heavy industrial lumber freight pallets.'
    }
}

--- Lookup recipe by key
--- @param recipeId string
--- @return table|nil
function Nyx.PenalLabor.GetRecipe(recipeId)
    if not recipeId or type(recipeId) ~= "string" then return nil end
    return Nyx.PenalLabor.Recipes[recipeId]
end

--- Get all registered recipes
--- @return table
function Nyx.PenalLabor.GetAllRecipes()
    return Nyx.PenalLabor.Recipes
end

--- Lookup workstation by key
--- @param workstationId string
--- @return table|nil
function Nyx.PenalLabor.GetWorkstation(workstationId)
    if not workstationId or type(workstationId) ~= "string" then return nil end
    return Nyx.PenalLabor.Workstations[workstationId]
end

--- Get all registered workstations
--- @return table
function Nyx.PenalLabor.GetAllWorkstations()
    return Nyx.PenalLabor.Workstations
end

--- Check if recipe can be crafted at given workstation
--- @param recipeId string
--- @param workstationId string
--- @return boolean
function Nyx.PenalLabor.IsRecipeAllowedAtWorkstation(recipeId, workstationId)
    local ws = Nyx.PenalLabor.GetWorkstation(workstationId)
    if not ws or not ws.allowedRecipes then return false end
    return ws.allowedRecipes[recipeId] == true
end

--- Pure sentence reduction math with floor clamping and release eligibility
--- @param currentSentenceMonths number
--- @param reductionMonths number
--- @return number newSentenceMonths, number actualReduction, boolean isEligibleForRelease
function Nyx.PenalLabor.CalculateSentenceReduction(currentSentenceMonths, reductionMonths)
    local cur = math.max(0, math.floor(tonumber(currentSentenceMonths) or 0))
    local red = math.max(0, math.floor(tonumber(reductionMonths) or 0))

    if cur == 0 then
        return 0, 0, false
    end

    local newSentence = math.max(0, cur - red)
    local actualRed = cur - newSentence
    local isEligible = (newSentence <= 0)

    return newSentence, actualRed, isEligible
end

--- Calculate civic funds generated for municipal treasury reserve
--- @param recipeId string
--- @param batchMultiplier number|nil
--- @return number civicFunds
function Nyx.PenalLabor.CalculateCivicValue(recipeId, batchMultiplier)
    local recipe = Nyx.PenalLabor.GetRecipe(recipeId)
    if not recipe then return 0.00 end

    local mult = math.max(1, math.floor(tonumber(batchMultiplier) or 1))
    local base = tonumber(recipe.civicFundsGenerated) or 0.00
    return math.floor((base * mult) * 100) / 100
end

--- Validate inmate eligibility to perform penal labor
--- @param penalRecord table|nil
--- @return boolean canWork, string|nil reason
function Nyx.PenalLabor.ValidateLaborEligibility(penalRecord)
    if not penalRecord or type(penalRecord) ~= "table" then
        return false, "NOT_INCARCERATED"
    end

    local status = penalRecord.status or "released"
    if status ~= "incarcerated" then
        return false, string.format("INMATE_STATUS_%s", string.upper(status))
    end

    local sentence = tonumber(penalRecord.current_sentence_months) or 0
    if sentence <= 0 then
        return false, "SENTENCE_EXPIRED"
    end

    return true, nil
end

--- Validate whether available inventory supplies satisfy the labor inputs
--- @param recipe table
--- @param availableItems table<string, number>
--- @param batchMultiplier number|nil
--- @return boolean success, string|nil missingItem, number|nil needed, number|nil have
function Nyx.PenalLabor.ValidateLaborInputs(recipe, availableItems, batchMultiplier)
    if not recipe or not recipe.inputs then
        return false, "INVALID_RECIPE", 0, 0
    end

    local mult = math.max(1, math.floor(tonumber(batchMultiplier) or 1))
    availableItems = availableItems or {}

    for _, req in ipairs(recipe.inputs) do
        local needed = req.amount * mult
        local have = tonumber(availableItems[req.item]) or 0
        if have < needed then
            return false, req.item, needed, have
        end
    end

    return true, nil, nil, nil
end

--- Calculate batch outputs with metadata
--- @param recipe table
--- @param batchMultiplier number|nil
--- @param citizenId string|nil
--- @param creationTimestamp number|nil
--- @return table outputs
function Nyx.PenalLabor.CalculateLaborOutputs(recipe, batchMultiplier, citizenId, creationTimestamp)
    local mult = math.max(1, math.floor(tonumber(batchMultiplier) or 1))
    local ts = creationTimestamp or os.time()
    local citId = citizenId or "INMATE-UNKNOWN"
    local results = {}

    if not recipe or not recipe.outputs then return results end

    for _, out in ipairs(recipe.outputs) do
        local meta = {
            producedBy = citId,
            facility = "bolingbroke_penitentiary",
            recipeId = recipe.id,
            createdAt = ts,
            durability = 100.0,
            quality = 1.00
        }

        if out.item == "civic_license_plate" then
            meta.plate = string.format("SA%04d", math.random(1000, 9999))
            meta.stampedAt = ts
        elseif out.item == "civic_inmate_uniform" then
            meta.inmateNumber = citId
        end

        results[#results + 1] = {
            item = out.item,
            amount = out.amount * mult,
            metadata = meta
        }
    end

    return results
end

--- Formats penal status badge for UI/telemetry
--- @param status string
--- @param currentSentenceMonths number
--- @return table badge
function Nyx.PenalLabor.FormatPenalStatusBadge(status, currentSentenceMonths)
    local s = string.lower(status or "unknown")
    local months = tonumber(currentSentenceMonths) or 0

    if s == "incarcerated" then
        if months <= 0 then
            return {
                label = "Szabadulásra Jogosult",
                code = "ELIGIBLE_RELEASE",
                css = "badge-success",
                color = "#10B981"
            }
        end
        return {
            label = string.format("Elítélt (%d hónap)", months),
            code = "INCARCERATED",
            css = "badge-danger",
            color = "#EF4444"
        }
    elseif s == "paroled" then
        return {
            label = "Feltételesen Szabadlábon",
            code = "PAROLED",
            css = "badge-warning",
            color = "#F59E0B"
        }
    elseif s == "released" then
        return {
            label = "Szabadlábon",
            code = "RELEASED",
            css = "badge-secondary",
            color = "#6B7280"
        }
    elseif s == "escaped" then
        return {
            label = "Szökött Fegyenc",
            code = "ESCAPED",
            css = "badge-danger",
            color = "#B91C1C"
        }
    end

    return {
        label = "Ismeretlen",
        code = "UNKNOWN",
        css = "badge-secondary",
        color = "#9CA3AF"
    }
end

--- Format standard USD currency
--- @param amount number
--- @return string
function Nyx.PenalLabor.FormatCurrency(amount)
    local num = tonumber(amount) or 0.0
    local formatted = string.format("%.2f", num)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return "$" .. formatted
end

--- Zero-trust payload validator for labor initiation
--- @param payload any
--- @return boolean isValid, string|nil errorCode, table|nil sanitized
function Nyx.PenalLabor.ValidateLaborPayload(payload)
    if type(payload) ~= "table" then
        return false, "INVALID_PAYLOAD", nil
    end

    local wsId = payload.workstationId
    if not wsId or type(wsId) ~= "string" or not Nyx.PenalLabor.GetWorkstation(wsId) then
        return false, "INVALID_WORKSTATION", nil
    end

    local recipeId = payload.recipeId
    if not recipeId or type(recipeId) ~= "string" or not Nyx.PenalLabor.GetRecipe(recipeId) then
        return false, "INVALID_RECIPE", nil
    end

    if not Nyx.PenalLabor.IsRecipeAllowedAtWorkstation(recipeId, wsId) then
        return false, "RECIPE_NOT_ALLOWED_AT_WORKSTATION", nil
    end

    local mult = tonumber(payload.batchMultiplier) or 1
    if mult < 1 or mult > 5 then
        return false, "INVALID_BATCH_MULTIPLIER", nil
    end

    return true, nil, {
        workstationId = wsId,
        recipeId = recipeId,
        batchMultiplier = math.floor(mult)
    }
end
