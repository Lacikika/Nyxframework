--[[
    Nyxframework: nyx_services
    File: shared/chemical_labs.lua
    Description: Pure Lua 5.4 domain engine for pharmaceutical synthesis, chemical laboratory
                 autoclaves, sterility degradation, and bio-chemical compounding recipes.
]]

Nyx = Nyx or {}
Nyx.ChemicalLabs = {}

-- Statutory Constants
Nyx.ChemicalLabs.MaxInteractionDistance = 3.5
Nyx.ChemicalLabs.DefaultSterilizationDuration = 15 -- seconds
Nyx.ChemicalLabs.CriticalSterilityThreshold = 40.0 -- Below this, autoclave is contaminated

-- Autoclave Operational Status States
Nyx.ChemicalLabs.Statuses = {
    IDLE = 'idle',
    SYNTHESIZING = 'synthesizing',
    STERILIZING = 'sterilizing',
    CONTAMINATED = 'contaminated',
    OFFLINE_POWER = 'offline_power'
}

-- Comprehensive Pharmaceutical & Bio-Chemical Synthesis Recipe Registry
Nyx.ChemicalLabs.Recipes = {
    ['saline_purification'] = {
        key = 'saline_purification',
        label = 'Isotonic Saline Solution Purification',
        inputs = {
            ['raw_saline_brine'] = 2,
            ['drink_water'] = 1
        },
        outputs = {
            ['saline_solution'] = 2
        },
        timeSeconds = 12,
        powerRequirementKw = 8.0,
        minSterility = 40.0,
        sterilityLoss = 3.0,
        description = 'Purifies concentrated mineral brine into 0.9% physiological saline IV solution.'
    },
    ['synthetic_plasma_synthesis'] = {
        key = 'synthetic_plasma_synthesis',
        label = 'Sterile Blood Plasma Bio-Synthesis',
        inputs = {
            ['organic_compounds'] = 2,
            ['saline_solution'] = 1,
            ['plastic_polymer'] = 1
        },
        outputs = {
            ['med_plasma'] = 1
        },
        timeSeconds = 25,
        powerRequirementKw = 18.0,
        minSterility = 70.0,
        sterilityLoss = 8.0,
        description = 'Complex synthesis of universal synthetic blood plasma for emergency ICU resuscitation.'
    },
    ['surgical_pack_autoclave'] = {
        key = 'surgical_pack_autoclave',
        label = 'Sterile Surgical Instrument Pack Autoclaving',
        inputs = {
            ['refined_iron'] = 2,
            ['item_disinfectant'] = 1,
            ['raw_fabric'] = 1
        },
        outputs = {
            ['med_surgical_pack'] = 1
        },
        timeSeconds = 20,
        powerRequirementKw = 15.0,
        minSterility = 60.0,
        sterilityLoss = 6.0,
        description = 'High-pressure steam autoclaving of surgical tools, scalpel blades, and suturing cotton.'
    },
    ['disinfectant_compounding'] = {
        key = 'disinfectant_compounding',
        label = 'Clinical Disinfectant Compounding',
        inputs = {
            ['chemical_precursors'] = 2,
            ['drink_water'] = 1
        },
        outputs = {
            ['item_disinfectant'] = 2
        },
        timeSeconds = 15,
        powerRequirementKw = 10.0,
        minSterility = 30.0,
        sterilityLoss = 4.0,
        description = 'Compounds chlorhexidine-based surface disinfectant for sanitizing hospital triage beds.'
    },
    ['hospital_linens_sanitization'] = {
        key = 'hospital_linens_sanitization',
        label = 'High-Temperature Hospital Linen Sanitization',
        inputs = {
            ['raw_fabric'] = 3,
            ['bleach'] = 1
        },
        outputs = {
            ['clean_linens'] = 2
        },
        timeSeconds = 18,
        powerRequirementKw = 12.0,
        minSterility = 50.0,
        sterilityLoss = 5.0,
        description = 'Industrial bleach and thermal treatment producing sterile clinical bed linen sets.'
    },
    ['sterile_pressure_bandage'] = {
        key = 'sterile_pressure_bandage',
        label = 'Sterile Pressure Bandage Packaging',
        inputs = {
            ['raw_fabric'] = 2,
            ['item_disinfectant'] = 1
        },
        outputs = {
            ['bandage_sterile'] = 3
        },
        timeSeconds = 14,
        powerRequirementKw = 6.0,
        minSterility = 50.0,
        sterilityLoss = 4.0,
        description = 'Sterilizes industrial cotton into compressed pressure bandages for trauma laceration care.'
    },
    ['tourniquet_assembly'] = {
        key = 'tourniquet_assembly',
        label = 'Combat Application Tourniquet Assembly',
        inputs = {
            ['plastic_polymer'] = 1,
            ['raw_fabric'] = 1,
            ['refined_iron'] = 1
        },
        outputs = {
            ['tourniquet'] = 2
        },
        timeSeconds = 16,
        powerRequirementKw = 8.0,
        minSterility = 40.0,
        sterilityLoss = 3.0,
        description = 'Precision assembly of windlass rod and occlusive nylon straps for arterial hemorrhage arrest.'
    },
    ['morphine_ampoule_synthesis'] = {
        key = 'morphine_ampoule_synthesis',
        label = 'Controlled Morphine Sulfate Bio-Extraction',
        inputs = {
            ['organic_compounds'] = 3,
            ['chemical_precursors'] = 1
        },
        outputs = {
            ['morphine_ampoule'] = 2
        },
        timeSeconds = 30,
        powerRequirementKw = 20.0,
        minSterility = 75.0,
        sterilityLoss = 10.0,
        description = 'Controlled extraction of pharmaceutical-grade morphine sulfate analgesic for acute shock.'
    }
}

-- 1. Get Recipe definition by key
function Nyx.ChemicalLabs.GetRecipe(recipeKey)
    if not recipeKey then return nil end
    return Nyx.ChemicalLabs.Recipes[recipeKey]
end

-- 2. Get All Recipes
function Nyx.ChemicalLabs.GetAllRecipes()
    return Nyx.ChemicalLabs.Recipes
end

-- 3. Evaluate Recipe Eligibility
--- Validates workstation state, regional power, sterility thresholds, and player inventory materials
--- @param lab table Chemical lab table from memory/database
--- @param recipeKey string Recipe identifier
--- @param isPowered boolean Whether regional substation is supplying electrical power
--- @param playerItemCounts table Map of [itemId] = quantity
--- @param batchQuantity integer Optional batch multiplier (default 1)
--- @return boolean isEligible, string reasonCode, table details
function Nyx.ChemicalLabs.EvaluateRecipeEligibility(lab, recipeKey, isPowered, playerItemCounts, batchQuantity)
    if not lab then
        return false, "LAB_NOT_FOUND", { message = "Laboratóriumi munkaállomás nem található." }
    end

    local status = lab.autoclave_status or Nyx.ChemicalLabs.Statuses.IDLE
    if status == Nyx.ChemicalLabs.Statuses.SYNTHESIZING then
        return false, "LAB_BUSY", { message = "Az autokláv jelenleg egy aktív szintézist futtat." }
    elseif status == Nyx.ChemicalLabs.Statuses.STERILIZING then
        return false, "LAB_STERILIZING", { message = "Az autokláv sterilizálási és fertőtlenítési ciklus alatt áll." }
    elseif status == Nyx.ChemicalLabs.Statuses.CONTAMINATED then
        return false, "LAB_CONTAMINATED", { message = "A laboratórium kontaminálódott! Sterilizálás szükséges a használat előtt." }
    elseif status == Nyx.ChemicalLabs.Statuses.OFFLINE_POWER then
        return false, "GRID_BLACKOUT", { message = "A regionális transzformátor alállomás áramkimaradás miatt leállt." }
    end

    if not isPowered then
        return false, "GRID_BLACKOUT", { message = "A körzeti elektromos hálózat lekapcsolt. Nincs áramellátás." }
    end

    local recipe = Nyx.ChemicalLabs.Recipes[recipeKey]
    if not recipe then
        return false, "INVALID_RECIPE", { message = "Ismeretlen gyógyszerészeti recept." }
    end

    batchQuantity = tonumber(batchQuantity) or 1
    if batchQuantity < 1 or math.floor(batchQuantity) ~= batchQuantity then
        return false, "INVALID_QUANTITY", { message = "Érvénytelen tételszám." }
    end

    local currentSterility = tonumber(lab.sterility_level) or 100.00
    if currentSterility < recipe.minSterility then
        return false, "STERILITY_TOO_LOW", {
            message = string.format("Elégtelen sterilitási szint: %.1f%% (Minimum elvárás: %.1f%%).", currentSterility, recipe.minSterility),
            currentSterility = currentSterility,
            minSterility = recipe.minSterility
        }
    end

    playerItemCounts = playerItemCounts or {}
    local missingItems = {}
    local requiredItems = {}

    for itemId, reqAmount in pairs(recipe.inputs) do
        local totalReq = reqAmount * batchQuantity
        requiredItems[itemId] = totalReq
        local playerAmount = tonumber(playerItemCounts[itemId]) or 0
        if playerAmount < totalReq then
            missingItems[itemId] = {
                required = totalReq,
                available = playerAmount,
                missing = totalReq - playerAmount
            }
        end
    end

    if next(missingItems) ~= nil then
        return false, "INSUFFICIENT_ITEMS", {
            message = "Hiányzó kiindulási vegyületek vagy steril anyagok.",
            missing = missingItems,
            required = requiredItems
        }
    end

    return true, "ELIGIBLE", {
        recipe = recipe,
        batchQuantity = batchQuantity,
        requiredInputs = requiredItems,
        durationSeconds = recipe.timeSeconds * batchQuantity,
        sterilityLoss = recipe.sterilityLoss * batchQuantity
    }
end

-- 4. Calculate Batch Output Yield & Purity Metadata
--- Models sterility degradation effects on product purity and yield
--- @param recipe table Recipe table
--- @param sterilityLevel number 0.00 to 100.00
--- @param batchQuantity integer
--- @return integer outputUnits, string qualityGrade, table metadata
function Nyx.ChemicalLabs.CalculateBatchYield(recipe, sterilityLevel, batchQuantity)
    batchQuantity = math.max(1, tonumber(batchQuantity) or 1)
    sterilityLevel = tonumber(sterilityLevel) or 100.00

    if sterilityLevel < recipe.minSterility then
        return 0, "CONTAMINATED_SPOILED", {
            isSpoiled = true,
            purity = 0.00,
            sterile = false,
            notes = "Batch spoiled due to severe bacterial/chemical contamination."
        }
    end

    local baseYield = 0
    for _, qty in pairs(recipe.outputs) do
        baseYield = baseYield + (qty * batchQuantity)
    end

    if sterilityLevel >= 90.00 then
        return baseYield, "PURITY_OPTIMAL", {
            isSpoiled = false,
            purity = 1.00,
            sterile = true,
            reagentGrade = "Analytical Reagent (AR) 99.8%",
            notes = "Sterile pharmaceutical batch under optimal aseptic conditions."
        }
    elseif sterilityLevel >= 70.00 then
        return baseYield, "PURITY_STANDARD", {
            isSpoiled = false,
            purity = 0.90,
            sterile = true,
            reagentGrade = "United States Pharmacopeia (USP) Grade",
            notes = "Standard clinical pharmaceutical grade."
        }
    else
        return baseYield, "PURITY_DEGRADED", {
            isSpoiled = false,
            purity = 0.75,
            sterile = false,
            reagentGrade = "Technical Reagent Grade",
            notes = "Low sterility during compounding. Partial degradation."
        }
    end
end

-- 5. Calculate Post-Batch Sterility Degradation
function Nyx.ChemicalLabs.CalculateSterilityDegradation(currentSterility, recipe, batchQuantity)
    currentSterility = tonumber(currentSterility) or 100.00
    batchQuantity = math.max(1, tonumber(batchQuantity) or 1)
    local loss = (recipe and recipe.sterilityLoss or 5.0) * batchQuantity
    return math.max(0.00, currentSterility - loss)
end

-- 6. Evaluate Sterilization Cycle Feasibility
--- Checks if a lab can undergo high-pressure autoclave sanitization with disinfectant or bleach
--- @param lab table
--- @param playerItemCounts table
--- @return boolean canSterilize, string reasonCode, string|nil itemToConsume, number restoredLevel
function Nyx.ChemicalLabs.EvaluateSterilizationCycle(lab, playerItemCounts)
    if not lab then
        return false, "LAB_NOT_FOUND", nil, 0.00
    end

    local status = lab.autoclave_status or Nyx.ChemicalLabs.Statuses.IDLE
    if status == Nyx.ChemicalLabs.Statuses.SYNTHESIZING then
        return false, "LAB_BUSY", nil, 0.00
    elseif status == Nyx.ChemicalLabs.Statuses.STERILIZING then
        return false, "ALREADY_STERILIZING", nil, 0.00
    end

    local currentSterility = tonumber(lab.sterility_level) or 100.00
    if currentSterility >= 99.00 and status == Nyx.ChemicalLabs.Statuses.IDLE then
        return false, "ALREADY_STERILE", nil, 100.00
    end

    playerItemCounts = playerItemCounts or {}
    local itemToConsume = nil

    if (tonumber(playerItemCounts['item_disinfectant']) or 0) >= 1 then
        itemToConsume = 'item_disinfectant'
    elseif (tonumber(playerItemCounts['bleach']) or 0) >= 1 then
        itemToConsume = 'bleach'
    end

    if not itemToConsume then
        return false, "MISSING_DISINFECTANT", nil, currentSterility
    end

    return true, "ELIGIBLE", itemToConsume, 100.00
end

-- 7. 3D Spatial Proximity Math
function Nyx.ChemicalLabs.IsPointNearLab(point, labCoords, maxDist)
    if not point or not labCoords then return false end
    maxDist = maxDist or Nyx.ChemicalLabs.MaxInteractionDistance

    local px = point.x or (point[1])
    local py = point.y or (point[2])
    local pz = point.z or (point[3])

    local lx = labCoords.x or (labCoords[1])
    local ly = labCoords.y or (labCoords[2])
    local lz = labCoords.z or (labCoords[3])

    if not px or not py or not pz or not lx or not ly or not lz then return false end

    local dx = px - lx
    local dy = py - ly
    local dz = pz - lz
    return (dx * dx + dy * dy + dz * dz) <= (maxDist * maxDist)
end

-- 8. Presentation Diagnostic & Formatting
function Nyx.ChemicalLabs.FormatLabDisplay(lab)
    if not lab then return { label = "Ismeretlen Labor", statusLabel = "OFFLINE", color = "#6B7280" } end

    local status = lab.autoclave_status or Nyx.ChemicalLabs.Statuses.IDLE
    local sterility = tonumber(lab.sterility_level) or 100.00

    local badgeMap = {
        ['idle'] = {
            label = "ÜZEMKÉSZ (IDLE)",
            color = "#10B981",
            class = "badge-success"
        },
        ['synthesizing'] = {
            label = "SZINTÉZIS FOLYAMATBAN",
            color = "#3B82F6",
            class = "badge-info"
        },
        ['sterilizing'] = {
            label = "STERILIZÁLÁSI CIKLUS",
            color = "#8B5CF6",
            class = "badge-purple"
        },
        ['contaminated'] = {
            label = "KONTAMINÁLT (FERTŐZÖTT)",
            color = "#EF4444",
            class = "badge-danger"
        },
        ['offline_power'] = {
            label = "ÁRAMKIMARADÁS (BLACKOUT)",
            color = "#F59E0B",
            class = "badge-warning"
        }
    }

    local badge = badgeMap[status] or badgeMap['idle']

    return {
        labId = lab.lab_id,
        labLabel = lab.lab_label or "Klinikai Laboratórium",
        substationId = lab.substation_id or "grid_city_01",
        sterilityLevel = sterility,
        status = status,
        statusLabel = badge.label,
        badgeColor = badge.color,
        badgeClass = badge.class,
        powerDrawKw = tonumber(lab.power_draw_kw) or 15.0,
        activeRecipe = lab.active_batch_recipe,
        totalBatches = tonumber(lab.total_batches_produced) or 0
    }
end
