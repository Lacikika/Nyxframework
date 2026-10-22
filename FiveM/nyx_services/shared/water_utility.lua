--[[
    Nyxframework: nyx_services
    File: shared/water_utility.lua
    Description: Pure, deterministic Lua calculations for municipal water utility systems,
                 reservoir contamination diffusion, pump station power dependencies,
                 and fire hydrant pressure dynamics.
]]

Nyx = Nyx or {}
Nyx.WaterUtility = Nyx.WaterUtility or {}

-- Constants
Nyx.WaterUtility.BASE_HYDRANT_PSI = 100.0 -- Nominal operating pressure at 100% reservoir & pumps online
Nyx.WaterUtility.MIN_HYDRANT_PSI = 10.0   -- Low gravity residual pressure when pumps are offline
Nyx.WaterUtility.MAX_HYDRANT_PSI = 120.0  -- Maximum pressure ceiling
Nyx.WaterUtility.DRAFTING_RATE_LPS = 15.0  -- Liters per second drafted by a fire tender

--- Calculates active fire hydrant PSI based on reservoir water ratio, pump station power status, and draft load.
--- @param waterLevelLiters number Current reservoir volume in liters
--- @param maxCapacityLiters number Maximum reservoir capacity in liters
--- @param pumpStatus string Status of linked pump station ('ONLINE', 'OFFLINE_POWER', 'FAULT')
--- @param activeDrafts number Number of active fire tenders drafting from this reservoir zone
--- @return number Hydrant PSI (0.0 to 120.0)
function Nyx.WaterUtility.CalculateHydrantPressure(waterLevelLiters, maxCapacityLiters, pumpStatus, activeDrafts)
    local volumeRatio = 0.0
    if maxCapacityLiters and maxCapacityLiters > 0 then
        volumeRatio = math.max(0.0, math.min(1.0, (waterLevelLiters or 0.0) / maxCapacityLiters))
    end

    local basePsi = Nyx.WaterUtility.BASE_HYDRANT_PSI * volumeRatio

    if pumpStatus == "OFFLINE_POWER" or pumpStatus == "FAULT" then
        basePsi = math.min(basePsi, Nyx.WaterUtility.MIN_HYDRANT_PSI)
    end

    activeDrafts = math.max(0, tonumber(activeDrafts) or 0)
    local loadPenalty = activeDrafts * 5.0 -- 5 PSI pressure drop per simultaneous drafting tender
    local finalPsi = math.max(0.0, basePsi - loadPenalty)

    return math.min(Nyx.WaterUtility.MAX_HYDRANT_PSI, math.floor(finalPsi * 100) / 100)
end

--- Calculates contamination diffusion into a reservoir when hazardous materials are introduced.
--- @param currentPpm number Current contamination parts-per-million in reservoir
--- @param currentLevelLiters number Current water volume in liters
--- @param contaminantGrams number Mass of contaminant introduced in grams
--- @return number newPpm, number newPurityPercentage
function Nyx.WaterUtility.CalculateContaminationDiffusion(currentPpm, currentLevelLiters, contaminantGrams)
    currentPpm = math.max(0.0, tonumber(currentPpm) or 0.0)
    currentLevelLiters = math.max(1.0, tonumber(currentLevelLiters) or 1.0)
    contaminantGrams = math.max(0.0, tonumber(contaminantGrams) or 0.0)

    -- 1 gram in 1,000 liters (1 m^3) = 1 PPM
    local addedPpm = (contaminantGrams / currentLevelLiters) * 1000.0
    local newPpm = currentPpm + addedPpm

    -- Purity drops logarithmically with PPM: 0 PPM = 100%, 100 PPM = 90%, 1,000 PPM = 0%
    local purity = math.max(0.0, math.min(100.0, 100.0 - (newPpm / 10.0)))

    return math.floor(newPpm * 100) / 100, math.floor(purity * 100) / 100
end

--- Calculates chemical purification dosage required to treat contaminated reservoir water.
--- @param currentPpm number Current contamination PPM
--- @param treatmentKg number Mass of purifying chemical added in kilograms
--- @param chemicalEfficiency number PPM neutralized per kg per 1,000,000 liters (default 50.0)
--- @param currentLevelLiters number Current water volume in liters
--- @return number newPpm, number newPurityPercentage
function Nyx.WaterUtility.CalculatePurificationTreatment(currentPpm, treatmentKg, chemicalEfficiency, currentLevelLiters)
    currentPpm = math.max(0.0, tonumber(currentPpm) or 0.0)
    treatmentKg = math.max(0.0, tonumber(treatmentKg) or 0.0)
    chemicalEfficiency = math.max(1.0, tonumber(chemicalEfficiency) or 50.0)
    currentLevelLiters = math.max(1.0, tonumber(currentLevelLiters) or 1.0)

    -- Neutralization formula normalized by water volume in millions of liters
    local millionLiters = currentLevelLiters / 1000000.0
    local ppmReduction = (treatmentKg * chemicalEfficiency) / millionLiters
    local newPpm = math.max(0.0, currentPpm - ppmReduction)

    local purity = math.max(0.0, math.min(100.0, 100.0 - (newPpm / 10.0)))

    return math.floor(newPpm * 100) / 100, math.floor(purity * 100) / 100
end

--- Calculates municipal water volume depletion based on property metered consumption and fire tender drafting.
--- @param currentLevelLiters number Current volume in reservoir
--- @param meteredConsumptionLiters number Volume consumed by residential/commercial grid meters
--- @param draftingDurationSeconds number Duration of active hydrant drafting in seconds
--- @param activeDraftTenders number Count of active drafting tenders
--- @return number newLevelLiters
function Nyx.WaterUtility.CalculateWaterConsumption(currentLevelLiters, meteredConsumptionLiters, draftingDurationSeconds, activeDraftTenders)
    currentLevelLiters = math.max(0.0, tonumber(currentLevelLiters) or 0.0)
    meteredConsumptionLiters = math.max(0.0, tonumber(meteredConsumptionLiters) or 0.0)
    draftingDurationSeconds = math.max(0.0, tonumber(draftingDurationSeconds) or 0.0)
    activeDraftTenders = math.max(0, tonumber(activeDraftTenders) or 0)

    local draftedVolume = draftingDurationSeconds * Nyx.WaterUtility.DRAFTING_RATE_LPS * activeDraftTenders
    local totalDepletion = meteredConsumptionLiters + draftedVolume

    local newLevel = math.max(0.0, currentLevelLiters - totalDepletion)
    return math.floor(newLevel * 100) / 100
end
