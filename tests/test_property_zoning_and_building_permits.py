"""
Nyxframework: Property Zoning & Building Permits Test Suite
Tests fee calculations, treasury splits, blueprint validation, auto-approval thresholds,
state machine transitions, and renovation property capacity upgrades.
"""

import math
import os
import pytest


class BuildingPermitEngine:
    ZoningRules = {
        "retail_storefront": {
            "label": "Retail Commercial District",
            "maxFloorAreaSqm": 1500,
            "maxHeightMeters": 20.00,
            "basePermitFee": 450.00,
            "inspectionFeeFlat": 200.00,
            "environmentalSurchargeRate": 0.0150,
            "requiresCertifiedBlueprint": True,
            "autoApprovalEligible": True,
        },
        "corporate_office": {
            "label": "Corporate Executive District",
            "maxFloorAreaSqm": 3000,
            "maxHeightMeters": 60.00,
            "basePermitFee": 850.00,
            "inspectionFeeFlat": 350.00,
            "environmentalSurchargeRate": 0.0200,
            "requiresCertifiedBlueprint": True,
            "autoApprovalEligible": False,
        },
        "industrial_warehouse": {
            "label": "Industrial Logistics Zone",
            "maxFloorAreaSqm": 10000,
            "maxHeightMeters": 35.00,
            "basePermitFee": 1200.00,
            "inspectionFeeFlat": 500.00,
            "environmentalSurchargeRate": 0.0350,
            "requiresCertifiedBlueprint": True,
            "autoApprovalEligible": False,
        },
        "hospitality_venue": {
            "label": "Commercial Entertainment Sector",
            "maxFloorAreaSqm": 2500,
            "maxHeightMeters": 25.00,
            "basePermitFee": 650.00,
            "inspectionFeeFlat": 300.00,
            "environmentalSurchargeRate": 0.0250,
            "requiresCertifiedBlueprint": True,
            "autoApprovalEligible": False,
        },
        "medical_clinic": {
            "label": "Public Health & Clinical Complex",
            "maxFloorAreaSqm": 2000,
            "maxHeightMeters": 30.00,
            "basePermitFee": 750.00,
            "inspectionFeeFlat": 400.00,
            "environmentalSurchargeRate": 0.0100,
            "requiresCertifiedBlueprint": True,
            "autoApprovalEligible": False,
        },
    }

    RenovationTypes = {
        "interior_remodel": {
            "label": "Interior Storefront Remodel",
            "rateMultiplier": 1.00,
            "capacityBonusKg": 250,
            "registerSlotBonus": 1,
            "minStructuralTier": 1,
        },
        "facade_modernization": {
            "label": "Exterior Facade Modernization",
            "rateMultiplier": 1.20,
            "capacityBonusKg": 100,
            "registerSlotBonus": 0,
            "minStructuralTier": 1,
        },
        "structural_expansion": {
            "label": "Structural Mezzanine Expansion",
            "rateMultiplier": 1.80,
            "capacityBonusKg": 1000,
            "registerSlotBonus": 2,
            "minStructuralTier": 2,
        },
        "safety_upgrade": {
            "label": "Fire & Safety System Retrofit",
            "rateMultiplier": 0.80,
            "capacityBonusKg": 0,
            "registerSlotBonus": 0,
            "minStructuralTier": 1,
        },
        "industrial_conversion": {
            "label": "Heavy Industrial Storage Conversion",
            "rateMultiplier": 2.20,
            "capacityBonusKg": 3000,
            "registerSlotBonus": 3,
            "minStructuralTier": 3,
        },
    }

    @staticmethod
    def round_to_cent(val):
        return math.floor(float(val) * 100.0 + 0.5) / 100.0

    @classmethod
    def calculate_permit_fees(cls, zoning_type, renovation_type, floor_area_sqm, blueprint_cost, laws_catalog=None):
        zoning_rule = cls.ZoningRules.get(zoning_type, cls.ZoningRules["retail_storefront"])
        renovation_rule = cls.RenovationTypes.get(renovation_type, cls.RenovationTypes["interior_remodel"])
        area = max(1, int(floor_area_sqm or 100))
        bp_cost = max(0.0, cls.round_to_cent(blueprint_cost or 0.0))

        base_permit_fee = cls.round_to_cent(zoning_rule["basePermitFee"] * renovation_rule["rateMultiplier"])
        inspection_fee = cls.round_to_cent(zoning_rule["inspectionFeeFlat"])

        env_rate = zoning_rule["environmentalSurchargeRate"]
        if laws_catalog and "zoning:industrial_environmental_surcharge" in laws_catalog:
            law_data = laws_catalog["zoning:industrial_environmental_surcharge"]
            if isinstance(law_data, dict) and "surcharge" in law_data:
                env_rate = float(law_data["surcharge"])

        env_surcharge = cls.round_to_cent(area * env_rate * 10.0)
        total_permit_fee = cls.round_to_cent(base_permit_fee + inspection_fee + env_surcharge)
        total_project_cost = cls.round_to_cent(total_permit_fee + bp_cost)

        civil_works_split = cls.round_to_cent(base_permit_fee + env_surcharge)
        inspection_pool_split = cls.round_to_cent(inspection_fee)

        return {
            "zoningType": zoning_type,
            "renovationType": renovation_type,
            "floorAreaSqm": area,
            "basePermitFee": base_permit_fee,
            "inspectionFee": inspection_fee,
            "environmentalSurcharge": env_surcharge,
            "environmentalSurchargeRate": env_rate,
            "blueprintCost": bp_cost,
            "totalPermitFee": total_permit_fee,
            "totalProjectCost": total_project_cost,
            "treasurySplit": {
                "civilWorksFund": civil_works_split,
                "inspectionPool": inspection_pool_split,
                "blueprintEscrow": bp_cost,
            },
        }

    @classmethod
    def validate_blueprint(cls, blueprint_data, property_zoning, property_limits=None):
        if not blueprint_data or not isinstance(blueprint_data, dict):
            return False, "Missing or invalid architectural blueprint payload"

        target_zoning = blueprint_data.get("target_zoning") or blueprint_data.get("targetZoning")
        if target_zoning and target_zoning != property_zoning:
            return False, f"Blueprint target zoning '{target_zoning}' does not match property zoning '{property_zoning}'"

        zoning_rule = cls.ZoningRules.get(property_zoning, cls.ZoningRules["retail_storefront"])
        max_area = property_limits.get("maxFloorAreaSqm") if property_limits else zoning_rule["maxFloorAreaSqm"]
        bp_area = int(blueprint_data.get("floor_area_sqm") or blueprint_data.get("floorAreaSqm") or 0)

        if bp_area > max_area:
            return False, f"Blueprint floor area ({bp_area} sqm) exceeds statutory maximum ({max_area} sqm)"

        if zoning_rule["requiresCertifiedBlueprint"]:
            is_certified = blueprint_data.get("is_certified")
            if is_certified is None:
                is_certified = blueprint_data.get("isCertified")
            if is_certified is False or is_certified == 0 or is_certified is None:
                return False, "Property zoning requires a certified architectural blueprint"

        return True, None

    @classmethod
    def evaluate_auto_approval(cls, permit_data):
        if not permit_data or not isinstance(permit_data, dict):
            return False

        zoning_rule = cls.ZoningRules.get(permit_data.get("zoningType"))
        if not zoning_rule or not zoning_rule.get("autoApprovalEligible"):
            return False

        renovation_rule = cls.RenovationTypes.get(permit_data.get("renovationType"))
        if not renovation_rule or renovation_rule.get("minStructuralTier", 1) > 1:
            return False

        area = int(permit_data.get("floorAreaSqm") or 0)
        if area > 500:
            return False

        return True

    @classmethod
    def transition_permit_state(cls, current_status, action, context=None):
        action = str(action or "").upper()
        current_status = str(current_status or "SUBMITTED").upper()

        if action == "AUTO_APPROVE":
            if current_status == "SUBMITTED":
                return "APPROVED", None
            return current_status, "Auto-approval only valid from SUBMITTED state"
        elif action == "REQUEST_INSPECTION":
            if current_status == "SUBMITTED":
                return "INSPECTION_PENDING", None
            return current_status, "Inspection request only valid from SUBMITTED state"
        elif action == "APPROVE":
            if current_status in ["SUBMITTED", "INSPECTION_PENDING"]:
                return "APPROVED", None
            return current_status, f"Cannot approve permit from '{current_status}' status"
        elif action == "REJECT":
            if current_status in ["SUBMITTED", "INSPECTION_PENDING"]:
                return "REJECTED", None
            return current_status, f"Cannot reject permit from '{current_status}' status"
        elif action == "COMPLETE":
            if current_status == "APPROVED":
                return "COMPLETED", None
            return current_status, f"Cannot complete renovation; permit status is '{current_status}', expected 'APPROVED'"
        elif action == "REVOKE":
            if current_status in ["APPROVED", "INSPECTION_PENDING", "SUBMITTED"]:
                return "REVOKED", None
            return current_status, f"Cannot revoke permit from '{current_status}' status"

        return current_status, f"Invalid permit state action '{action}'"

    @classmethod
    def calculate_renovation_property_bonus(cls, renovation_type, current_stash_kg, current_registers):
        reno = cls.RenovationTypes.get(renovation_type, cls.RenovationTypes["interior_remodel"])
        base_stash = max(0, int(current_stash_kg or 1000))
        base_regs = max(1, int(current_registers or 2))

        new_stash = base_stash + reno["capacityBonusKg"]
        new_regs = base_regs + reno["registerSlotBonus"]

        return {
            "renovationType": renovation_type,
            "previousStashCapacityKg": base_stash,
            "newStashCapacityKg": new_stash,
            "previousRegisterSlots": base_regs,
            "newRegisterSlots": new_regs,
            "bonusStashKg": reno["capacityBonusKg"],
            "bonusRegisters": reno["registerSlotBonus"],
        }


# ----------------------------------------------------------------------------
# Test Cases
# ----------------------------------------------------------------------------

def test_permit_fee_calculations():
    fees = BuildingPermitEngine.calculate_permit_fees("retail_storefront", "interior_remodel", 250, 750.00)
    assert fees["basePermitFee"] == 450.00
    assert fees["inspectionFee"] == 200.00
    assert fees["environmentalSurcharge"] == 37.50
    assert fees["blueprintCost"] == 750.00
    assert fees["totalPermitFee"] == 687.50
    assert fees["totalProjectCost"] == 1437.50
    assert fees["treasurySplit"]["civilWorksFund"] == 487.50
    assert fees["treasurySplit"]["inspectionPool"] == 200.00


def test_permit_fee_calculations_heavy_industrial():
    fees = BuildingPermitEngine.calculate_permit_fees("industrial_warehouse", "industrial_conversion", 2500, 3000.00)
    # basePermitFee = 1200 * 2.2 = 2640.00
    assert fees["basePermitFee"] == 2640.00
    assert fees["inspectionFee"] == 500.00
    # envSurcharge = 2500 * 0.035 * 10 = 875.00
    assert fees["environmentalSurcharge"] == 875.00
    assert fees["totalPermitFee"] == 4015.00
    assert fees["totalProjectCost"] == 7015.00


def test_blueprint_validation_success():
    bp = {
        "blueprint_id": "bp_retail_mod_v1",
        "target_zoning": "retail_storefront",
        "floor_area_sqm": 250,
        "is_certified": True,
    }
    is_valid, err = BuildingPermitEngine.validate_blueprint(bp, "retail_storefront")
    assert is_valid is True
    assert err is None


def test_blueprint_validation_mismatched_zoning():
    bp = {
        "blueprint_id": "bp_office_expansion_v1",
        "target_zoning": "corporate_office",
        "floor_area_sqm": 600,
        "is_certified": True,
    }
    is_valid, err = BuildingPermitEngine.validate_blueprint(bp, "retail_storefront")
    assert is_valid is False
    assert "target zoning 'corporate_office' does not match" in err


def test_blueprint_validation_uncertified():
    bp = {
        "blueprint_id": "bp_uncertified_v1",
        "target_zoning": "retail_storefront",
        "floor_area_sqm": 200,
        "is_certified": False,
    }
    is_valid, err = BuildingPermitEngine.validate_blueprint(bp, "retail_storefront")
    assert is_valid is False
    assert "requires a certified architectural blueprint" in err


def test_auto_approval_evaluation():
    # Eligible: retail_storefront, interior_remodel (tier 1), floorArea <= 500
    permit = {
        "zoningType": "retail_storefront",
        "renovationType": "interior_remodel",
        "floorAreaSqm": 250,
        "blueprintCertified": True,
    }
    assert BuildingPermitEngine.evaluate_auto_approval(permit) is True

    # Ineligible: corporate_office does not allow auto-approval
    permit["zoningType"] = "corporate_office"
    assert BuildingPermitEngine.evaluate_auto_approval(permit) is False

    # Ineligible: structural_expansion is tier 2
    permit["zoningType"] = "retail_storefront"
    permit["renovationType"] = "structural_expansion"
    assert BuildingPermitEngine.evaluate_auto_approval(permit) is False


def test_permit_state_machine_transitions():
    state, err = BuildingPermitEngine.transition_permit_state("SUBMITTED", "REQUEST_INSPECTION")
    assert state == "INSPECTION_PENDING"
    assert err is None

    state, err = BuildingPermitEngine.transition_permit_state("INSPECTION_PENDING", "APPROVE")
    assert state == "APPROVED"
    assert err is None

    state, err = BuildingPermitEngine.transition_permit_state("APPROVED", "COMPLETE")
    assert state == "COMPLETED"
    assert err is None

    # Invalid completion from SUBMITTED
    state, err = BuildingPermitEngine.transition_permit_state("SUBMITTED", "COMPLETE")
    assert state == "SUBMITTED"
    assert "expected 'APPROVED'" in err


def test_renovation_property_bonuses():
    bonus = BuildingPermitEngine.calculate_renovation_property_bonus("industrial_conversion", 10000, 2)
    assert bonus["newStashCapacityKg"] == 13000
    assert bonus["newRegisterSlots"] == 5
    assert bonus["bonusStashKg"] == 3000
    assert bonus["bonusRegisters"] == 3


def test_sql_migration_files_exist():
    migration_name = "067_property_zoning_and_building_permits.sql"
    paths = [
        os.path.join("FiveM", "nyx_core", "sql", "migrations", migration_name),
        os.path.join("FiveM", "nyx_properties", "sql", "migrations", migration_name),
        os.path.join("FiveM", "nyx_treasury", "sql", "migrations", migration_name),
    ]
    for path in paths:
        assert os.path.exists(path), f"Migration file missing: {path}"
