--[[
    Nyxframework: nyx_properties
    File: client/locks.lua
    Description: Door lock toggles, key mapping shortcuts, and state synchronizers.
]]

Nyx = Nyx or {}
Nyx.Properties = Nyx.Properties or {}

-- Toggle Lock Function
function Nyx.Properties.ToggleLock(propertyId)
    propertyId = propertyId or Nyx.Properties.CurrentPropertyId
    if not propertyId then return end
    if not exports['nyx_core'] or not exports['nyx_core'].TriggerRPCAwait then return end

    local res = exports['nyx_core']:TriggerRPCAwait("properties:toggleLock", propertyId)
    if res and res.success then
        TriggerEvent("nyx:ui:notify", {
            type = res.isLocked and "warning" or "success",
            title = "INGATLAN ZÁR",
            message = res.isLocked and "A bejárati ajtó be lett zárva." or "A bejárati ajtó ki lett nyitva."
        })
    else
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "HOZZÁFÉRÉS MEGTAGADVA",
            message = "Nincs jogosultságod vagy megfelelő szintű kulcsod a zár kezeléséhez!"
        })
    end
end

-- Server broadcast event for lock status update
RegisterNetEvent("nyx:properties:client:lockUpdated", function(propertyId, isLocked)
    if Nyx.Properties.CurrentPropertyId == propertyId then
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = "AJTÓ ÁLLAPOT",
            message = isLocked and "Az ajtó lezárásra került." or "Az ajtó fel lett oldva."
        })
    end
end)
