--[[
    Nyxframework: nyx_vehicles
    File: shared/tolls_and_weighing.lua
    Description: Pure deterministic calculations for toll fees, Gross Vehicle Weight Ratings (GVWR),
                 overweight fines, commercial axle multipliers, and weigh station bypass thresholds.
]]

Nyx = Nyx or {}
Nyx.TollsAndWeighing = Nyx.TollsAndWeighing or {}

-- Round value cleanly to exact two decimal places (cents)
function Nyx.TollsAndWeighing.RoundToCent(amount)
    amount = tonumber(amount) or 0.0
    return math.floor(amount * 100.0 + 0.5) / 100.0
end

-- Default base curb weights by vehicle class (in kg)
-- Vehicle Classes: 0: Compacts, 1: Sedans, 2: SUVs, 3: Coupes, 4: Muscle, 5: Sports Classics,
-- 6: Sports, 7: Super, 8: Motorcycles, 9: Off-road, 10: Industrial, 11: Utility, 12: Vans, 20: Commercial
Nyx.TollsAndWeighing.BaseCurbWeights = {
    [0]  = 1200.0, -- Compacts
    [1]  = 1600.0, -- Sedans
    [2]  = 2200.0, -- SUVs
    [3]  = 1400.0, -- Coupes
    [4]  = 1700.0, -- Muscle
    [5]  = 1300.0, -- Sports Classics
    [6]  = 1500.0, -- Sports
    [7]  = 1450.0, -- Super
    [8]  = 250.0,  -- Motorcycles
    [9]  = 2400.0, -- Off-road
    [10] = 8000.0, -- Industrial
    [11] = 3500.0, -- Utility
    [12] = 2800.0, -- Vans
    [20] = 12000.0 -- Commercial (Semis, Heavy Haulers)
}

-- Standard Axle counts by class
Nyx.TollsAndWeighing.ClassAxleCounts = {
    [8]  = 2, -- Motorcycle
    [10] = 4, -- Industrial (Heavy)
    [20] = 5  -- Commercial 18-wheeler / Semi
}

-- Base Max Allowed Weights (in kg)
Nyx.TollsAndWeighing.MaxAllowedWeights = {
    [10] = 25000.0, -- Industrial
    [11] = 10000.0, -- Utility
    [12] = 8000.0,  -- Vans
    [20] = 40000.0, -- Commercial Heavy
    ["default"] = 15000.0
}

--- Pure calculation for highway toll fees
--- @param vehicleClass number GTA V vehicle class integer (0..22, 20=commercial)
--- @param baseFee number Base toll fee in dollars
--- @param commercialAxleMultiplier number Multiplier applied for commercial / multi-axle heavy vehicles
--- @param statutoryTaxRate number Dynamic statutory transit tax modifier (default 1.0)
--- @return number finalFee Total toll fee rounded to cent
function Nyx.TollsAndWeighing.CalculateTollFee(vehicleClass, baseFee, commercialAxleMultiplier, statutoryTaxRate)
    vehicleClass = tonumber(vehicleClass) or 0
    baseFee = tonumber(baseFee) or 5.00
    commercialAxleMultiplier = tonumber(commercialAxleMultiplier) or 1.50
    statutoryTaxRate = tonumber(statutoryTaxRate) or 1.00

    local isCommercial = (vehicleClass == 10 or vehicleClass == 20 or vehicleClass == 11)
    local axles = Nyx.TollsAndWeighing.ClassAxleCounts[vehicleClass] or 2

    local effectiveFee = baseFee
    if isCommercial then
        effectiveFee = baseFee * (1.0 + (axles - 2) * 0.25) * commercialAxleMultiplier
    end

    effectiveFee = effectiveFee * math.max(0.1, statutoryTaxRate)
    return Nyx.TollsAndWeighing.RoundToCent(effectiveFee)
end

--- Pure calculation for Gross Vehicle Weight Rating (GVWR)
--- @param vehicleClass number GTA vehicle class
--- @param trunkCargoKg number Trunk / Glovebox inventory weight in kg
--- @param loadedPalletsKg number Loaded physical pallet cargo weight in kg
--- @param customCurbWeight number Optional override for vehicle base curb weight in kg
--- @return number grossWeightKg Combined gross weight in kg
function Nyx.TollsAndWeighing.CalculateGVWR(vehicleClass, trunkCargoKg, loadedPalletsKg, customCurbWeight)
    vehicleClass = tonumber(vehicleClass) or 0
    trunkCargoKg = tonumber(trunkCargoKg) or 0.0
    loadedPalletsKg = tonumber(loadedPalletsKg) or 0.0

    local curb = tonumber(customCurbWeight)
    if not curb or curb <= 0 then
        curb = Nyx.TollsAndWeighing.BaseCurbWeights[vehicleClass] or 1800.0
    end

    local total = curb + math.max(0.0, trunkCargoKg) + math.max(0.0, loadedPalletsKg)
    return Nyx.TollsAndWeighing.RoundToCent(total)
end

--- Get max allowed gross weight limit for a vehicle class
--- @param vehicleClass number
--- @return number maxAllowedKg Max allowed weight in kg
function Nyx.TollsAndWeighing.GetMaxAllowedWeight(vehicleClass)
    vehicleClass = tonumber(vehicleClass) or 0
    return Nyx.TollsAndWeighing.MaxAllowedWeights[vehicleClass] or Nyx.TollsAndWeighing.MaxAllowedWeights["default"]
end

--- Calculate statutory overweight citation fine
--- @param grossWeightKg number Measured vehicle weight
--- @param maxAllowedKg number Statutory max weight limit
--- @param baseFinePerExcessKg number Fine per excess kg (default $2.50 / kg)
--- @return number fine Statutory fine rounded to cent
function Nyx.TollsAndWeighing.CalculateOverweightFine(grossWeightKg, maxAllowedKg, baseFinePerExcessKg)
    grossWeightKg = tonumber(grossWeightKg) or 0.0
    maxAllowedKg = tonumber(maxAllowedKg) or 15000.0
    baseFinePerExcessKg = tonumber(baseFinePerExcessKg) or 2.50

    local excessKg = grossWeightKg - maxAllowedKg
    if excessKg <= 0 then
        return 0.00
    end

    -- Mandatory base administrative fine $250.00 + excess weight charge
    local totalFine = 250.00 + (excessKg * baseFinePerExcessKg)
    return Nyx.TollsAndWeighing.RoundToCent(totalFine)
end

--- Determine weigh station inspection outcome status
--- @param grossWeightKg number Measured weight
--- @param maxAllowedKg number Max weight
--- @param hasValidManifest boolean Whether freight manifest is valid
--- @param isContrabandFlagged boolean Whether cargo contains illicit or unmanifested contraband
--- @param didBypass boolean Whether vehicle bypassed scale without halting
--- @return string status ('PASS', 'OVERWEIGHT', 'CONTRABAND_FLAG', 'BYPASSED')
function Nyx.TollsAndWeighing.DetermineInspectionStatus(grossWeightKg, maxAllowedKg, hasValidManifest, isContrabandFlagged, didBypass)
    if didBypass then
        return "BYPASSED"
    end
    if isContrabandFlagged or (not hasValidManifest and (grossWeightKg > 5000.0)) then
        return "CONTRABAND_FLAG"
    end
    if tonumber(grossWeightKg) > tonumber(maxAllowedKg) then
        return "OVERWEIGHT"
    end
    return "PASS"
end
