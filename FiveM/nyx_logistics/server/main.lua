--[[
    Nyxframework: nyx_logistics
    File: server/main.lua
    Description: Resource lifecycle, state integrity, and module initialization.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}

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

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    print("^2[Nyx:Logistics] Zero-Sum Supply Chain & Logistics Engine initialized.^7")
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    print("^3[Nyx:Logistics] Supply chain engine halted.^7")
end)
