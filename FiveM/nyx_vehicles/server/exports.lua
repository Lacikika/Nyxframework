--[[
    Nyxframework: nyx_vehicles
    File: server/exports.lua
    Description: Clean public server exports for vehicle lifecycle, storage, and access keys.
]]

Nyx = Nyx or {}

exports("SpawnVehicle", function(src, vin, coords, heading)
    return Nyx.Vehicles.SpawnVehicle(src, vin, coords, heading)
end)

exports("DespawnVehicle", function(src, vin, garageId)
    return Nyx.Vehicles.DespawnVehicle(src, vin, garageId)
end)

exports("HasKey", function(citizenId, vin, plate)
    return Nyx.Vehicles.HasKey(citizenId, vin, plate)
end)

exports("ToggleLock", function(src, vinOrNetId)
    return Nyx.Vehicles.ToggleLock(src, vinOrNetId)
end)

exports("RepairVehicle", function(src, vin, fullRepair)
    return Nyx.Vehicles.RepairVehicle(src, vin, fullRepair)
end)

exports("GetActiveVehicle", function(vinOrNetId)
    local vin = vinOrNetId
    if type(vinOrNetId) == "number" or tonumber(vinOrNetId) then
        vin = Nyx.Vehicles.ByNetId[tonumber(vinOrNetId)]
    end
    return vin and Nyx.Vehicles.Active[vin] or nil
end)

exports("GetPlayerVehicles", function(citizenId)
    return Nyx.Vehicles.GetPlayerVehicles(citizenId)
end)

exports("GetVehicleWear", function(vinOrNetId)
    return Nyx.Vehicles.GetWear(vinOrNetId)
end)

exports("GetVehicleMileage", function(vinOrNetId)
    local wear = Nyx.Vehicles.GetWear(vinOrNetId)
    return wear and wear.mileage or 0.0
end)

exports("ResetTrip", function(vinOrNetId)
    return Nyx.Vehicles.ResetTrip(vinOrNetId)
end)

exports("ServiceVehicle", function(src, vinOrNetId, serviceType, notes)
    return Nyx.Vehicles.ServiceVehicle(src, vinOrNetId, serviceType, notes)
end)

exports("UpdateVehicleWear", function(vinOrNetId, deltaKm, wearDeltas)
    return Nyx.Vehicles.UpdateWear(vinOrNetId, deltaKm, wearDeltas)
end)

exports("ImpoundVehicle", function(vin, reason, fee, impoundLotId, officerCitizenId)
    return Nyx.Vehicles.ImpoundVehicle(vin, reason, fee, impoundLotId, officerCitizenId)
end)

exports("ReleaseImpoundedVehicle", function(src, vin, impoundLotId)
    return Nyx.Vehicles.ReleaseImpoundedVehicle(src, vin, impoundLotId)
end)

exports("GetImpoundedVehicles", function(citizenId, optionalLotId)
    return Nyx.Vehicles.GetImpoundedVehicles(citizenId, optionalLotId)
end)

exports("GetVehicleRegistration", function(vin)
    return Nyx.Vehicles.GetVehicleRegistration(vin)
end)

exports("RenewVehicleRegistration", function(src, vin)
    return Nyx.Vehicles.RenewVehicleRegistration(src, vin)
end)

exports("GetDiagnosticsOverview", function(src, vinOrIdentifier)
    return Nyx.Vehicles.GetDiagnosticsOverview(src, vinOrIdentifier)
end)

exports("ScanVehicle", function(src, vinOrPlate, notes)
    return Nyx.Vehicles.ScanVehicle(src, vinOrPlate, notes)
end)

exports("PerformCertifiedService", function(src, payload)
    return Nyx.Vehicles.PerformCertifiedService(src, payload)
end)

exports("GetCivicImpoundLots", function()
    return Nyx.Vehicles.ImpoundLots or {}
end)

exports("GetGasStation", function(stationId)
    return Nyx.VehicleFuel.GetGasStation(stationId)
end)

exports("GetAllGasStations", function()
    return Nyx.VehicleFuel.GetAllGasStations()
end)

exports("GetGasStationReservoir", function(stationId)
    return Nyx.VehicleFuel.GetGasStationReservoir(stationId)
end)

exports("ReplenishReservoir", function(stationId, liters)
    return Nyx.VehicleFuel.ReplenishReservoir(stationId, liters)
end)

-- Keys, Fleet RFID Tokens & Lockpicking Forensics
exports("CheckIgnition", function(src, vinOrNetId)
    return Nyx.Vehicles.CheckIgnition(src, vinOrNetId)
end)

exports("AttemptLockpick", function(src, netId, useGloves)
    return Nyx.Vehicles.AttemptLockpick(src, netId, useGloves)
end)

exports("AttemptHotwire", function(src, netId, useGloves)
    return Nyx.Vehicles.AttemptHotwire(src, netId, useGloves)
end)

exports("IssuePhysicalKey", function(src, vin, targetCitId, keyType)
    return Nyx.Vehicles.IssuePhysicalKey(src, vin, targetCitId, keyType)
end)

exports("IssueRfidToken", function(src, factionId, targetCitId, accessLevel, label)
    return Nyx.Vehicles.IssueRfidToken(src, factionId, targetCitId, accessLevel, label)
end)

exports("RevokeRfidToken", function(src, tokenUuid, reason)
    return Nyx.Vehicles.RevokeRfidToken(src, tokenUuid, reason)
end)

exports("GetVehicleLockpickHistory", function(vin)
    return Nyx.Vehicles.GetLockpickHistory(vin)
end)


