--[[
    Nyxframework: nyx_vehicles
    File: server/road_degradation.lua
    Description: Authoritative server state management for highway road segment degradation,
                 transit pass recording, municipal public works repair contracts,
                 and treasury/services integration.
]]

Nyx = Nyx or {}
Nyx.Vehicles = Nyx.Vehicles or {}
Nyx.Vehicles.RoadDegradationServer = Nyx.Vehicles.RoadDegradationServer or {}

local RoadSegments = {}

-- Load active highway segments on resource start
local function loadHighwaySegments()
    MySQL.query("SELECT * FROM `nyx_highway_segments`", {}, function(rows)
        if rows then
            for _, row in ipairs(rows) do
                RoadSegments[row.segment_id] = {
                    segment_id = row.segment_id,
                    highway_name = row.highway_name,
                    length_meters = tonumber(row.length_meters) or 1000.0,
                    quality_pct = tonumber(row.quality_pct) or 100.0,
                    total_heavy_axle_passages = tonumber(row.total_heavy_axle_passages) or 0,
                    status = row.status or "OPTIMAL"
                }
            end
            print(string.format("^2[Nyx:Vehicles] Loaded %d highway road segments.^7", #rows))
        end
    end)
end

CreateThread(function()
    while GetResourceState("oxmysql") ~= "started" do
        Wait(100)
    end
    loadHighwaySegments()
end)

--- Records a vehicle transit passage over a highway segment and degrades quality
--- @param segmentId string
--- @param grossWeightKg number
--- @param axleCount number
--- @return table Result payload { success = boolean, newQuality = number, damageFactor = number, status = string }
function Nyx.Vehicles.RoadDegradationServer.RecordTransitPass(segmentId, grossWeightKg, axleCount)
    if not segmentId or not RoadSegments[segmentId] then
        return { success = false, message = "INVALID_SEGMENT_ID" }
    end

    grossWeightKg = tonumber(grossWeightKg) or 1500.0
    axleCount = tonumber(axleCount) or 2

    local damageFactor = Nyx.Vehicles.RoadDegradation.CalculateAxleDamageFactor(grossWeightKg, axleCount)
    local seg = RoadSegments[segmentId]

    -- Heavy vehicles (damageFactor >= 1.5) accumulate heavy axle passages
    if damageFactor >= 1.5 then
        seg.total_heavy_axle_passages = seg.total_heavy_axle_passages + 1
    end

    -- Deduct quality proportionally
    local qualityLoss = damageFactor * 0.05
    seg.quality_pct = math.max(0.00, seg.quality_pct - qualityLoss)

    local eval = Nyx.Vehicles.RoadDegradation.CalculateHandlingPenalty(seg.quality_pct)
    seg.status = eval.status

    -- Async DB sync
    MySQL.update("UPDATE `nyx_highway_segments` SET `quality_pct` = ?, `total_heavy_axle_passages` = ?, `status` = ? WHERE `segment_id` = ?", {
        seg.quality_pct, seg.total_heavy_axle_passages, seg.status, segmentId
    })

    -- Auto-generate repair contract if quality drops below 60%
    if seg.quality_pct < 60.0 then
        local repairInfo = Nyx.Vehicles.RoadDegradation.CalculateRepairCostAndMaterials(seg.length_meters, 100.0 - seg.quality_pct)
        local contractId = "contract_" .. segmentId
        MySQL.query("INSERT INTO `nyx_road_repair_contracts` (`contract_id`, `segment_id`, `required_asphalt_kg`, `treasury_payout`, `status`) VALUES (?, ?, ?, ?, 'OPEN') ON DUPLICATE KEY UPDATE `required_asphalt_kg` = VALUES(`required_asphalt_kg`), `treasury_payout` = VALUES(`treasury_payout`)", {
            contractId, segmentId, repairInfo.requiredAsphaltKg, repairInfo.treasuryPayout
        })
    end

    return {
        success = true,
        segmentId = segmentId,
        newQuality = seg.quality_pct,
        damageFactor = damageFactor,
        status = seg.status
    }
end

--- Retrieves current highway segment condition
--- @param segmentId string
--- @return table
function Nyx.Vehicles.RoadDegradationServer.GetSegmentCondition(segmentId)
    if not segmentId or not RoadSegments[segmentId] then
        return { quality_pct = 100.0, status = "OPTIMAL", total_heavy_axle_passages = 0 }
    end
    return RoadSegments[segmentId]
end

--- Submits a road repair batch with asphalt to restore segment quality
--- @param segmentId string
--- @param asphaltKg number
--- @param factionId string
--- @return table Result payload { success = boolean, restoredQuality = number, payout = number }
function Nyx.Vehicles.RoadDegradationServer.SubmitRoadRepair(segmentId, asphaltKg, factionId)
    if not segmentId or not RoadSegments[segmentId] then
        return { success = false, message = "INVALID_SEGMENT" }
    end

    asphaltKg = math.max(0.0, tonumber(asphaltKg) or 0.0)
    local seg = RoadSegments[segmentId]
    local qualityLoss = 100.0 - seg.quality_pct

    if qualityLoss <= 0 then
        return { success = false, message = "ROAD_ALREADY_OPTIMAL" }
    end

    local repairInfo = Nyx.Vehicles.RoadDegradation.CalculateRepairCostAndMaterials(seg.length_meters, qualityLoss)
    local asphaltNeeded = repairInfo.requiredAsphaltKg

    local restoreRatio = asphaltNeeded > 0 and math.min(1.0, asphaltKg / asphaltNeeded) or 1.0
    local restoredPoints = qualityLoss * restoreRatio
    seg.quality_pct = math.min(100.0, seg.quality_pct + restoredPoints)

    local eval = Nyx.Vehicles.RoadDegradation.CalculateHandlingPenalty(seg.quality_pct)
    seg.status = eval.status

    local payout = repairInfo.treasuryPayout * restoreRatio

    MySQL.update("UPDATE `nyx_highway_segments` SET `quality_pct` = ?, `status` = ?, `last_repaired_at` = CURRENT_TIMESTAMP WHERE `segment_id` = ?", {
        seg.quality_pct, seg.status, segmentId
    })

    if seg.quality_pct >= 95.0 then
        MySQL.update("UPDATE `nyx_road_repair_contracts` SET `status` = 'COMPLETED', `completed_at` = CURRENT_TIMESTAMP WHERE `segment_id` = ?", { segmentId })
    end

    return {
        success = true,
        segmentId = segmentId,
        restoredQuality = seg.quality_pct,
        payout = payout,
        status = seg.status
    }
end

-- Server Events
RegisterNetEvent("nyx:vehicles:server:recordHighwayPass", function(segmentId, grossWeightKg, axleCount)
    local src = source
    local res = Nyx.Vehicles.RoadDegradationServer.RecordTransitPass(segmentId, grossWeightKg, axleCount)
    TriggerClientEvent("nyx:vehicles:client:highwayPassRecorded", src, res)
end)

RegisterNetEvent("nyx:vehicles:server:submitRoadRepair", function(segmentId, asphaltKg, factionId)
    local src = source
    local res = Nyx.Vehicles.RoadDegradationServer.SubmitRoadRepair(segmentId, asphaltKg, factionId)
    TriggerClientEvent("nyx:vehicles:client:roadRepairSubmitted", src, res)
end)
