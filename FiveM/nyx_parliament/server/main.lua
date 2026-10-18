--[[
    Nyxframework: nyx_parliament
    File: server/main.lua
    Description: Parliament main lifecycle, lawbook queries, and server event bindings.
]]

Nyx = Nyx or {}
Nyx.Parliament = Nyx.Parliament or {}

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

-- RPC: Query Authoritative Law Book
Nyx.RPC.Register("parliament:getLawBook", function(src, categoryFilter)
    local results = {}
    for id, law in pairs(Nyx.Parliament.Laws) do
        if not categoryFilter or categoryFilter == "ALL" or law.category == categoryFilter then
            results[#results + 1] = {
                id = law.id,
                title = law.title,
                category = law.category,
                currentValue = law.currentValue,
                minAllowed = law.minAllowed,
                maxAllowed = law.maxAllowed,
                lastAmended = law.lastAmended
            }
        end
    end
    return results
end)

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    print("^2[Nyx:Parliament] Autonomous Civic Governance & Legislative Engine initialized.^7")
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    print("^3[Nyx:Parliament] Governance engine halted.^7")
end)
