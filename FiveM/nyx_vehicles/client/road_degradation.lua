--[[
    Nyxframework: nyx_vehicles
    File: client/road_degradation.lua
    Description: Client-side spatial sampling for highway segments, dynamic vehicle handling/traction
                 degradation when driving on degraded road segments, and NUI event dispatching.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}
Nyx.Vehicles.RoadDegradationClient = Nyx.Vehicles.RoadDegradationClient or {}

local currentSegmentId = nil
local currentHandlingModifier = { gripMultiplier = 1.0, suspensionWearMultiplier = 1.0, status = "OPTIMAL" }

-- Sample known highway segments
local SegmentCoords = {
    { id = "seg_del_perro_fwy_1", x = -400.0, y = -800.0, z = 20.0, radius = 500.0 },
    { id = "seg_la_puerta_fwy_1", x = 100.0, y = -1750.0, z = 15.0, radius = 400.0 },
    { id = "seg_palomino_fwy_1", x = 1700.0, y = -250.0, z = 35.0, radius = 600.0 },
    { id = "seg_senora_fwy_1", x = 2000.0, y = 3500.0, z = 55.0, radius = 800.0 },
}

CreateThread(function()
    while true do
        Wait(2000)
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if GetPedInVehicleSeat(veh, -1) == ped then
                local pCoords = GetEntityCoords(veh)
                local matched = nil

                for _, seg in ipairs(SegmentCoords) do
                    local dist = #(pCoords - vector3(seg.x, seg.y, seg.z))
                    if dist <= seg.radius then
                        matched = seg.id
                        break
                    end
                end

                if matched ~= currentSegmentId then
                    currentSegmentId = matched
                    if currentSegmentId then
                        -- Query segment condition from server or trigger pass
                        TriggerServerEvent("nyx:vehicles:server:recordHighwayPass", currentSegmentId, 2500.0, 2)
                    end
                end
            end
        else
            currentSegmentId = nil
        end
    end
end)

RegisterNetEvent("nyx:vehicles:client:highwayPassRecorded", function(payload)
    if not payload or not payload.success then return end
    local eval = Nyx.Vehicles.RoadDegradation.CalculateHandlingPenalty(payload.newQuality)
    currentHandlingModifier = eval

    -- Send NUI notification for UI dashboard overlay
    SendNUIMessage({
        action = "updateHighwayRoadCondition",
        data = {
            segmentId = payload.segmentId,
            qualityPct = payload.newQuality,
            status = payload.status,
            gripMultiplier = eval.gripMultiplier
        }
    })
end)
