--[[
    Nyxframework: nyx_services
    File: client/exports.lua
    Description: Client export wrappers for power grid and utility state.
]]

exports("IsPlayerInBlackout", function()
    return IsPlayerInBlackout and IsPlayerInBlackout() or false
end)

exports("IsCoordsPowered", function(coords)
    return IsCoordsPowered and IsCoordsPowered(coords) or true
end)

exports("GetActiveBlackouts", function()
    return GetActiveBlackouts and GetActiveBlackouts() or {}
end)

exports("GetNearestFarm", function(maxDist)
    return Nyx.Services and Nyx.Services.GetNearestFarm and Nyx.Services.GetNearestFarm(maxDist)
end)

exports("GetNearestPantry", function(maxDist)
    return Nyx.Services and Nyx.Services.GetNearestPantry and Nyx.Services.GetNearestPantry(maxDist)
end)

exports("IsHarvestingCrop", function()
    return Nyx.Services and Nyx.Services.IsHarvesting and Nyx.Services.IsHarvesting() or false
end)

exports("GetNearestTransformer", function(maxDist)
    return Nyx.Services and Nyx.Services.GetNearestTransformer and Nyx.Services.GetNearestTransformer(maxDist)
end)

exports("IsSabotaging", function()
    return isSabotaging or false
end)

exports("GetMeterStatus", function(meterId, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("services:getMeter", function(res)
            if cb then cb(res and res.success, res and res.meter) end
        end, meterId)
    end
end)

exports("PayUtilityBill", function(meterId, amount, cb)
    if exports['nyx_core'] and exports['nyx_core'].TriggerRPC then
        exports['nyx_core']:TriggerRPC("services:payUtilityBill", function(res)
            if cb then cb(res and res.success, res and res.data, res and res.error) end
        end, meterId, amount)
    end
end)

-- Hospital Beds & Clinical Triage Recovery Client Exports
exports("GetCurrentHospitalBed", function()
    return Nyx.Services and Nyx.Services.CurrentBed or nil
end)

exports("GetNearbyHospitalBeds", function(maxDist)
    return Nyx.Services and Nyx.Services.GetNearbyBeds and Nyx.Services.GetNearbyBeds(maxDist) or {}
end)

exports("AdmitToNearbyHospitalBed", function()
    local nearby = Nyx.Services and Nyx.Services.GetNearbyBeds and Nyx.Services.GetNearbyBeds(3.0) or {}
    if #nearby > 0 then
        local targetBed = nearby[1].bed
        Nyx.Services.AdmitToBedClient(targetBed.bed_id or targetBed.bedId)
        return true
    end
    return false
end)

exports("ExitCurrentHospitalBed", function()
    if Nyx.Services and Nyx.Services.DischargeCurrentBedClient then
        Nyx.Services.DischargeCurrentBedClient()
        return true
    end
    return false
end)

exports("SanitizeHospitalBed", function(bedId, itemKey)
    if Nyx.Services and Nyx.Services.SanitizeBedClient then
        Nyx.Services.SanitizeBedClient(bedId, itemKey)
        return true
    end
    return false
end)

-- Chemical & Pharmaceutical Synthesis Laboratories Client Exports
exports("GetClosestChemicalLab", function(maxDist)
    maxDist = maxDist or 50.0
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local closestLab = nil
    local closestDist = maxDist

    local knownPoints = {
        ['chemlab_humane_biotech'] = vector3(3538.5, 3660.2, 28.1),
        ['chemlab_cypress_refinery'] = vector3(922.5, -2148.0, 30.5),
        ['chemlab_pillbox_pharmacy'] = vector3(356.2, -598.4, 43.3),
        ['chemlab_sandy_lab'] = vector3(1852.3, 3680.1, 34.2)
    }

    for labId, coords in pairs(knownPoints) do
        local dist = #(pCoords - coords)
        if dist <= closestDist then
            closestDist = dist
            closestLab = { labId = labId, coords = coords, distance = dist }
        end
    end
    return closestLab
end)

exports("GetNearbyChemicalLabs", function(maxDist)
    maxDist = maxDist or 100.0
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local results = {}

    local knownPoints = {
        ['chemlab_humane_biotech'] = vector3(3538.5, 3660.2, 28.1),
        ['chemlab_cypress_refinery'] = vector3(922.5, -2148.0, 30.5),
        ['chemlab_pillbox_pharmacy'] = vector3(356.2, -598.4, 43.3),
        ['chemlab_sandy_lab'] = vector3(1852.3, 3680.1, 34.2)
    }

    for labId, coords in pairs(knownPoints) do
        local dist = #(pCoords - coords)
        if dist <= maxDist then
            table.insert(results, { labId = labId, coords = coords, distance = dist })
        end
    end
    return results
end)
