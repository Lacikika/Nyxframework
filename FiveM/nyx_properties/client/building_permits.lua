--[[
    Nyxframework: nyx_properties
    File: client/building_permits.lua
    Description: Client Spatial Interactions & NUI Bridge for Property Zoning & Building Permits.
]]

Nyx = Nyx or {}
Nyx.BuildingPermits = Nyx.BuildingPermits or {}

-- Municipal Planning & Zoning Office Coordinates (City Hall / Public Works)
local PLANNING_OFFICE_COORDS = vector3(-542.12, -208.55, 37.65)

-- Register Spatial Interactions via nyx_interact if present
CreateThread(function()
    if exports["nyx_interact"] and exports["nyx_interact"].AddInteractionPoint then
        exports["nyx_interact"]:AddInteractionPoint("zoning_planning_office", {
            coords = PLANNING_OFFICE_COORDS,
            radius = 2.5,
            label = "City Planning & Zoning Terminal",
            icon = "fa-solid fa-city",
            onInteract = function()
                Nyx.BuildingPermits.OpenPlanningOfficeUI()
            end
        })
    end
end)

function Nyx.BuildingPermits.OpenPlanningOfficeUI(propertyId)
    local targetProperty = propertyId or "prop_default_storefront"
    if exports["nyx_ui"] and exports["nyx_ui"].OpenView then
        exports["nyx_ui"]:OpenView("zoning_permits_portal", {
            propertyId = targetProperty,
            zoningRules = Nyx.BuildingPermits.ZoningRules,
            renovationTypes = Nyx.BuildingPermits.RenovationTypes
        })
    else
        TriggerEvent("chat:addMessage", {
            color = { 0, 200, 255 },
            multiline = true,
            args = { "ZONING", "City Planning & Building Permit Terminal Accessed." }
        })
    end
end

-- Response Net Listeners
RegisterNetEvent("nyx_properties:permitSubmittedResponse", function(success, message, permitData)
    if success then
        TriggerEvent("nyx_ui:notify", { type = "success", title = "Building Permit", message = message })
    else
        TriggerEvent("nyx_ui:notify", { type = "error", title = "Building Permit Rejected", message = message })
    end
end)

RegisterNetEvent("nyx_properties:permitInspectedResponse", function(success, message, permitData)
    if success then
        TriggerEvent("nyx_ui:notify", { type = "info", title = "Inspection Updated", message = message })
    else
        TriggerEvent("nyx_ui:notify", { type = "error", title = "Inspection Failed", message = message })
    end
end)

RegisterNetEvent("nyx_properties:renovationCompletedResponse", function(success, message, bonusData)
    if success then
        TriggerEvent("nyx_ui:notify", { type = "success", title = "Renovation Complete", message = message })
    else
        TriggerEvent("nyx_ui:notify", { type = "error", title = "Renovation Error", message = message })
    end
end)

-- Exports
exports("OpenBuildingPermitTerminal", function(propertyId)
    Nyx.BuildingPermits.OpenPlanningOfficeUI(propertyId)
end)
