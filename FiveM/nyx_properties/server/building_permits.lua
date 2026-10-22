--[[
    Nyxframework: nyx_properties
    File: server/building_permits.lua
    Description: Authoritative Server State Manager for Property Zoning & Building Permits.
                 Handles oxmysql persistence, treasury fee deduction, municipal inspector
                 approval workflows, and commercial renovation completions.
]]

Nyx = Nyx or {}
Nyx.BuildingPermits = Nyx.BuildingPermits or {}

local isMySQLReady = false

if MySQL and MySQL.ready then
    MySQL.ready(function()
        isMySQLReady = true
    end)
end

-- In-memory runtime cache for building permits
local activePermits = {}

-- ----------------------------------------------------------------------------
-- Helper Functions
-- ----------------------------------------------------------------------------
local function generatePermitId()
    local timestamp = os.time()
    local rand = math.random(1000, 9999)
    return string.format("PERMIT-%d-%d", timestamp, rand)
end

local function auditLog(action, source, details)
    print(string.format("^3[Nyx:BuildingPermits:Audit]^7 [%s] Source: %s | Details: %s", action, tostring(source), json.encode(details)))
    if Nyx.Treasury and Nyx.Treasury.RecordAuditTrail then
        pcall(Nyx.Treasury.RecordAuditTrail, source, "BUILDING_PERMIT_" .. action, details)
    end
end

-- ----------------------------------------------------------------------------
-- 1. Fetch Property Zoning & Blueprint DB Records
-- ----------------------------------------------------------------------------
function Nyx.BuildingPermits.GetZoningRule(zoningType)
    if isMySQLReady then
        local rows = MySQL.query.await("SELECT * FROM nyx_property_zoning_rules WHERE zoning_type = ?", { zoningType })
        if rows and #rows > 0 then
            return rows[1]
        end
    end
    return Nyx.BuildingPermits.ZoningRules[zoningType] or Nyx.BuildingPermits.ZoningRules.retail_storefront
end

function Nyx.BuildingPermits.GetBlueprint(blueprintId)
    if isMySQLReady then
        local rows = MySQL.query.await("SELECT * FROM nyx_architectural_blueprints WHERE blueprint_id = ?", { blueprintId })
        if rows and #rows > 0 then
            return rows[1]
        end
    end
    return {
        blueprint_id = blueprintId,
        architect_identifier = "arch_city_planning",
        title = "Standard Blueprint",
        target_zoning = "retail_storefront",
        floor_area_sqm = 250,
        structural_tier = 1,
        blueprint_cost = 750.00,
        is_certified = 1
    }
end

-- ----------------------------------------------------------------------------
-- 2. Submit Building Permit Application
-- ----------------------------------------------------------------------------
function Nyx.BuildingPermits.SubmitPermitApplication(source, propertyId, renovationType, blueprintId, playerMoney)
    local player = Nyx.GetPlayerFromId and Nyx.GetPlayerFromId(source)
    local citizenId = player and player.citizenId or ("CITIZEN-" .. tostring(source))

    -- Fetch Property
    local property = nil
    if isMySQLReady then
        local props = MySQL.query.await("SELECT * FROM nyx_properties WHERE property_id = ?", { propertyId })
        if props and #props > 0 then
            property = props[1]
        end
    end

    local zoningType = property and property.commercial_zoning or "retail_storefront"
    if zoningType == "none" or not zoningType then
        zoningType = "retail_storefront"
    end

    local blueprint = Nyx.BuildingPermits.GetBlueprint(blueprintId)
    local isValidBp, bpErr = Nyx.BuildingPermits.ValidateBlueprint(blueprint, zoningType, nil)
    if not isValidBp then
        return false, bpErr, nil
    end

    local feeSummary = Nyx.BuildingPermits.CalculatePermitFees(
        zoningType,
        renovationType,
        blueprint.floor_area_sqm or 250,
        blueprint.blueprint_cost or 0.00,
        nil
    )

    local totalCost = feeSummary.totalProjectCost

    -- Funds verification & deduction
    local availableMoney = playerMoney or (player and player.getBank and player.getBank() or 100000.00)
    if availableMoney < totalCost then
        return false, string.format("Insufficient funds for permit application ($%.2f required, $%.2f available)", totalCost, availableMoney), nil
    end

    if player and player.removeBank then
        player.removeBank(totalCost)
    end

    -- Treasury Fee Allocations
    if Nyx.Treasury and Nyx.Treasury.DepositDepartmentFund then
        pcall(Nyx.Treasury.DepositDepartmentFund, "treasury_civil_works", feeSummary.treasurySplit.civilWorksFund, "BUILDING_PERMIT_FEE")
        pcall(Nyx.Treasury.DepositDepartmentFund, "treasury_inspection_pool", feeSummary.treasurySplit.inspectionPool, "BUILDING_INSPECTION_FEE")
    end

    local permitId = generatePermitId()
    local isAutoApproved = Nyx.BuildingPermits.EvaluateAutoApproval({
        zoningType = zoningType,
        renovationType = renovationType,
        floorAreaSqm = blueprint.floor_area_sqm,
        blueprintCertified = (blueprint.is_certified == 1 or blueprint.is_certified == true)
    })

    local initialStatus = isAutoApproved and "APPROVED" or "INSPECTION_PENDING"

    local permitRecord = {
        permit_id = permitId,
        property_id = propertyId,
        applicant_identifier = citizenId,
        applicant_faction = nil,
        zoning_type = zoningType,
        renovation_type = renovationType,
        blueprint_id = blueprintId,
        floor_area_sqm = blueprint.floor_area_sqm or 250,
        base_permit_fee = feeSummary.basePermitFee,
        inspection_fee = feeSummary.inspectionFee,
        environmental_surcharge = feeSummary.environmentalSurcharge,
        blueprint_cost = feeSummary.blueprintCost,
        total_cost = totalCost,
        status = initialStatus,
        inspector_identifier = isAutoApproved and "MUNICIPAL_AUTO_APPROVER" or nil,
        rejection_reason = nil
    }

    if isMySQLReady then
        MySQL.insert.await([[
            INSERT INTO nyx_building_permits
            (permit_id, property_id, applicant_identifier, applicant_faction, zoning_type, renovation_type, blueprint_id, floor_area_sqm, base_permit_fee, inspection_fee, environmental_surcharge, blueprint_cost, total_cost, status, inspector_identifier, approved_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            permitId, propertyId, citizenId, nil, zoningType, renovationType, blueprintId,
            blueprint.floor_area_sqm or 250, feeSummary.basePermitFee, feeSummary.inspectionFee,
            feeSummary.environmentalSurcharge, feeSummary.blueprintCost, totalCost,
            initialStatus, isAutoApproved and "MUNICIPAL_AUTO_APPROVER" or nil,
            isAutoApproved and os.date("!%Y-%m-%d %H:%M:%S") or nil
        })
    end

    activePermits[permitId] = permitRecord

    auditLog("APPLICATION_SUBMITTED", source, {
        permitId = permitId,
        propertyId = propertyId,
        totalCost = totalCost,
        status = initialStatus
    })

    return true, "Permit application submitted successfully", permitRecord
end

-- ----------------------------------------------------------------------------
-- 3. Inspect & Approve / Reject Building Permit
-- ----------------------------------------------------------------------------
function Nyx.BuildingPermits.InspectPermit(source, permitId, action, rejectionReason)
    local inspectorPlayer = Nyx.GetPlayerFromId and Nyx.GetPlayerFromId(source)
    local inspectorId = inspectorPlayer and inspectorPlayer.citizenId or ("INSPECTOR-" .. tostring(source))

    local permit = activePermits[permitId]
    if not permit and isMySQLReady then
        local rows = MySQL.query.await("SELECT * FROM nyx_building_permits WHERE permit_id = ?", { permitId })
        if rows and #rows > 0 then
            permit = rows[1]
        end
    end

    if not permit then
        return false, "Permit record not found"
    end

    local newStatus, err = Nyx.BuildingPermits.TransitionPermitState(permit.status, action, nil)
    if err then
        return false, err
    end

    permit.status = newStatus
    permit.inspector_identifier = inspectorId
    if action == "REJECT" then
        permit.rejection_reason = rejectionReason or "Inspection failed statutory code compliance"
    end

    if isMySQLReady then
        MySQL.update.await([[
            UPDATE nyx_building_permits
            SET status = ?, inspector_identifier = ?, rejection_reason = ?, approved_at = CASE WHEN ? = 'APPROVED' THEN CURRENT_TIMESTAMP ELSE approved_at END
            WHERE permit_id = ?
        ]], { newStatus, inspectorId, permit.rejection_reason, newStatus, permitId })
    end

    activePermits[permitId] = permit

    auditLog("INSPECTION_PROCESSED", source, {
        permitId = permitId,
        action = action,
        newStatus = newStatus,
        inspectorId = inspectorId
    })

    return true, string.format("Permit status updated to '%s'", newStatus), permit
end

-- ----------------------------------------------------------------------------
-- 4. Complete Commercial Renovation
-- ----------------------------------------------------------------------------
function Nyx.BuildingPermits.CompleteRenovation(source, permitId)
    local permit = activePermits[permitId]
    if not permit and isMySQLReady then
        local rows = MySQL.query.await("SELECT * FROM nyx_building_permits WHERE permit_id = ?", { permitId })
        if rows and #rows > 0 then
            permit = rows[1]
        end
    end

    if not permit then
        return false, "Permit record not found"
    end

    local newStatus, err = Nyx.BuildingPermits.TransitionPermitState(permit.status, "COMPLETE", nil)
    if err then
        return false, err
    end

    permit.status = newStatus

    -- Fetch existing property capacity
    local currentStashKg = 1000
    local currentRegisters = 2

    if isMySQLReady then
        local props = MySQL.query.await("SELECT stash_capacity_kg, register_count FROM nyx_properties WHERE property_id = ?", { permit.property_id })
        if props and #props > 0 then
            currentStashKg = props[1].stash_capacity_kg or 1000
            currentRegisters = props[1].register_count or 2
        end
    end

    local bonus = Nyx.BuildingPermits.CalculateRenovationPropertyBonus(permit.renovation_type, currentStashKg, currentRegisters)

    if isMySQLReady then
        MySQL.update.await([[
            UPDATE nyx_properties
            SET stash_capacity_kg = ?, register_count = ?
            WHERE property_id = ?
        ]], { bonus.newStashCapacityKg, bonus.newRegisterSlots, permit.property_id })

        MySQL.update.await([[
            UPDATE nyx_building_permits
            SET status = 'COMPLETED', completed_at = CURRENT_TIMESTAMP
            WHERE permit_id = ?
        ]], { permitId })
    end

    activePermits[permitId] = permit

    auditLog("RENOVATION_COMPLETED", source, {
        permitId = permitId,
        propertyId = permit.property_id,
        newStashCapacityKg = bonus.newStashCapacityKg,
        newRegisterSlots = bonus.newRegisterSlots
    })

    return true, "Renovation completed successfully; property attributes upgraded", bonus
end

-- ----------------------------------------------------------------------------
-- 5. Query Active Property Permits
-- ----------------------------------------------------------------------------
function Nyx.BuildingPermits.GetPropertyPermits(propertyId)
    if isMySQLReady then
        return MySQL.query.await("SELECT * FROM nyx_building_permits WHERE property_id = ? ORDER BY created_at DESC", { propertyId })
    end

    local result = {}
    for _, p in pairs(activePermits) do
        if p.property_id == propertyId then
            table.insert(result, p)
        end
    end
    return result
end

-- Net Events / RPC Handlers
RegisterNetEvent("nyx_properties:submitPermit", function(propertyId, renovationType, blueprintId)
    local src = source
    local ok, msg, data = Nyx.BuildingPermits.SubmitPermitApplication(src, propertyId, renovationType, blueprintId)
    TriggerClientEvent("nyx_properties:permitSubmittedResponse", src, ok, msg, data)
end)

RegisterNetEvent("nyx_properties:inspectPermit", function(permitId, action, rejectionReason)
    local src = source
    local ok, msg, data = Nyx.BuildingPermits.InspectPermit(src, permitId, action, rejectionReason)
    TriggerClientEvent("nyx_properties:permitInspectedResponse", src, ok, msg, data)
end)

RegisterNetEvent("nyx_properties:completeRenovation", function(permitId)
    local src = source
    local ok, msg, data = Nyx.BuildingPermits.CompleteRenovation(src, permitId)
    TriggerClientEvent("nyx_properties:renovationCompletedResponse", src, ok, msg, data)
end)

-- Exports
exports("SubmitBuildingPermit", function(source, propertyId, renovationType, blueprintId)
    return Nyx.BuildingPermits.SubmitPermitApplication(source, propertyId, renovationType, blueprintId)
end)

exports("InspectBuildingPermit", function(source, permitId, action, rejectionReason)
    return Nyx.BuildingPermits.InspectPermit(source, permitId, action, rejectionReason)
end)

exports("CompletePropertyRenovation", function(source, permitId)
    return Nyx.BuildingPermits.CompleteRenovation(source, permitId)
end)

exports("CalculatePermitFees", function(zoningType, renovationType, floorAreaSqm, blueprintCost)
    return Nyx.BuildingPermits.CalculatePermitFees(zoningType, renovationType, floorAreaSqm, blueprintCost)
end)
