--[[
    Nyxframework: nyx_logistics
    File: client/zones.lua
    Description: Client-side localized zone telemetry, state bag synchronization,
                 and retail shelf interaction helpers.
]]

Nyx = Nyx or {}
Nyx.Logistics = Nyx.Logistics or {}
Nyx.Logistics.CurrentZone = "zone_ls_metro"

-- Background telemetry: Periodically resolve player delivery zone (2.5s interval)
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if DoesEntityExist(ped) then
            local coords = GetEntityCoords(ped)
            local resolvedZone = Nyx.Logistics.ResolveZoneFromCoords(coords, Nyx.Logistics.DefaultZones)

            if resolvedZone ~= Nyx.Logistics.CurrentZone then
                local prevZone = Nyx.Logistics.CurrentZone
                Nyx.Logistics.CurrentZone = resolvedZone
                LocalPlayer.state:set("deliveryZone", resolvedZone, true)

                TriggerEvent("nyx:logistics:client:zoneChanged", resolvedZone, prevZone)

                if Config.Debug then
                    print(string.format("^4[Nyx:Logistics] Entered delivery zone: %s^7", resolvedZone))
                end
            end
        end
        Wait(2500)
    end
end)

-- Public client helpers
function Nyx.Logistics.GetCurrentZone()
    return Nyx.Logistics.CurrentZone or "zone_ls_metro"
end
