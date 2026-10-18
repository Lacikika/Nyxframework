--[[
    Nyxframework: nyx_logistics
    File: shared/refining.lua
    Description: Pure Lua 5.4 deterministic domain algorithms for industrial refining,
                 forestry timber transformation, metal foundry rolling, and functional parts manufacturing.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Refining = {}

-- Refining Facility Type Taxonomy
Nyx.Refining.FacilityTypes = {
    ['sawmill'] = {
        type = 'sawmill',
        label = 'Ipari Fafeldolgozó & Fűrészüzem (Timber Sawmill)',
        icon = 'tree',
        themeColor = '#8D6E63',
        description = 'Nagy teljesítményű fűrészüzem rönkök fűrészáruvá és cellulózzá történő feldolgozására.',
        defaultPowerKw = 15.0,
        supportedRecipes = { 'timber_sawmill_milling' }
    },
    ['foundry'] = {
        type = 'foundry',
        label = 'Nehézipari Öntöde & Hengerüzem (Metal Foundry)',
        icon = 'fire',
        themeColor = '#FF7043',
        description = 'Magas hőmérsékletű fémhengerlő és huzalextrúziós nehézipari üzem.',
        defaultPowerKw = 25.0,
        supportedRecipes = { 'structural_sheet_rolling', 'copper_wire_drawing', 'steel_freight_pallet' }
    },
    ['textile'] = {
        type = 'textile',
        label = 'Textilipari Fonoda & Szövőgyár (Textile Mill)',
        icon = 'tshirt',
        themeColor = '#42A5F5',
        description = 'Ipari pamutfésülő és szövetgyártó üzem egyenruhákhoz és orvosi kellékekhez.',
        defaultPowerKw = 12.0,
        supportedRecipes = { 'textile_cotton_carding' }
    },
    ['refinery'] = {
        type = 'refinery',
        label = 'Kőolajfinomító & Malomüzem (Industrial Refinery)',
        icon = 'oil-can',
        themeColor = '#78909C',
        description = 'Kőolaj polimerekké és generátor-üzemanyaggá alakítása, valamint gabonaőrlés.',
        defaultPowerKw = 20.0,
        supportedRecipes = { 'polymer_refining', 'industrial_fuel_refining', 'wheat_milling', 'corn_milling' }
    },
    ['assembly'] = {
        type = 'assembly',
        label = 'Precíziós Összeszerelő Üzem (Assembly Plant)',
        icon = 'cogs',
        themeColor = '#26A69A',
        description = 'Fogyasztási cikkek, lőszer, precíziós fegyveralkatrészek és elektronika gyártása.',
        defaultPowerKw = 18.0,
        supportedRecipes = { 'repair_kit', 'ammo_9mm_batch', 'machinery_parts_fabrication', 'bakery_bread', 'produce_pallet_packaging', 'electronics_assembly', 'precision_weapon_parts_machining', 'wire_cutters_assembly' }
    },
    ['chemical'] = {
        type = 'chemical',
        label = 'Vegyi- & Gyógyszerszintézis Üzem (Chemical Plant)',
        icon = 'flask',
        themeColor = '#AB47BC',
        description = 'Gyógyszeralapanyagok, áramköri szubsztrátok és fertőtlenítőszerek szintézise.',
        defaultPowerKw = 15.0,
        supportedRecipes = { 'first_aid_pack', 'saline_purification', 'synthetic_plasma_synthesis', 'disinfectant_compounding', 'circuit_board_fabrication' }
    },
    ['smelter'] = {
        type = 'smelter',
        label = 'Ipari Kohászati Smelter (Metallurgical Smelter)',
        icon = 'industry',
        themeColor = '#D4E157',
        description = 'Nagy teherbírású acél raklapöntés és nyersvasolvasztás.',
        defaultPowerKw = 35.0,
        supportedRecipes = { 'steel_freight_pallet' }
    },
    ['penal_workshop'] = {
        type = 'penal_workshop',
        label = 'Büntetés-végrehajtási Munkacsarnok (Penal Workshop)',
        icon = 'hammer',
        themeColor = '#FFA726',
        description = 'Közhasznú termékek előállítása elítéltek munkavégzésével.',
        defaultPowerKw = 8.0,
        supportedRecipes = { 'civic_license_plates', 'civic_road_barrier', 'civic_emergency_cot', 'civic_wooden_pallet' }
    }
}

-- Actions Taxonomy for Regulatory & Judicial Auditing
Nyx.Refining.Actions = {
    REFINING_STARTED = "REFINING_STARTED",
    REFINING_COMPLETED = "REFINING_COMPLETED",
    REFINING_HALTED_BLACKOUT = "REFINING_HALTED_BLACKOUT",
    REFINING_RESUMED = "REFINING_RESUMED",
    PALLET_DISPATCHED = "PALLET_DISPATCHED"
}

-- Heavy Freight threshold: 50kg or above triggers automatic palletization
Nyx.Refining.DefaultPalletThresholdGrams = 50000

--- Returns facility definition and capabilities by facility type
--- @param facilityType string
--- @return table|nil definition
function Nyx.Refining.GetFacilityDefinition(facilityType)
    if not facilityType then return nil end
    return Nyx.Refining.FacilityTypes[facilityType]
end

--- Validates if input items satisfy recipe requirements for a given batch count
--- @param recipe table
--- @param availableItems table<string, number>
--- @param batchCount number
--- @return boolean success, string|nil error, string|nil missingItem, number|nil needed, number|nil have
function Nyx.Refining.ValidateRefiningInputs(recipe, availableItems, batchCount)
    if not recipe or not recipe.inputs then
        return false, "INVALID_RECIPE", nil, nil, nil
    end

    local batches = math.max(1, math.min(50, tonumber(batchCount) or 1))
    availableItems = availableItems or {}

    for _, input in ipairs(recipe.inputs) do
        local requiredTotal = input.amount * batches
        local have = tonumber(availableItems[input.item]) or 0
        if have < requiredTotal then
            return false, "INSUFFICIENT_INPUTS", input.item, requiredTotal, have
        end
    end

    return true, nil, nil, nil, nil
end

--- Calculates duration in seconds, power draw in kW, and total energy in kWh for a batch
--- @param recipe table
--- @param batchCount number
--- @return number durationSeconds, number powerKw, number totalKwh
function Nyx.Refining.CalculateRefiningEnergyAndDuration(recipe, batchCount)
    if not recipe then return 0, 0, 0 end

    local batches = math.max(1, tonumber(batchCount) or 1)
    local baseTime = tonumber(recipe.processingTime) or 20
    local baseKw = tonumber(recipe.powerRequirementKw) or 15

    -- Multiple batches gain a slight industrial efficiency curve (10% reduction per additional batch up to 30%)
    local batchScale = 1.0 + ((batches - 1) * 0.85)
    local durationSeconds = math.max(1, math.floor(baseTime * batchScale))

    local powerKw = baseKw * (1.0 + ((batches - 1) * 0.20))
    local totalKwh = powerKw * (durationSeconds / 3600.0)
    totalKwh = math.floor(totalKwh * 10000) / 10000

    return durationSeconds, powerKw, totalKwh
end

--- Calculates refined batch outputs given an optional facility efficiency multiplier
--- @param recipe table
--- @param batchCount number
--- @param facilityEfficiency number|nil
--- @param isPowered boolean|nil
--- @return table outputs
function Nyx.Refining.CalculateRefiningYield(recipe, batchCount, facilityEfficiency, isPowered)
    if not recipe or not recipe.outputs then return {} end
    if isPowered == false then return {} end

    local batches = math.max(1, tonumber(batchCount) or 1)
    local eff = math.max(0.50, math.min(1.50, tonumber(facilityEfficiency) or 1.00))
    local ts = os.time()
    local results = {}

    for _, out in ipairs(recipe.outputs) do
        local baseAmount = out.amount * batches
        local finalAmount = math.max(1, math.floor(baseAmount * eff))

        local meta = {}
        if out.metadata then
            for k, v in pairs(out.metadata) do
                meta[k] = v
            end
        end
        meta.createdAt = ts
        meta.recipeKey = recipe.key
        meta.batchCount = batches
        meta.facilityEfficiency = eff

        results[#results + 1] = {
            item = out.item,
            amount = finalAmount,
            metadata = meta
        }
    end

    return results
end

--- Evaluates whether batch outputs should be automatically loaded onto a physical freight pallet
--- @param recipe table
--- @param batchCount number
--- @param outputMode string|nil
--- @param itemWeights table<string, number>|nil
--- @return boolean shouldPalletize, number totalWeightGrams
function Nyx.Refining.EvaluatePalletPackaging(recipe, batchCount, outputMode, itemWeights)
    if outputMode == "pallet" then
        return true, 0
    end

    if not recipe or not recipe.outputs then
        return false, 0
    end

    local batches = math.max(1, tonumber(batchCount) or 1)
    itemWeights = itemWeights or {}
    local totalWeight = 0

    for _, out in ipairs(recipe.outputs) do
        local unitW = tonumber(itemWeights[out.item]) or 1500 -- Fallback 1.5kg
        totalWeight = totalWeight + (out.amount * batches * unitW)
    end

    local shouldPallet = (totalWeight >= Nyx.Refining.DefaultPalletThresholdGrams)
    return shouldPallet, totalWeight
end

--- 3D Euclidean distance calculation between two spatial coordinates
--- @param point table|vector3
--- @param facilityCoords table|vector3
--- @param maxDist number
--- @return boolean isNear, number distance
function Nyx.Refining.IsPointNearFacility(point, facilityCoords, maxDist)
    if not point or not facilityCoords then return false, 999999.0 end

    local px = point.x or (point[1] or 0.0)
    local py = point.y or (point[2] or 0.0)
    local pz = point.z or (point[3] or 0.0)

    local fx = facilityCoords.x or (facilityCoords[1] or 0.0)
    local fy = facilityCoords.y or (facilityCoords[2] or 0.0)
    local fz = facilityCoords.z or (facilityCoords[3] or 0.0)

    local dx = px - fx
    local dy = py - fy
    local dz = pz - fz
    local dist = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))

    local maxD = math.max(0.1, tonumber(maxDist) or 3.5)
    return (dist <= maxD), dist
end

--- Formats facility state, connected substation power, and recipe telemetry for UI / presentation
--- @param facility table
--- @param activeRecipe table|nil
--- @param isPowered boolean
--- @param powerReason string|nil
--- @return table telemetry
function Nyx.Refining.FormatFacilityTelemetry(facility, activeRecipe, isPowered, powerReason)
    if not facility then
        return {
            status = "unknown",
            badgeClass = "badge-secondary",
            powerLabel = "Ismeretlen",
            energyFormatted = "0.00 kWh"
        }
    end

    local isActive = facility.is_active or false
    local powerStatus = isPowered and "online" or "offline"

    local badgeClass = "badge-secondary"
    local statusText = "Üzemen Kívül"

    if not isPowered then
        badgeClass = "badge-danger"
        statusText = string.format("Áramszünet (%s)", tostring(powerReason or "Hálózat Leállva"))
    elseif isActive then
        badgeClass = "badge-warning"
        statusText = string.format("Folyamatban (%s)", activeRecipe and activeRecipe.label or "Termelés")
    else
        badgeClass = "badge-success"
        statusText = "Készenlétben (Üzemkész)"
    end

    local energyKwh = tonumber(facility.total_energy_consumed_kwh) or 0.0
    local energyFormatted = string.format("%.2f kWh", energyKwh)

    local def = Nyx.Refining.GetFacilityDefinition(facility.type)

    return {
        id = facility.id,
        type = facility.type,
        typeLabel = def and def.label or facility.type,
        icon = def and def.icon or "industry",
        themeColor = def and def.themeColor or "#607D8B",
        status = statusText,
        badgeClass = badgeClass,
        isPowered = isPowered,
        powerLabel = isPowered and "Hálózat Aktív (230V/400V)" or "Nincs Hálózati Tápellátás",
        powerConsumptionKw = tonumber(facility.power_consumption_kw) or (def and def.defaultPowerKw or 15.0),
        energyFormatted = energyFormatted,
        totalEnergyConsumedKwh = energyKwh,
        progress = tonumber(facility.progress) or 0.0,
        outputMode = facility.output_mode or "inventory",
        activeRecipeKey = facility.active_recipe,
        activeRecipeLabel = activeRecipe and activeRecipe.label or nil
    }
end
