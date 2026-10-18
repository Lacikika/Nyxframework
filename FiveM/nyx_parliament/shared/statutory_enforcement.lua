--[[
    Nyxframework: nyx_parliament & nyx_mdt & nyx_vehicles
    File: shared/statutory_enforcement.lua
    Description: Pure Lua 5.4 domain logic for dynamic speed limits, speeding violation tiers,
                 closed-loop sales tax caps, zoning policy adjustments, statutory bill validation,
                 and MDT real-time dispatch warning overlays.
]]

Nyx = Nyx or {}
Nyx.StatutoryEnforcement = {}

-- ----------------------------------------------------------------------------
-- 1. Precision Rounding & Utility Helpers
-- ----------------------------------------------------------------------------
local function round(val, decimals)
    local mult = 10 ^ (decimals or 2)
    return math.floor((val or 0.0) * mult + 0.5) / mult
end

local function clamp(val, minVal, maxVal)
    if minVal and val < minVal then return minVal end
    if maxVal and val > maxVal then return maxVal end
    return val
end

-- ----------------------------------------------------------------------------
-- 2. Statutory Speed Limits Taxonomy & Default Configurations
-- ----------------------------------------------------------------------------
Nyx.StatutoryEnforcement.DefaultSpeedLimits = {
    ['urban'] = 45.0,               -- City surface streets, downtown, Vinewood
    ['highway'] = 75.0,             -- Interstates, freeways (Del Perro, Olympic, Senora)
    ['industrial'] = 35.0,          -- Elysian Island, docks, Port of LS, industrial rail corridors
    ['school_residential'] = 25.0   -- Rockford Hills, Mirror Park, school zones, hospital perimeters
}

Nyx.StatutoryEnforcement.SpeedTolerances = {
    bufferMph = 5.0,                -- Grace margin before any infraction is recognized
    minorThresholdMph = 15.0,       -- 6 to 15 mph over limit = Tier 1 Minor Infraction
    majorThresholdMph = 30.0        -- 16 to 30 mph over limit = Tier 2 Major Misdemeanor
                                    -- 31+ mph over limit = Tier 3 Reckless Vehicular Endangerment
}

Nyx.StatutoryEnforcement.ViolationTiers = {
    [0] = {
        tier = 0,
        code = "TIER_0_COMPLIANT",
        label = "Szabályos Sebesség",
        severity = "none",
        chargeId = nil,
        baseFine = 0.0,
        jailMonths = 0,
        impoundRecommended = false,
        triggerDispatchWarning = false
    },
    [1] = {
        tier = 1,
        code = "TIER_1_MINOR",
        label = "Kisebb Sebességtúllépés (6-15 mph felett)",
        severity = "low",
        chargeId = "penal:speeding_minor",
        baseFine = 250.0,
        jailMonths = 0,
        impoundRecommended = false,
        triggerDispatchWarning = true
    },
    [2] = {
        tier = 2,
        code = "TIER_2_MAJOR",
        label = "Jelentős Sebességtúllépés (16-30 mph felett)",
        severity = "medium",
        chargeId = "penal:speeding_major",
        baseFine = 750.0,
        jailMonths = 5,
        impoundRecommended = false,
        triggerDispatchWarning = true
    },
    [3] = {
        tier = 3,
        code = "TIER_3_RECKLESS",
        label = "Gondatlan Veszélyeztetés (31+ mph felett)",
        severity = "critical",
        chargeId = "penal:reckless_driving",
        baseFine = 2500.0,
        jailMonths = 15,
        impoundRecommended = true,
        triggerDispatchWarning = true
    }
}

-- ----------------------------------------------------------------------------
-- 3. Resolve Active Statutory Speed Limit from Laws Catalog
-- ----------------------------------------------------------------------------
function Nyx.StatutoryEnforcement.ResolveSpeedLimit(zoneType, lawsCatalog)
    local z = string.lower(tostring(zoneType or "urban"))
    local defaultLimit = Nyx.StatutoryEnforcement.DefaultSpeedLimits[z] or Nyx.StatutoryEnforcement.DefaultSpeedLimits['urban']

    if not lawsCatalog or type(lawsCatalog) ~= "table" then
        return defaultLimit
    end

    local lawId = "speed:" .. z
    local law = lawsCatalog[lawId]
    if law then
        local cur = law.currentValue or law.current_value
        if type(cur) == "table" and cur.mph then
            return tonumber(cur.mph) or defaultLimit
        elseif type(cur) == "number" then
            return cur
        end
    end

    return defaultLimit
end

-- ----------------------------------------------------------------------------
-- 4. Evaluate Speeding Violation with Fine & Sentence Calibration
-- ----------------------------------------------------------------------------
function Nyx.StatutoryEnforcement.EvaluateSpeeding(vehicleSpeedMph, zoneType, lawsCatalog)
    local actualSpeed = math.max(0.0, round(tonumber(vehicleSpeedMph) or 0.0, 2))
    local zType = string.lower(tostring(zoneType or "urban"))
    local speedLimit = Nyx.StatutoryEnforcement.ResolveSpeedLimit(zType, lawsCatalog)
    local deltaMph = round(actualSpeed - speedLimit, 2)
    local tol = Nyx.StatutoryEnforcement.SpeedTolerances

    -- Compliant or within grace buffer
    if deltaMph <= tol.bufferMph then
        local tierDef = Nyx.StatutoryEnforcement.ViolationTiers[0]
        return {
            isViolation = false,
            tier = 0,
            tierCode = tierDef.code,
            tierLabel = tierDef.label,
            speedMph = actualSpeed,
            speedLimitMph = speedLimit,
            deltaMph = deltaMph,
            chargeId = nil,
            title = tierDef.label,
            recommendedFine = 0.0,
            sentenceMonths = 0,
            severity = "none",
            impoundRecommended = false,
            triggerDispatchWarning = false
        }
    end

    -- Determine Tier
    local tierIndex = 1
    if deltaMph > tol.majorThresholdMph then
        tierIndex = 3
    elseif deltaMph > tol.minorThresholdMph then
        tierIndex = 2
    else
        tierIndex = 1
    end

    local tierConfig = Nyx.StatutoryEnforcement.ViolationTiers[tierIndex]
    local chargeId = tierConfig.chargeId
    local baseFine = tierConfig.baseFine
    local sentenceMonths = tierConfig.jailMonths
    local minFine = 50.0
    local maxFine = 5000.0

    -- Extract bounds and override values if present in active statutory laws
    if lawsCatalog and lawsCatalog[chargeId] then
        local law = lawsCatalog[chargeId]
        local cur = law.currentValue or law.current_value
        local minAllowed = law.minAllowed or law.min_allowed
        local maxAllowed = law.maxAllowed or law.max_allowed

        if type(cur) == "table" then
            if cur.fine then baseFine = tonumber(cur.fine) or baseFine end
            if cur.months then sentenceMonths = tonumber(cur.months) or sentenceMonths end
        end
        if type(minAllowed) == "table" and minAllowed.fine then
            minFine = tonumber(minAllowed.fine) or minFine
        end
        if type(maxAllowed) == "table" and maxAllowed.fine then
            maxFine = tonumber(maxAllowed.fine) or maxFine
        end
    end

    -- Compute progressive fine scaling based on exact excess speed
    local scaledFine = baseFine
    if tierIndex == 1 then
        -- Scale linearly between buffer (5) and minorThreshold (15)
        local progress = (deltaMph - tol.bufferMph) / (tol.minorThresholdMph - tol.bufferMph)
        scaledFine = baseFine * (1.0 + (progress * 0.40))
    elseif tierIndex == 2 then
        -- Scale linearly between minorThreshold (15) and majorThreshold (30)
        local progress = (deltaMph - tol.minorThresholdMph) / (tol.majorThresholdMph - tol.minorThresholdMph)
        scaledFine = baseFine * (1.0 + (progress * 0.50))
    elseif tierIndex == 3 then
        -- Severe scaling for reckless speeds
        local excessAbove30 = deltaMph - tol.majorThresholdMph
        scaledFine = baseFine * (1.0 + math.min(2.0, (excessAbove30 / 20.0) * 0.80))
    end

    local finalFine = round(clamp(scaledFine, minFine, maxFine), 2)

    return {
        isViolation = true,
        tier = tierIndex,
        tierCode = tierConfig.code,
        tierLabel = tierConfig.label,
        speedMph = actualSpeed,
        speedLimitMph = speedLimit,
        deltaMph = deltaMph,
        chargeId = chargeId,
        title = tierConfig.label,
        recommendedFine = finalFine,
        sentenceMonths = sentenceMonths,
        severity = tierConfig.severity,
        impoundRecommended = tierConfig.impoundRecommended,
        triggerDispatchWarning = tierConfig.triggerDispatchWarning
    }
end

-- ----------------------------------------------------------------------------
-- 5. Sales Tax Cap & Exact Cent Closed-Loop Conservation
-- ----------------------------------------------------------------------------
function Nyx.StatutoryEnforcement.CalculateSalesTax(subtotal, proposedRate, lawsCatalog)
    local sub = math.max(0.0, round(tonumber(subtotal) or 0.0, 2))
    local propRate = math.max(0.0, tonumber(proposedRate) or 0.05)
    local capRate = 0.12 -- Default constitutional ceiling: 12.0%

    if lawsCatalog and lawsCatalog["tax:sales_cap"] then
        local law = lawsCatalog["tax:sales_cap"]
        local cur = law.currentValue or law.current_value
        if type(cur) == "table" and cur.rate then
            capRate = tonumber(cur.rate) or capRate
        elseif type(cur) == "number" then
            capRate = cur
        end
    end

    local wasCapped = (propRate > capRate)
    local effectiveRate = round(math.min(propRate, capRate), 4)
    local taxAmount = round(sub * effectiveRate, 2)
    local grossTotal = round(sub + taxAmount, 2)

    -- Assert closed-loop exact zero-cent conservation invariant
    local reconstructed = round(sub + taxAmount, 2)
    local delta = math.abs(grossTotal - reconstructed)

    return {
        subtotal = sub,
        proposedRate = propRate,
        statutoryCap = capRate,
        effectiveRate = effectiveRate,
        wasCapped = wasCapped,
        taxAmount = taxAmount,
        grossTotal = grossTotal,
        isConserved = (delta < 0.001)
    }
end

-- ----------------------------------------------------------------------------
-- 6. Zoning Policy Modifiers & Environmental Adjustments
-- ----------------------------------------------------------------------------
function Nyx.StatutoryEnforcement.EvaluateZoningPolicy(zoningType, baseTaxRate, lawsCatalog)
    local z = string.lower(tostring(zoningType or "commercial"))
    local baseRate = math.max(0.0, tonumber(baseTaxRate) or 0.05)
    local netRate = baseRate
    local adjustmentPct = 0.0
    local policyLabel = "Normál Adózási Övezet"

    if z == "commercial" or z == "retail_storefront" or z == "corporate_office" then
        local rebate = 0.02
        if lawsCatalog and lawsCatalog["zoning:commercial_tax_rebate"] then
            local law = lawsCatalog["zoning:commercial_tax_rebate"]
            local cur = law.currentValue or law.current_value
            if type(cur) == "table" and cur.rebate then
                rebate = tonumber(cur.rebate) or rebate
            end
        end
        adjustmentPct = -rebate
        netRate = math.max(0.0, round(baseRate - rebate, 4))
        policyLabel = string.format("Kereskedelmi Adókedvezmény Övezet (-%.1f%%)", rebate * 100.0)
    elseif z == "industrial" or z == "industrial_warehouse" then
        local surcharge = 0.03
        if lawsCatalog and lawsCatalog["zoning:industrial_environmental_surcharge"] then
            local law = lawsCatalog["zoning:industrial_environmental_surcharge"]
            local cur = law.currentValue or law.current_value
            if type(cur) == "table" and cur.surcharge then
                surcharge = tonumber(cur.surcharge) or surcharge
            end
        end
        adjustmentPct = surcharge
        netRate = round(baseRate + surcharge, 4)
        policyLabel = string.format("Ipari Környezetvédelmi Felár Övezet (+%.1f%%)", surcharge * 100.0)
    end

    return {
        zoningType = z,
        baseRate = baseRate,
        adjustmentPct = adjustmentPct,
        netRate = netRate,
        policyLabel = policyLabel
    }
end

-- ----------------------------------------------------------------------------
-- 7. Structured Bill Proposal Validator with Subsystem Guard Clauses
-- ----------------------------------------------------------------------------
function Nyx.StatutoryEnforcement.ValidateStatutoryBillActions(actions, lawsCatalog)
    if type(actions) ~= "table" or #actions == 0 then
        return false, "BILL_ACTIONS_EMPTY"
    end
    if #actions > 10 then
        return false, "TOO_MANY_ACTIONS"
    end

    local sanitized = {}
    for idx, act in ipairs(actions) do
        if type(act) ~= "table" then
            return false, string.format("MALFORMED_ACTION_%d", idx)
        end

        local targetId = act.targetLawId
        local field = act.field
        local newVal = tonumber(act.newValue)

        if not targetId or not field or newVal == nil then
            return false, string.format("MALFORMED_ACTION_AT_INDEX_%d", idx)
        end

        -- Subsystem specific domain sanity bounds
        if targetId:sub(1, 6) == "speed:" then
            if field ~= "mph" then
                return false, string.format("INVALID_SPEED_FIELD: '%s' (expected 'mph')", field)
            end
            if newVal < 15 or newVal > 120 then
                return false, string.format("SPEED_LIMIT_OUT_OF_BOUNDS: %s must be between 15 and 120 mph", newVal)
            end
        elseif targetId == "tax:sales_cap" then
            if field ~= "rate" then
                return false, string.format("INVALID_TAX_CAP_FIELD: '%s'", field)
            end
            if newVal < 0.01 or newVal > 0.50 then
                return false, string.format("SALES_TAX_CAP_OUT_OF_BOUNDS: %s must be between 0.01 and 0.50", newVal)
            end
        elseif targetId:sub(1, 6) == "penal:" then
            if field == "fine" and (newVal < 0 or newVal > 100000) then
                return false, string.format("FINE_OUT_OF_BOUNDS: %s must be between 0 and 100,000", newVal)
            elseif field == "months" and (newVal < 0 or newVal > 120) then
                return false, string.format("SENTENCE_OUT_OF_BOUNDS: %s must be between 0 and 120 months", newVal)
            end
        end

        -- Check against constitutional law boundary table if present
        if lawsCatalog and lawsCatalog[targetId] then
            local lawDef = lawsCatalog[targetId]
            local minAllowed = lawDef.minAllowed or lawDef.min_allowed
            local maxAllowed = lawDef.maxAllowed or lawDef.max_allowed

            local minVal = minAllowed and tonumber(minAllowed[field])
            local maxVal = maxAllowed and tonumber(maxAllowed[field])

            if minVal and newVal < minVal then
                return false, string.format("STATUTORY_MINIMUM_VIOLATION: %s.%s cannot be less than %s", targetId, field, minVal)
            end
            if maxVal and newVal > maxVal then
                return false, string.format("STATUTORY_MAXIMUM_VIOLATION: %s.%s cannot exceed %s", targetId, field, maxVal)
            end
        end

        sanitized[#sanitized + 1] = {
            targetLawId = targetId,
            field = field,
            newValue = newVal
        }
    end

    return true, sanitized
end

-- ----------------------------------------------------------------------------
-- 8. ANPR Radar Proximity & 3D Spatial Calculation
-- ----------------------------------------------------------------------------
function Nyx.StatutoryEnforcement.IsPointInRadarZone(pointCoords, zoneCoords, radius)
    if not pointCoords or not zoneCoords then return false, 0.0 end
    local px, py, pz = tonumber(pointCoords.x) or 0.0, tonumber(pointCoords.y) or 0.0, tonumber(pointCoords.z) or 0.0
    local zx, zy, zz = tonumber(zoneCoords.x) or 0.0, tonumber(zoneCoords.y) or 0.0, tonumber(zoneCoords.z) or 0.0
    local rad = tonumber(radius) or 120.0

    local dx = px - zx
    local dy = py - zy
    local dz = pz - zz
    local dist = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))

    return (dist <= rad), round(dist, 2)
end

-- ----------------------------------------------------------------------------
-- 9. Format MDT Dispatch Warning Overlay Presentation
-- ----------------------------------------------------------------------------
function Nyx.StatutoryEnforcement.FormatWarningOverlay(warning)
    if not warning or type(warning) ~= "table" then
        return {
            badgeClass = "badge-secondary",
            icon = "fa-solid fa-bell",
            header = "ÉRTESÍTÉS",
            severity = "low"
        }
    end

    local cat = warning.category or "speeding_anpr"
    local sev = warning.severity or "medium"

    local badgeMap = {
        ['low'] = { badgeClass = "badge-info", icon = "fa-solid fa-circle-info" },
        ['medium'] = { badgeClass = "badge-warning", icon = "fa-solid fa-triangle-exclamation" },
        ['high'] = { badgeClass = "badge-danger", icon = "fa-solid fa-car-burst" },
        ['critical'] = { badgeClass = "badge-danger", icon = "fa-solid fa-radiation" }
    }

    local b = badgeMap[sev] or badgeMap['medium']

    local title = warning.title or "MDT Figyelmeztető Riasztás"
    local sub = string.format("%s | %s", warning.location_label or "Ismeretlen Lokáció", warning.status or "active")

    return {
        badgeClass = b.badgeClass,
        icon = b.icon,
        header = title,
        subtitle = sub,
        severity = sev,
        category = cat
    }
end

-- ----------------------------------------------------------------------------
-- 10. UUID Generator for Warnings and Overrides
-- ----------------------------------------------------------------------------
function Nyx.StatutoryEnforcement.GenerateWarningUuid()
    local template = "wrn-xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format("%x", v)
    end))
end
