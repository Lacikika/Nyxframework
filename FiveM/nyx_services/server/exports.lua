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

exports("HydrateSubstationRecord", function(subId, dbRow, cfgSub)
    return Nyx.Services.HydrateSubstationRecord(subId, dbRow, cfgSub)
end)

-- Metered Utility Billing & Grid Load
exports("RegisterUtilityMeter", function(meterId, ownerCitId, substationId, propertyType, propertyId)
    return Nyx.Services.RegisterMeter(meterId, ownerCitId, substationId, propertyType, propertyId)
end)

exports("RecordUtilityConsumption", function(meterId, kwh, water)
    return Nyx.Services.RecordConsumption(meterId, kwh, water)
end)

exports("GetUtilityMeter", function(meterId)
    return Nyx.Services.GetMeter(meterId)
end)

exports("GetMeterByPropertyId", function(propertyId)
    return Nyx.Services.GetMeterByPropertyId(propertyId)
end)

exports("GetUtilityInvoices", function(meterId, limit)
    return Nyx.Services.GetUtilityInvoices(meterId, limit)
end)

exports("GetSubstationGridLoad", function(substationId)
    return Nyx.Services.GetSubstationGridLoad(substationId)
end)

exports("ProcessUtilityBillingCycle", function()
    return Nyx.Services.ProcessUtilityBillingCycle()
end)

exports("PayUtilityBill", function(src, meterId, amount)
    return Nyx.Services.PayUtilityBill(src, meterId, amount)
end)

exports("EnforcePowerCutoff", function(meterId, reason, actorCitizenId)
    return Nyx.Services.EnforcePowerCutoff(meterId, reason, actorCitizenId)
end)

exports("ReconnectUtility", function(meterId, actorCitizenId)
    return Nyx.Services.ReconnectUtility(meterId, actorCitizenId)
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

exports("GetHospitalStashId", function(hospitalId)
    local h = Nyx.Services.GetHospital(hospitalId)
    return h and h.stashId or Nyx.HospitalSupplies.GetStashIdForHospital(hospitalId)
end)

exports("GetHospitalSupplyCounts", function(hospitalId)
    return Nyx.Services.GetHospitalStashCounts(hospitalId)
end)

exports("EvaluateHospitalStatus", function(hospitalId)
    return Nyx.Services.EvaluateHospitalStatus(hospitalId)
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

-- Anatomical Trauma & Medical Injury Engine
exports("GetPlayerTraumaState", function(src)
    return Nyx.Services.GetPlayerTrauma(src)
end)

exports("AddLimbDamage", function(src, limb, woundType, severity)
    return Nyx.Services.AddLimbDamage(src, limb, woundType, severity)
end)

exports("ApplyMedicalTreatment", function(medicSrc, patientSrc, limb, item)
    return Nyx.Services.ApplyMedicalTreatment(medicSrc, patientSrc, limb, item)
end)

exports("DiagnosePlayerTrauma", function(examinerSrc, patientSrc)
    return Nyx.Services.DiagnosePatient(examinerSrc, patientSrc)
end)

exports("ResetTraumaState", function(src)
    return Nyx.Services.ResetTraumaState(src)
end)

exports("SetPlayerBloodVolume", function(src, volume)
    local state = Nyx.Services.GetPlayerTrauma(src)
    if state then
        state.bloodVolume = math.max(0, math.min(5000, tonumber(volume) or 5000))
        local _, _, isUnc = Nyx.Trauma.CalculateShockClass(state.bloodVolume)
        state.isUnconscious = isUnc
        Nyx.Services.SavePlayerTrauma(src)
        return true, state.bloodVolume
    end
    return false, "TRAUMA_STATE_NOT_FOUND"
end)

-- Agricultural Extraction & Food Pantries
exports("GetFarm", function(farmId)
    return Nyx.Services.Farms and Nyx.Services.Farms[farmId]
end)

exports("GetAllFarms", function()
    return Nyx.Services.Farms or {}
end)

exports("HarvestCrop", function(src, farmId)
    return Nyx.Services.HarvestCrop(src, farmId)
end)

exports("GetPantry", function(pantryId)
    return Nyx.Services.Pantries and Nyx.Services.Pantries[pantryId]
end)

exports("GetAllPantries", function()
    return Nyx.Services.Pantries or {}
end)

exports("GetPantrySupplyCounts", function(pantryId)
    return Nyx.Services.GetPantryStockCounts(pantryId)
end)

exports("EvaluatePantryStatus", function(pantryId)
    return Nyx.Services.EvaluatePantryStatus(pantryId)
end)

exports("RestockPantry", function(src, pantryId, itemId, amount)
    return Nyx.Services.RestockPantry(src, pantryId, itemId, amount)
end)

exports("DisposeSpoiledFood", function(src, pantryId)
    return Nyx.Services.DisposeSpoiledFood(src, pantryId)
end)

exports("RecordFoodAudit", function(action, sourceId, targetInvId, itemId, quantity, durability, isSpoiled, citizenId, notes)
    return Nyx.Services.RecordFoodAudit(action, sourceId, targetInvId, itemId, quantity, durability, isSpoiled, citizenId, notes)
end)

-- Substation Sabotage & Security Locks
exports("SabotageSubstation", function(src, substationId, toolName)
    return Nyx.Services.SabotageSubstation(src, substationId, toolName)
end)

exports("GetSabotageStatus", function(substationId)
    return Nyx.Services.GetSabotageStatus(substationId)
end)

exports("GetSabotageLogs", function(substationId, limit)
    return Nyx.Services.GetSabotageLogs(substationId, limit)
end)

exports("IsSubstationSabotaged", function(substationId)
    local s = Nyx.Services.GetSubstation(substationId)
    return s and s.isSabotaged or false
end)

exports("EvaluateDoorlockState", function(propertyType, isLocked, isPowered, hasBackupGen)
    return Nyx.Sabotage.EvaluateDoorlockState(propertyType, isLocked, isPowered, hasBackupGen)
end)

exports("EvaluateWarehouseLockState", function(isLocked, isPowered, hasBackupGen)
    return Nyx.Sabotage.EvaluateWarehouseLockState(isLocked, isPowered, hasBackupGen)
end)

exports("EvaluateAlarmStatus", function(hasAlarm, isPowered, hasBackupGen, isDoorBreached)
    return Nyx.Sabotage.EvaluateAlarmStatus(hasAlarm, isPowered, hasBackupGen, isDoorBreached)
end)

-- Hospital Beds & Clinical Triage Recovery
exports("GetHospitalBed", function(bedId)
    local bed = Nyx.Services.HospitalBeds and Nyx.Services.HospitalBeds[bedId]
    return bed and Nyx.HospitalBeds.FormatBedSummary(bed) or nil
end)

exports("GetHospitalBeds", function(hospitalId)
    local results = {}
    if Nyx.Services.HospitalBeds then
        for _, bed in pairs(Nyx.Services.HospitalBeds) do
            if not hospitalId or bed.hospital_id == hospitalId then
                table.insert(results, Nyx.HospitalBeds.FormatBedSummary(bed))
            end
        end
    end
    return results
end)

exports("AdmitToHospitalBed", function(bedId, patientSrc)
    return Nyx.Services.AdmitPatientToBed(bedId, patientSrc)
end)

exports("DischargeFromHospitalBed", function(bedId, reason)
    return Nyx.Services.DischargePatientFromBed(bedId, reason)
end)

exports("SanitizeHospitalBed", function(src, bedId, itemKey)
    return Nyx.Services.SanitizeBed(src, bedId, itemKey)
end)

exports("AdministerHospitalBedTreatment", function(bedId, item)
    return Nyx.Services.AdministerBedTreatment(bedId, item)
end)

exports("GetPlayerOccupiedBed", function(src)
    return Nyx.Services.OccupiedBedSources and Nyx.Services.OccupiedBedSources[src] or nil
end)

-- Chemical & Pharmaceutical Synthesis Laboratories
exports("GetChemicalLab", function(labId)
    local lab = Nyx.Services.ChemicalLabs and Nyx.Services.ChemicalLabs[labId]
    return lab and Nyx.ChemicalLabs.FormatLabDisplay(lab) or nil
end)

exports("GetChemicalLabs", function()
    local results = {}
    if Nyx.Services.ChemicalLabs then
        for _, lab in pairs(Nyx.Services.ChemicalLabs) do
            table.insert(results, Nyx.ChemicalLabs.FormatLabDisplay(lab))
        end
    end
    return results
end)

exports("StartChemicalSynthesis", function(src, labId, recipeKey, quantity)
    return Nyx.Services.StartChemicalSynthesis(src, labId, recipeKey, quantity)
end)

exports("SterilizeChemicalLab", function(src, labId)
    return Nyx.Services.StartLabSterilization(src, labId)
end)

