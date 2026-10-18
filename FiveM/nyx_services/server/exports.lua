--[[
    Nyxframework: nyx_services
    File: server/exports.lua
    Description: Clean public server exports for power grid, utility billing, and healthcare systems.
]]

Nyx = Nyx or {}

-- Power Grid & Substations
exports("IsCoordsPowered", function(coords)
    return Nyx.Services.IsCoordsPowered(coords)
end)

exports("IsSubstationPowered", function(substationId)
    local s = Nyx.Services.GetSubstation(substationId)
    return s and not s.isBlackout or false
end)

exports("GetSubstation", function(substationId)
    return Nyx.Services.GetSubstation(substationId)
end)

exports("GetAllSubstations", function()
    return Nyx.Services.GetAllSubstations()
end)

exports("RefuelSubstation", function(src, substationId)
    return Nyx.Services.RefuelSubstation(src, substationId)
end)

exports("RepairSubstation", function(src, substationId)
    return Nyx.Services.RepairSubstation(src, substationId)
end)

exports("TriggerSubstationFailure", function(substationId, reason, citizenId)
    return Nyx.Services.TriggerSubstationFailure(substationId, reason, citizenId)
end)

exports("ResetCircuitBreaker", function(src, substationId)
    return Nyx.Services.ResetCircuitBreaker(src, substationId)
end)

exports("SimulateGridOverload", function(substationId, spikeMw)
    return Nyx.Services.SimulateGridOverload(substationId, spikeMw)
end)

exports("GetSubstationDiagnostics", function(substationId)
    return Nyx.Services.GetSubstationDiagnostics(substationId)
end)

-- Metered Utility Billing
exports("RegisterUtilityMeter", function(meterId, ownerCitId, substationId, propertyType)
    return Nyx.Services.RegisterMeter(meterId, ownerCitId, substationId, propertyType)
end)

exports("RecordUtilityConsumption", function(meterId, kwh, water)
    return Nyx.Services.RecordConsumption(meterId, kwh, water)
end)

-- Healthcare & Hospitals
exports("GetHospital", function(hospitalId)
    return Nyx.Services.GetHospital(hospitalId)
end)

exports("GetAllHospitals", function()
    return Nyx.Services.GetAllHospitals()
end)

exports("ProcessRevival", function(src, hospitalId, requiresSurgery)
    return Nyx.Services.ProcessRevival(src, hospitalId, requiresSurgery)
end)

exports("RestockHospital", function(src, hospitalId, item, amount)
    return Nyx.Services.RestockHospital(src, hospitalId, item, amount)
end)

-- Public Auto-Repair Stations
exports("GetRepairStations", function()
    return Nyx.Services.RepairStations or {}
end)

exports("GetRepairEstimate", function(src, stationId, vehicleNetId)
    return Nyx.Services.GetRepairEstimate(src, stationId, vehicleNetId)
end)

exports("RepairVehicleAtStation", function(src, stationId, vehicleNetId)
    return Nyx.Services.RepairVehicleAtStation(src, stationId, vehicleNetId)
end)
