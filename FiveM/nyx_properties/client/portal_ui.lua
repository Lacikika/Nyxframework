--[[
    Nyxframework: nyx_properties
    File: client/portal_ui.lua
    Description: Client-side dispatch and UI bridge for the Property Blind-Auction
                 & Stewardship Web Application. Routes player intent through nyx_ui
                 CEF single-frame overlay.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}

-- 1. Open Property Portal UI
function Nyx.Properties.OpenPortal(options)
    options = options or {}

    -- Fetch initial telemetry from server
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPCAwait then
        local overview = exports['nyx_core']:TriggerRPCAwait("properties:getRealEstatePortalOverview")
        if overview and overview.success then
            local payload = {
                activeTab = options.activeTab or "auctions",
                selectedPropertyId = options.propertyId,
                selectedAuctionId = options.auctionId,
                data = overview
            }

            if exports['nyx_ui'] and exports['nyx_ui'].OpenPropertyPortal then
                exports['nyx_ui']:OpenPropertyPortal(payload)
                return true
            elseif exports['nyx_ui'] and exports['nyx_ui'].OpenView then
                exports['nyx_ui']:OpenView("properties", payload)
                return true
            end
        end
    end

    -- Fallback alert if NUI bridge is unavailable
    TriggerEvent("nyx:ui:notify", {
        type = "error",
        title = "INGATLAN PORTÁL",
        message = "A portál felület jelenleg nem érhető el."
    })
    return false
end

-- 2. Close Property Portal UI
function Nyx.Properties.ClosePortal()
    if exports['nyx_ui'] and exports['nyx_ui'].ClosePropertyPortal then
        exports['nyx_ui']:ClosePropertyPortal()
    end
end

-- 3. Register Console & Chat Commands
RegisterCommand("realestate", function(_, args)
    local tab = args[1] or "auctions"
    Nyx.Properties.OpenPortal({ activeTab = tab })
end, false)

RegisterCommand("auctions", function()
    Nyx.Properties.OpenPortal({ activeTab = "auctions" })
end, false)

RegisterCommand("myproperties", function()
    Nyx.Properties.OpenPortal({ activeTab = "taxation" })
end, false)

RegisterCommand("stewardship", function()
    Nyx.Properties.OpenPortal({ activeTab = "stewardship" })
end, false)

-- 4. Client Exports
exports('OpenPortal', Nyx.Properties.OpenPortal)
exports('ClosePortal', Nyx.Properties.ClosePortal)
exports('OpenRealEstatePortal', Nyx.Properties.OpenPortal)
exports('OpenPropertyPortal', Nyx.Properties.OpenPortal)
