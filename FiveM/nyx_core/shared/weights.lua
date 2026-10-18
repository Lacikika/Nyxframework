--[[
    Nyxframework: nyx_core
    File: shared/weights.lua
    Description: Authoritative, forgiving tiered weight bracket calculations,
                 heavy freight threshold validations, and locomotion modifiers.
]]

Nyx = Nyx or {}
Nyx.Weights = Nyx.Weights or {}

-- Standard fallback tier structures (if Config not yet mounted)
local DefaultTiers = {
    tier_0 = {
        id = 0,
        minRatio = 0.0,
        maxRatio = 0.70,
        moveRate = 1.0,
        sprintAllowed = true,
        jumpAllowed = true,
        climbAllowed = true,
        staminaDrainMult = 1.0,
        label = "TIER_0"
    },
    tier_1 = {
        id = 1,
        minRatio = 0.70,
        maxRatio = 0.95,
        moveRate = 0.90,
        sprintAllowed = true,
        jumpAllowed = true,
        climbAllowed = true,
        staminaDrainMult = 1.30,
        label = "TIER_1"
    },
    tier_2 = {
        id = 2,
        minRatio = 0.95,
        maxRatio = math.huge,
        moveRate = 0.80,
        sprintAllowed = false,
        jumpAllowed = false,
        climbAllowed = false,
        staminaDrainMult = 2.00,
        label = "TIER_2"
    },
    tier_3 = {
        id = 3,
        isHeavyFreight = true,
        moveRate = 0.65,
        sprintAllowed = false,
        jumpAllowed = false,
        climbAllowed = false,
        staminaDrainMult = 2.50,
        label = "TIER_3"
    }
}

-- Backward-compatible aliases for legacy tier references
DefaultTiers.normal = DefaultTiers.tier_0
DefaultTiers.encumbered = DefaultTiers.tier_1
DefaultTiers.heavy = DefaultTiers.tier_1
DefaultTiers.overburdened = DefaultTiers.tier_2
DefaultTiers.critical = DefaultTiers.tier_2
DefaultTiers.heavy_freight = DefaultTiers.tier_3

-- Retrieve tier definition by key or ID
function Nyx.Weights.GetTier(tierKey)
    local cfgTiers = (Config and Config.WeightPenalties and Config.WeightPenalties.tiers) or DefaultTiers
    if type(tierKey) == "number" then
        tierKey = "tier_" .. tostring(tierKey)
    end
    return cfgTiers[tierKey] or DefaultTiers[tierKey] or DefaultTiers.tier_0
end

-- Check if total item weight exceeds heavy freight threshold (> 50kg)
function Nyx.Weights.IsHeavyFreight(weightGrams)
    local grams = tonumber(weightGrams) or 0
    local threshold = (Config and Config.WeightPenalties and Config.WeightPenalties.heavyFreightThresholdGrams) or 50000
    return grams > threshold
end

-- Calculate forgiving tiered weight bracket based on load ratio and heavy freight flag
function Nyx.Weights.CalculateTier(ratio, isHeavyFreight)
    local cfgTiers = (Config and Config.WeightPenalties and Config.WeightPenalties.tiers) or DefaultTiers
    local r = tonumber(ratio) or 0.0

    -- Tier 3: Heavy Industrial Payload (> 50kg)
    if isHeavyFreight then
        local t3 = cfgTiers.tier_3 or DefaultTiers.tier_3
        return "tier_3", t3
    end

    -- Tier 2: Overencumbered (96% - 100%+ capacity)
    local t2 = cfgTiers.tier_2 or DefaultTiers.tier_2
    local t2Threshold = (t2 and t2.minRatio) or 0.95
    if r > t2Threshold then
        return "tier_2", t2
    end

    -- Tier 1: Moderate Load (71% - 95% capacity)
    local t1 = cfgTiers.tier_1 or DefaultTiers.tier_1
    local t1Threshold = (t1 and t1.minRatio) or 0.70
    if r > t1Threshold then
        return "tier_1", t1
    end

    -- Tier 0: Normal Load (0% - 70% capacity)
    local t0 = cfgTiers.tier_0 or DefaultTiers.tier_0
    return "tier_0", t0
end

-- Global framework alias
Nyx.CalculateWeightTier = Nyx.Weights.CalculateTier
