--[[
    Nyxframework: nyx_properties
    File: client/main.lua
    Description: Client property state tracking, interior routing transitions, and UI bridges.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}
Nyx.Properties.CurrentPropertyId = nil

-- Enter Property Handler
function Nyx.Properties.Enter(propertyId)
    if not exports['nyx_core'] or not exports['nyx_core'].TriggerRPCAwait then return end

    local res = exports['nyx_core']:TriggerRPCAwait("properties:enterProperty", propertyId)
    if res and res.success then
        Nyx.Properties.CurrentPropertyId = propertyId
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = "BELÉPÉS",
            message = "Beléptél az ingatlanba."
        })
    else
        local errMsg = "Nem sikerült belépni az ingatlanba."
        if res and res.error == "DOOR_LOCKED" then
            errMsg = "Az ajtó zárva van!"
        elseif res and res.error == "PROPERTY_SEIZED_TAX_DELINQUENCY" then
            errMsg = "Az ingatlant lefoglalta a hatóság súlyos adóhátralék miatt!"
        end

        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "BELÉPÉS SIKERTELEN",
            message = errMsg
        })
    end
end

-- Exit Property Handler
function Nyx.Properties.Exit(propertyId)
    propertyId = propertyId or Nyx.Properties.CurrentPropertyId
    if not propertyId then return end
    if not exports['nyx_core'] or not exports['nyx_core'].TriggerRPCAwait then return end

    local res = exports['nyx_core']:TriggerRPCAwait("properties:exitProperty", propertyId)
    if res and res.success then
        Nyx.Properties.CurrentPropertyId = nil
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = "KILÉPÉS",
            message = "Kiléptél az utcára."
        })
    end
end
