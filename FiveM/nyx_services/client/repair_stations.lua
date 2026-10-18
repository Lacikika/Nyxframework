--[[
    Nyxframework: nyx_services
    File: client/repair_stations.lua
    Description: Client-side municipal repair station interactions, Third-Eye (LALT) options,
                 and insolvency warnings.
]]

local repairStations = {
    { id = "repair_depot_ls", label = "Los Santos Municipal Public Works Repair Depot", coords = vector3(-338.4, -136.2, 39.0) },
    { id = "repair_sandy_shores", label = "Sandy Shores Municipal Auto Maintenance Bay", coords = vector3(1735.6, 3311.2, 41.2) },
    { id = "repair_paleto_bay", label = "Paleto Bay Public Service Maintenance Stall", coords = vector3(110.8, 6626.5, 31.8) }
}

-- Register Third-Eye (LALT) Targets
CreateThread(function()
    while not exports['nyx_interact'] do
        Wait(500)
    end

    for _, station in ipairs(repairStations) do
        exports['nyx_interact']:AddTargetCoords("repair_station_" .. station.id, station.coords, 3.5, {
            options = {
                {
                    icon = "fa-solid fa-wrench",
                    label = "Városi Járműszerviz (Municipal Vehicle Repair)",
                    event = "nyx:services:client:openRepairStation",
                    args = { stationId = station.id, stationLabel = station.label },
                    canInteract = function(entity, dist)
                        return dist <= 3.5
                    end
                }
            },
            distance = 3.5
        })
    end
end)

-- Find nearest vehicle to player
local function getNearbyVehicle(coords, radius)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 then return veh end

    local r = radius or 6.0
    local handle, current = FindFirstVehicle()
    local nearestVeh = nil
    local shortestDist = r

    if handle ~= -1 then
        repeat
            local vCoords = GetEntityCoords(current)
            local dist = #(coords - vCoords)
            if dist < shortestDist then
                shortestDist = dist
                nearestVeh = current
            end
            local success, nextVeh = FindNextVehicle(handle)
            current = nextVeh
        until not success
        EndFindVehicle(handle)
    end

    return nearestVeh
end

-- Open Repair Station Interaction
RegisterNetEvent("nyx:services:client:openRepairStation", function(data)
    local stationId = data and data.stationId or "repair_depot_ls"
    local stationLabel = data and data.stationLabel or "Városi Szerviz"

    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local targetVeh = getNearbyVehicle(pedCoords, 7.0)

    if not targetVeh or not DoesEntityExist(targetVeh) then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = stationLabel,
            message = "Nincs jármű a szervizállás közelében!"
        })
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(targetVeh)
    local okEst, est = exports['nyx_core']:TriggerRPC("services:getRepairEstimate", {
        stationId = stationId,
        vehicleNetId = netId
    })

    if not okEst or not est then
        TriggerEvent("nyx:ui:notify", {
            type = "info",
            title = stationLabel,
            message = tostring(est or "A jármű nem szorul javításra.")
        })
        return
    end

    local costData = est.cost
    local msg = string.format("Árajánlat: $%.2f (Munkadíj: $%.2f, Alkatrész: $%.2f, Városi pótdíj: $%.2f) | Pénzügyi állapot: %s",
        costData.totalCost, costData.laborFee, costData.partsFee, costData.surcharge, est.fiscalTier)

    TriggerEvent("chat:addMessage", {
        color = { 0, 220, 180 },
        multiline = true,
        args = { "SZERVIZ", msg }
    })

    if est.fiscalTier == "bankrupt" and not est.hasRepairKit then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "VÁROSI CSŐDÁLLAPOT",
            message = "A város fizetésképtelen. A javításhoz saját javítókészlet (tool_repairkit) szükséges!"
        })
        return
    end

    -- Trigger repair execution
    local okRep, repRes = exports['nyx_core']:TriggerRPC("services:repairAtStation", {
        stationId = stationId,
        vehicleNetId = netId
    })

    if not okRep or not repRes then
        TriggerEvent("nyx:ui:notify", {
            type = "error",
            title = "JAVÍTÁS MEGSZAKADT",
            message = tostring(repRes or "A fizetés vagy alkatrész-levonás meghiúsult.")
        })
        return
    end

    TriggerEvent("nyx:ui:notify", {
        type = "success",
        title = "JÁRMŰ MEGJAVÍTVA",
        message = string.format("Javítás kész! Levonva: $%.2f.%s",
            repRes.totalPaid, (repRes.usedRepairKit and " (1x Szerszámkészlet elhasználva)" or ""))
    })
end)

-- Command to initiate municipal repair
RegisterCommand("muni_repair", function()
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local nearestStation = nil
    local minDist = 15.0

    for _, s in ipairs(repairStations) do
        local dist = #(pedCoords - s.coords)
        if dist < minDist then
            minDist = dist
            nearestStation = s
        end
    end

    if not nearestStation then
        TriggerEvent("nyx:ui:notify", {
            type = "warning",
            title = "SZERVIZ",
            message = "Ön nincs városi szervizállás közelében!"
        })
        return
    end

    TriggerEvent("nyx:services:client:openRepairStation", {
        stationId = nearestStation.id,
        stationLabel = nearestStation.label
    })
end, false)
