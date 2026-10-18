--[[
    Nyxframework: nyx_parliament
    File: server/statutes.lua
    Description: Authoritative legal matrix, statutory parameter boundaries, and bill formulation validator.
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

-- Load authoritative laws into memory cache on boot
CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(50)
    end

    local rows = MySQL.query.await("SELECT * FROM `nyx_parliament_laws`")
    if rows then
        for _, row in ipairs(rows) do
            local function parseJson(raw)
                if type(raw) == "table" then return raw end
                if type(raw) == "string" and #raw > 0 then
                    local ok, parsed = pcall(json.decode, raw)
                    if ok and type(parsed) == "table" then return parsed end
                end
                return {}
            end

            Nyx.Parliament.Laws[row.law_id] = {
                id = row.law_id,
                title = row.title,
                category = row.category,
                currentValue = parseJson(row.current_value),
                minAllowed = parseJson(row.min_allowed),
                maxAllowed = parseJson(row.max_allowed),
                lastAmended = row.last_amended_by_session
            }
        end
        print(string.format("^2[Nyx:Parliament] Hydrated %d authoritative statutory laws and penal codes.^7", #rows))
    end
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
