--[[
    Nyxframework: nyx_vehicles
    File: shared/road_degradation.lua
    Description: Deterministic pure Lua formulas for highway pavement stress (4th-power law approximation),
                 road quality decay, vehicle handling/traction penalties on degraded roads,
                 and public works asphalt/resurfacing repair requirements.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}
Nyx.Vehicles.RoadDegradation = Nyx.Vehicles.RoadDegradation or {}

-- Pure deterministic rounding helper to 2 decimal places
local function roundToCent(val)
    val = tonumber(val) or 0.0
    return math.floor(val * 100.0 + 0.5) / 100.0
end

--- Calculates pavement stress / damage factor based on Fourth-Power Law approximation
--- @param grossWeightKg number Gross vehicle weight rating in KG
--- @param axleCount number Number of axles (default 2)
--- @return number Damage factor multiplier (relative to baseline 4,000 kg 2-axle passenger car = 1.0)
function Nyx.Vehicles.RoadDegradation.CalculateAxleDamageFactor(grossWeightKg, axleCount)
    grossWeightKg = math.max(100.0, tonumber(grossWeightKg) or 1500.0)
    axleCount = math.max(1, tonumber(axleCount) or 2)

    local weightPerAxle = grossWeightKg / axleCount
    local baselineAxleWeight = 2000.0 -- 2,000 kg per axle baseline (4,000 kg total for 2 axles)

    local ratio = weightPerAxle / baselineAxleWeight
    local factor = (ratio ^ 4.0) * (axleCount / 2.0)

    return roundToCent(factor)
end

--- Calculates current road segment quality percentage after heavy vehicle passages
--- @param heavyPassages number Total heavy axle passage count recorded
--- @param baselineQuality number Starting road quality percentage (0-100)
--- @param timeElapsedHours number Hours elapsed since last repair
--- @return number Degraded quality percentage (0.00 to 100.00)
function Nyx.Vehicles.RoadDegradation.CalculateRoadQualityDecay(heavyPassages, baselineQuality, timeElapsedHours)
    heavyPassages = math.max(0, tonumber(heavyPassages) or 0)
    baselineQuality = math.min(100.0, math.max(0.0, tonumber(baselineQuality) or 100.0))
    timeElapsedHours = math.max(0.0, tonumber(timeElapsedHours) or 0.0)

    -- Passage decay: 0.15% loss per heavy passage
    local passageLoss = heavyPassages * 0.15
    -- Environmental time decay: 0.05% loss per hour
    local timeLoss = timeElapsedHours * 0.05

    local remaining = baselineQuality - passageLoss - timeLoss
    remaining = math.min(100.0, math.max(0.0, remaining))

    return roundToCent(remaining)
end

--- Calculates handling / traction penalty factor for vehicles driving on a degraded road
--- @param roadQualityPct number Road quality percentage (0.00 to 100.00)
--- @return table Handling modifiers { gripMultiplier = number, suspensionWearMultiplier = number, status = string }
function Nyx.Vehicles.RoadDegradation.CalculateHandlingPenalty(roadQualityPct)
    roadQualityPct = math.min(100.0, math.max(0.0, tonumber(roadQualityPct) or 100.0))

    local gripMultiplier = 1.00
    local suspensionWearMultiplier = 1.00
    local status = "OPTIMAL"

    if roadQualityPct < 30.0 then
        status = "CRITICAL"
        gripMultiplier = 0.65
        suspensionWearMultiplier = 2.50
    elseif roadQualityPct < 60.0 then
        status = "DEGRADED"
        gripMultiplier = 0.80
        suspensionWearMultiplier = 1.75
    elseif roadQualityPct < 85.0 then
        status = "WEAR_WARNING"
        gripMultiplier = 0.92
        suspensionWearMultiplier = 1.25
    end

    return {
        gripMultiplier = roundToCent(gripMultiplier),
        suspensionWearMultiplier = roundToCent(suspensionWearMultiplier),
        status = status
    }
end

--- Calculates asphalt material & treasury payout required to restore a road segment to 100% quality
--- @param segmentLengthMeters number Segment length in meters
--- @param qualityLossPct number Quality loss percentage (e.g. 100 - quality_pct)
--- @return table { requiredAsphaltKg = number, treasuryPayout = number }
function Nyx.Vehicles.RoadDegradation.CalculateRepairCostAndMaterials(segmentLengthMeters, qualityLossPct)
    segmentLengthMeters = math.max(10.0, tonumber(segmentLengthMeters) or 1000.0)
    qualityLossPct = math.min(100.0, math.max(0.0, tonumber(qualityLossPct) or 0.0))

    -- 10 kg asphalt per meter for 100% loss
    local requiredAsphaltKg = (segmentLengthMeters * 10.0) * (qualityLossPct / 100.0)
    -- $2.50 treasury payout per kg asphalt laid
    local treasuryPayout = requiredAsphaltKg * 2.50

    return {
        requiredAsphaltKg = roundToCent(requiredAsphaltKg),
        treasuryPayout = roundToCent(treasuryPayout)
    }
end
