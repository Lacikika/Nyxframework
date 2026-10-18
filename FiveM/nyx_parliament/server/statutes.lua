--[[
    Nyxframework: nyx_parliament
    File: server/statutes.lua
    Description: Authoritative legal matrix, statutory parameter boundaries,
                 replicated State Bag penal code sync, and bill formulation validator.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}
Nyx.Parliament.Laws = {} -- [lawId] = lawState

-- Standardized RPC Bridge to nyx_core
Nyx.RPC = Nyx.RPC or {
    Register = function(route, handler)
        exports['nyx_core']:RegisterRPC(route, handler)
    end,
    GenerateNonce = function()
        local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        return (string.gsub(template, '[xy]', function(c)
            local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format('%x', v)
        end))
    end
}

-- Synchronize laws from database into memory and replicated State Bags
function Nyx.Parliament.HydrateLaws()
    local rows = MySQL.query.await("SELECT * FROM `nyx_parliament_laws`")
    if not rows then return false end

    local function parseJson(raw)
        if type(raw) == "table" then return raw end
        if type(raw) == "string" and #raw > 0 then
            local ok, parsed = pcall(json.decode, raw)
            if ok and type(parsed) == "table" then return parsed end
        end
        return {}
    end

    local penalCatalog = {}
    local lawsCatalog = {}
    local speedLimits = {
        urban = 45.0,
        highway = 75.0,
        industrial = 35.0,
        school_residential = 25.0
    }
    local salesTaxCap = 0.12
    local zoningPolicies = {}

    for _, row in ipairs(rows) do
        local lawData = {
            id = row.law_id,
            title = row.title,
            description = row.description,
            category = row.category,
            subsystemTarget = row.subsystem_target or "general",
            currentValue = parseJson(row.current_value),
            minAllowed = parseJson(row.min_allowed),
            maxAllowed = parseJson(row.max_allowed),
            lastAmended = row.last_amended_by_session
        }

        Nyx.Parliament.Laws[row.law_id] = lawData
        lawsCatalog[#lawsCatalog + 1] = lawData

        -- Categorize into Penal Code catalog if penal infraction/misdemeanor/felony
        if row.category:sub(1, 6) == "penal_" then
            penalCatalog[#penalCatalog + 1] = {
                id = row.law_id,
                title = row.title,
                category = row.category,
                fine = tonumber(lawData.currentValue.fine) or 0,
                sentenceMonths = tonumber(lawData.currentValue.months) or 0,
                minFine = lawData.minAllowed and tonumber(lawData.minAllowed.fine) or 0,
                maxFine = lawData.maxAllowed and tonumber(lawData.maxAllowed.fine) or 0,
                minSentence = lawData.minAllowed and tonumber(lawData.minAllowed.months) or 0,
                maxSentence = lawData.maxAllowed and tonumber(lawData.maxAllowed.months) or 0,
                lastAmended = lawData.lastAmended
            }
        elseif row.law_id:sub(1, 6) == "speed:" then
            local zType = row.law_id:sub(7)
            local mph = tonumber(lawData.currentValue.mph)
            if mph then
                speedLimits[zType] = mph
            end
        elseif row.law_id == "tax:sales_cap" then
            salesTaxCap = tonumber(lawData.currentValue.rate) or salesTaxCap
        elseif row.category == "zoning" then
            zoningPolicies[row.law_id] = lawData.currentValue
        end
    end

    -- Replicate active statutes to GlobalState with 0.00ms client latency
    GlobalState.parliamentLaws = lawsCatalog
    GlobalState.penalCode = penalCatalog
    GlobalState.speedLimits = speedLimits
    GlobalState.salesTaxCap = salesTaxCap
    GlobalState.zoningPolicies = zoningPolicies

    print(string.format("^2[Nyx:Parliament] Hydrated %d statutory laws (%d penal offenses, %d speed limits, sales cap: %.1f%%) to GlobalState.^7",
        #rows, #penalCatalog, 4, salesTaxCap * 100.0))
    return true
end

-- Load authoritative laws on startup
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end
    Nyx.Parliament.HydrateLaws()
end)

-- Retrieve law state from memory
function Nyx.Parliament.GetLaw(lawId)
    return Nyx.Parliament.Laws[lawId]
end

-- Retrieve specific field value from law
function Nyx.Parliament.GetLawValue(lawId, field)
    local law = Nyx.Parliament.Laws[lawId]
    if not law or not law.currentValue then return nil end
    return law.currentValue[field]
end

-- Retrieve all active penal code offenses
function Nyx.Parliament.GetPenalCode()
    local penal = {}
    for id, law in pairs(Nyx.Parliament.Laws) do
        if law.category:sub(1, 6) == "penal_" then
            penal[#penal + 1] = {
                id = law.id,
                title = law.title,
                category = law.category,
                fine = tonumber(law.currentValue.fine) or 0,
                sentenceMonths = tonumber(law.currentValue.months) or 0,
                minFine = law.minAllowed and tonumber(law.minAllowed.fine) or 0,
                maxFine = law.maxAllowed and tonumber(law.maxAllowed.fine) or 0,
                minSentence = law.minAllowed and tonumber(law.minAllowed.months) or 0,
                maxSentence = law.maxAllowed and tonumber(law.maxAllowed.months) or 0,
                lastAmended = law.lastAmended
            }
        end
    end
    table.sort(penal, function(a, b) return a.id < b.id end)
    return penal
end

-- Retrieve active statutory speed limits
function Nyx.Parliament.GetSpeedLimits()
    if GlobalState.speedLimits then
        return GlobalState.speedLimits
    end
    local limits = {}
    for zType, defMph in pairs(Nyx.StatutoryEnforcement.DefaultSpeedLimits) do
        local law = Nyx.Parliament.Laws["speed:" .. zType]
        limits[zType] = (law and law.currentValue and tonumber(law.currentValue.mph)) or defMph
    end
    return limits
end

-- Retrieve active speed limit for specific zone
function Nyx.Parliament.GetSpeedLimit(zoneType)
    local z = string.lower(tostring(zoneType or "urban"))
    local limits = Nyx.Parliament.GetSpeedLimits()
    return limits[z] or limits['urban'] or 45.0
end

-- Retrieve constitutional sales tax cap
function Nyx.Parliament.GetSalesTaxCap()
    if GlobalState.salesTaxCap then
        return GlobalState.salesTaxCap
    end
    local law = Nyx.Parliament.Laws["tax:sales_cap"]
    return (law and law.currentValue and tonumber(law.currentValue.rate)) or 0.12
end

-- Evaluate vehicle speed against statutory zone speed limit
function Nyx.Parliament.EvaluateSpeeding(speedMph, zoneType)
    return Nyx.StatutoryEnforcement.EvaluateSpeeding(speedMph, zoneType, Nyx.Parliament.Laws)
end

-- Calculate sales tax respecting constitutional cap
function Nyx.Parliament.CalculateSalesTax(subtotal, proposedRate)
    return Nyx.StatutoryEnforcement.CalculateSalesTax(subtotal, proposedRate, Nyx.Parliament.Laws)
end

-- Validate structured bill modification actions against statutory constitutional bounds
function Nyx.Parliament.ValidateBillActions(actions)
    return Nyx.StatutoryEnforcement.ValidateStatutoryBillActions(actions, Nyx.Parliament.Laws)
end

-- RPC: Query Live Penal Code
Nyx.RPC.Register("parliament:getPenalCode", function(src)
    return Nyx.Parliament.GetPenalCode()
end)

-- RPC: Query Live Speed Limits
Nyx.RPC.Register("parliament:getSpeedLimits", function(src)
    return Nyx.Parliament.GetSpeedLimits()
end)

-- RPC: Query Comprehensive Statutory Bounds & Policy Limits
Nyx.RPC.Register("parliament:getStatutoryLimits", function(src)
    return {
        speedLimits = Nyx.Parliament.GetSpeedLimits(),
        salesTaxCap = Nyx.Parliament.GetSalesTaxCap(),
        penalCode = Nyx.Parliament.GetPenalCode(),
        tolerances = Nyx.StatutoryEnforcement.SpeedTolerances,
        violationTiers = Nyx.StatutoryEnforcement.ViolationTiers
    }
end)
