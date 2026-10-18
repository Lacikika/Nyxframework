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

    for _, row in ipairs(rows) do
        local lawData = {
            id = row.law_id,
            title = row.title,
            category = row.category,
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
        end
    end

    -- Replicate active statutes to GlobalState with 0.00ms client latency
    GlobalState.parliamentLaws = lawsCatalog
    GlobalState.penalCode = penalCatalog

    print(string.format("^2[Nyx:Parliament] Hydrated %d statutory laws (%d penal code offenses) to GlobalState.^7",
        #rows, #penalCatalog))
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

-- Validate structured bill modification actions against statutory constitutional bounds
function Nyx.Parliament.ValidateBillActions(actions)
    if type(actions) ~= "table" or #actions == 0 then
        return false, "BILL_ACTIONS_EMPTY"
    end

    for idx, act in ipairs(actions) do
        if not act.targetLawId or not act.field or act.newValue == nil then
            return false, string.format("MALFORMED_ACTION_AT_INDEX_%d", idx)
        end

        local law = Nyx.Parliament.Laws[act.targetLawId]
        if not law then
            return false, string.format("LAW_NOT_FOUND: '%s'", act.targetLawId)
        end

        local newVal = tonumber(act.newValue)
        if not newVal then
            return false, string.format("INVALID_NUMERIC_VALUE_FOR_FIELD: '%s'", act.field)
        end

        local minVal = law.minAllowed and tonumber(law.minAllowed[act.field])
        local maxVal = law.maxAllowed and tonumber(law.maxAllowed[act.field])

        if minVal and newVal < minVal then
            return false, string.format("STATUTORY_MINIMUM_VIOLATION: %s.%s cannot be less than %s (proposed: %s)", act.targetLawId, act.field, minVal, newVal)
        end

        if maxVal and newVal > maxVal then
            return false, string.format("STATUTORY_MAXIMUM_VIOLATION: %s.%s cannot exceed %s (proposed: %s)", act.targetLawId, act.field, maxVal, newVal)
        end
    end

    return true
end

-- RPC: Query Live Penal Code
Nyx.RPC.Register("parliament:getPenalCode", function(src)
    return Nyx.Parliament.GetPenalCode()
end)
