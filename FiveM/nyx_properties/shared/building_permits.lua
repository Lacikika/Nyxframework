--[[
    Nyxframework: nyx_properties
    File: shared/building_permits.lua
    Description: Deterministic Commercial Property Zoning, Architectural Blueprint Validation,
                 Permit Fee Calculation Engine, Treasury Split Math & Permit State Machine.
]]

Nyx = Nyx or {}
Nyx.BuildingPermits = Nyx.BuildingPermits or {}

-- Cent-precision rounding helper
local function roundToCent(val)
    val = tonumber(val) or 0.0
    return math.floor(val * 100.0 + 0.5) / 100.0
end

Nyx.BuildingPermits.RoundToCent = roundToCent

-- ----------------------------------------------------------------------------
-- 1. Statutory Zoning Rules Taxonomy
-- ----------------------------------------------------------------------------
Nyx.BuildingPermits.ZoningRules = {
    retail_storefront = {
        label = "Retail Commercial District",
        maxFloorAreaSqm = 1500,
        maxHeightMeters = 20.00,
        basePermitFee = 450.00,
        inspectionFeeFlat = 200.00,
        environmentalSurchargeRate = 0.0150,
        requiresCertifiedBlueprint = true,
        autoApprovalEligible = true
    },
    corporate_office = {
        label = "Corporate Executive District",
        maxFloorAreaSqm = 3000,
        maxHeightMeters = 60.00,
        basePermitFee = 850.00,
        inspectionFeeFlat = 350.00,
        environmentalSurchargeRate = 0.0200,
        requiresCertifiedBlueprint = true,
        autoApprovalEligible = false
    },
    industrial_warehouse = {
        label = "Industrial Logistics Zone",
        maxFloorAreaSqm = 10000,
        maxHeightMeters = 35.00,
        basePermitFee = 1200.00,
        inspectionFeeFlat = 500.00,
        environmentalSurchargeRate = 0.0350,
        requiresCertifiedBlueprint = true,
        autoApprovalEligible = false
    },
    hospitality_venue = {
        label = "Commercial Entertainment Sector",
        maxFloorAreaSqm = 2500,
        maxHeightMeters = 25.00,
        basePermitFee = 650.00,
        inspectionFeeFlat = 300.00,
        environmentalSurchargeRate = 0.0250,
        requiresCertifiedBlueprint = true,
        autoApprovalEligible = false
    },
    medical_clinic = {
        label = "Public Health & Clinical Complex",
        maxFloorAreaSqm = 2000,
        maxHeightMeters = 30.00,
        basePermitFee = 750.00,
        inspectionFeeFlat = 400.00,
        environmentalSurchargeRate = 0.0100,
        requiresCertifiedBlueprint = true,
        autoApprovalEligible = false
    }
}

-- ----------------------------------------------------------------------------
-- 2. Renovation Types Taxonomy
-- ----------------------------------------------------------------------------
Nyx.BuildingPermits.RenovationTypes = {
    interior_remodel = {
        label = "Interior Storefront Remodel",
        rateMultiplier = 1.00,
        capacityBonusKg = 250,
        registerSlotBonus = 1,
        minStructuralTier = 1
    },
    facade_modernization = {
        label = "Exterior Facade Modernization",
        rateMultiplier = 1.20,
        capacityBonusKg = 100,
        registerSlotBonus = 0,
        minStructuralTier = 1
    },
    structural_expansion = {
        label = "Structural Mezzanine Expansion",
        rateMultiplier = 1.80,
        capacityBonusKg = 1000,
        registerSlotBonus = 2,
        minStructuralTier = 2
    },
    safety_upgrade = {
        label = "Fire & Safety System Retrofit",
        rateMultiplier = 0.80,
        capacityBonusKg = 0,
        registerSlotBonus = 0,
        minStructuralTier = 1
    },
    industrial_conversion = {
        label = "Heavy Industrial Storage Conversion",
        rateMultiplier = 2.20,
        capacityBonusKg = 3000,
        registerSlotBonus = 3,
        minStructuralTier = 3
    }
}

-- ----------------------------------------------------------------------------
-- 3. Pure Deterministic Fee Calculation
-- ----------------------------------------------------------------------------
--- Calculates building permit fees, environmental surcharges, and treasury splits
-- @param zoningType string
-- @param renovationType string
-- @param floorAreaSqm number
-- @param blueprintCost number
-- @param lawsCatalog table|nil
-- @return table
function Nyx.BuildingPermits.CalculatePermitFees(zoningType, renovationType, floorAreaSqm, blueprintCost, lawsCatalog)
    local zoningRule = Nyx.BuildingPermits.ZoningRules[zoningType] or Nyx.BuildingPermits.ZoningRules.retail_storefront
    local renovationRule = Nyx.BuildingPermits.RenovationTypes[renovationType] or Nyx.BuildingPermits.RenovationTypes.interior_remodel
    local area = math.max(1, tonumber(floorAreaSqm) or 100)
    local bpCost = math.max(0.0, roundToCent(blueprintCost or 0.0))

    local basePermitFee = roundToCent(zoningRule.basePermitFee * renovationRule.rateMultiplier)
    local inspectionFee = roundToCent(zoningRule.inspectionFeeFlat)

    local envRate = zoningRule.environmentalSurchargeRate
    if lawsCatalog and lawsCatalog["zoning:industrial_environmental_surcharge"] then
        local lawData = lawsCatalog["zoning:industrial_environmental_surcharge"]
        if type(lawData) == "table" and lawData.surcharge then
            envRate = tonumber(lawData.surcharge) or envRate
        end
    end

    local envSurcharge = roundToCent(area * envRate * 10.0)
    local totalPermitFee = roundToCent(basePermitFee + inspectionFee + envSurcharge)
    local totalProjectCost = roundToCent(totalPermitFee + bpCost)

    -- Statutory Treasury Splits
    local civilWorksSplit = roundToCent(basePermitFee + envSurcharge)
    local inspectionPoolSplit = roundToCent(inspectionFee)

    return {
        zoningType = zoningType,
        renovationType = renovationType,
        floorAreaSqm = area,
        basePermitFee = basePermitFee,
        inspectionFee = inspectionFee,
        environmentalSurcharge = envSurcharge,
        environmentalSurchargeRate = envRate,
        blueprintCost = bpCost,
        totalPermitFee = totalPermitFee,
        totalProjectCost = totalProjectCost,
        treasurySplit = {
            civilWorksFund = civilWorksSplit,
            inspectionPool = inspectionPoolSplit,
            blueprintEscrow = bpCost
        }
    }
end

-- ----------------------------------------------------------------------------
-- 4. Architectural Blueprint Validation
-- ----------------------------------------------------------------------------
--- Validates whether an architectural blueprint is eligible for a property renovation
-- @param blueprintData table
-- @param propertyZoning string
-- @param propertyLimits table|nil
-- @return boolean, string|nil
function Nyx.BuildingPermits.ValidateBlueprint(blueprintData, propertyZoning, propertyLimits)
    if not blueprintData or type(blueprintData) ~= "table" then
        return false, "Missing or invalid architectural blueprint payload"
    end

    local targetZoning = blueprintData.target_zoning or blueprintData.targetZoning
    if targetZoning and targetZoning ~= propertyZoning then
        return false, string.format("Blueprint target zoning '%s' does not match property zoning '%s'", targetZoning, propertyZoning)
    end

    local zoningRule = Nyx.BuildingPermits.ZoningRules[propertyZoning] or Nyx.BuildingPermits.ZoningRules.retail_storefront
    local maxArea = propertyLimits and propertyLimits.maxFloorAreaSqm or zoningRule.maxFloorAreaSqm
    local bpArea = tonumber(blueprintData.floor_area_sqm or blueprintData.floorAreaSqm) or 0

    if bpArea > maxArea then
        return false, string.format("Blueprint floor area (%d sqm) exceeds statutory maximum (%d sqm)", bpArea, maxArea)
    end

    if zoningRule.requiresCertifiedBlueprint then
        local isCertified = blueprintData.is_certified
        if isCertified == nil then
            isCertified = blueprintData.isCertified
        end
        if isCertified == 0 or isCertified == false or isCertified == nil then
            return false, "Property zoning requires a certified architectural blueprint"
        end
    end

    return true, nil
end

-- ----------------------------------------------------------------------------
-- 5. Auto-Approval Evaluation
-- ----------------------------------------------------------------------------
--- Evaluates whether a permit application qualifies for automated municipal approval
-- @param permitData table
-- @return boolean
function Nyx.BuildingPermits.EvaluateAutoApproval(permitData)
    if not permitData or type(permitData) ~= "table" then
        return false
    end

    local zoningRule = Nyx.BuildingPermits.ZoningRules[permitData.zoningType]
    if not zoningRule or not zoningRule.autoApprovalEligible then
        return false
    end

    local renovationRule = Nyx.BuildingPermits.RenovationTypes[permitData.renovationType]
    if not renovationRule or renovationRule.minStructuralTier > 1 then
        return false
    end

    local area = tonumber(permitData.floorAreaSqm) or 0
    if area > 500 then
        return false
    end

    return true
end

-- ----------------------------------------------------------------------------
-- 6. Permit Life-Cycle State Machine
-- ----------------------------------------------------------------------------
--- Pure transition state machine for building permit workflow
-- @param currentStatus string
-- @param action string
-- @param context table|nil
-- @return string, string|nil
function Nyx.BuildingPermits.TransitionPermitState(currentStatus, action, context)
    action = string.upper(action or "")
    currentStatus = string.upper(currentStatus or "SUBMITTED")

    if action == "AUTO_APPROVE" then
        if currentStatus == "SUBMITTED" then
            return "APPROVED", nil
        else
            return currentStatus, "Auto-approval only valid from SUBMITTED state"
        end
    elseif action == "REQUEST_INSPECTION" then
        if currentStatus == "SUBMITTED" then
            return "INSPECTION_PENDING", nil
        else
            return currentStatus, "Inspection request only valid from SUBMITTED state"
        end
    elseif action == "APPROVE" then
        if currentStatus == "SUBMITTED" or currentStatus == "INSPECTION_PENDING" then
            return "APPROVED", nil
        else
            return currentStatus, string.format("Cannot approve permit from '%s' status", currentStatus)
        end
    elseif action == "REJECT" then
        if currentStatus == "SUBMITTED" or currentStatus == "INSPECTION_PENDING" then
            return "REJECTED", nil
        else
            return currentStatus, string.format("Cannot reject permit from '%s' status", currentStatus)
        end
    elseif action == "COMPLETE" then
        if currentStatus == "APPROVED" then
            return "COMPLETED", nil
        else
            return currentStatus, string.format("Cannot complete renovation; permit status is '%s', expected 'APPROVED'", currentStatus)
        end
    elseif action == "REVOKE" then
        if currentStatus == "APPROVED" or currentStatus == "INSPECTION_PENDING" or currentStatus == "SUBMITTED" then
            return "REVOKED", nil
        else
            return currentStatus, string.format("Cannot revoke permit from '%s' status", currentStatus)
        end
    end

    return currentStatus, string.format("Invalid permit state action '%s'", action)
end

-- ----------------------------------------------------------------------------
-- 7. Renovation Property Bonus Calculation
-- ----------------------------------------------------------------------------
--- Calculates updated stash capacity and register slot totals after renovation completion
-- @param renovationType string
-- @param currentStashKg number
-- @param currentRegisters number
-- @return table
function Nyx.BuildingPermits.CalculateRenovationPropertyBonus(renovationType, currentStashKg, currentRegisters)
    local reno = Nyx.BuildingPermits.RenovationTypes[renovationType] or Nyx.BuildingPermits.RenovationTypes.interior_remodel
    local baseStash = math.max(0, tonumber(currentStashKg) or 1000)
    local baseRegs = math.max(1, tonumber(currentRegisters) or 2)

    local newStash = baseStash + reno.capacityBonusKg
    local newRegs = baseRegs + reno.registerSlotBonus

    return {
        renovationType = renovationType,
        previousStashCapacityKg = baseStash,
        newStashCapacityKg = newStash,
        previousRegisterSlots = baseRegs,
        newRegisterSlots = newRegs,
        bonusStashKg = reno.capacityBonusKg,
        bonusRegisters = reno.registerSlotBonus
    }
end
