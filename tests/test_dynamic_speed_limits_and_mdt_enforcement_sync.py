#!/usr/bin/env python3
"""
Unit and Integration Tests for Dynamic Speed Limits, Statutory Law Formulation & MDT Enforcement Overlays
(nyx_parliament, nyx_mdt, and nyx_vehicles).

Validates:
1. SQL migration 059 schema and mirroring.
2. Manifest declarations in nyx_parliament, nyx_mdt, and nyx_vehicles.
3. In-engine Test 54 registration in FiveM/nyx_core/server/tests.lua.
4. Python domain engine mirroring shared/statutory_enforcement.lua:
   - Statutory speed limit resolution by zone.
   - 4-Tier speeding infraction evaluation, buffer margins, and impound recommendations.
   - Exact cent closed-loop sales tax cap economic conservation.
   - Zoning policy adjustments (commercial rebate & industrial surcharge).
   - Structured bill action validation within constitutional limits.
   - 3D Euclidean radar zone spatial gating.
   - Dispatch warning overlay formatting and UUID generator.
"""

import os
import json
import math
import uuid
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class StatutoryEnforcementEngine:
    SPEED_BUFFER_MPH = 5.0
    DEFAULT_SALES_TAX_CAP = 0.1200

    DEFAULT_LIMITS = {
        "urban": 45.0,
        "highway": 75.0,
        "industrial": 35.0,
        "school_residential": 25.0,
    }

    ZONE_ALIASES = {
        "residential": "school_residential",
        "school": "school_residential",
        "city": "urban",
        "downtown": "urban",
        "freeway": "highway",
        "motorway": "highway",
        "factory": "industrial",
        "harbor": "industrial",
        "port": "industrial",
    }

    @staticmethod
    def round_to_cent(val):
        val = float(val or 0.0)
        return math.floor(val * 100.0 + 0.5) / 100.0

    @classmethod
    def resolve_speed_limit(cls, zone_name, laws=None):
        zone_key = str(zone_name or "urban").lower()
        zone_key = cls.ZONE_ALIASES.get(zone_key, zone_key)

        law_id = f"speed:{zone_key}"
        if laws and law_id in laws:
            cur_val = laws[law_id].get("currentValue", {})
            mph = cur_val.get("mph") or cur_val.get("speed") or cur_val.get("limit")
            if mph is not None:
                return float(mph)

        return float(cls.DEFAULT_LIMITS.get(zone_key, 45.0))

    @classmethod
    def get_sales_tax_cap(cls, laws=None):
        if laws and "tax:sales_cap" in laws:
            cur_val = laws["tax:sales_cap"].get("currentValue", {})
            rate = cur_val.get("rate") or cur_val.get("cap") or cur_val.get("taxRate")
            if rate is not None:
                return float(rate)
        return cls.DEFAULT_SALES_TAX_CAP

    @classmethod
    def evaluate_speeding(cls, measured_speed, zone_name, laws=None):
        speed = max(0.0, float(measured_speed or 0.0))
        speed_limit = cls.resolve_speed_limit(zone_name, laws)
        delta = speed - speed_limit

        res = {
            "measuredSpeed": speed,
            "speedLimit": speed_limit,
            "speedDelta": delta,
            "isViolation": False,
            "tier": 0,
            "tierLabel": "TIER_0_COMPLIANT",
            "recommendedFine": 0.00,
            "sentenceMonths": 0,
            "severity": "info",
            "triggerDispatchWarning": False,
            "impoundRecommended": False,
        }

        if delta <= cls.SPEED_BUFFER_MPH:
            return res

        res["isViolation"] = True

        if delta <= 15.0:
            res["tier"] = 1
            res["tierLabel"] = "TIER_1_MINOR"
            base_fine = 250.00
            months = 0
            if laws and "penal:speeding_minor" in laws:
                val = laws["penal:speeding_minor"].get("currentValue", {})
                base_fine = float(val.get("fine", 250.00))
                months = int(val.get("months", 0))

            over_margin = max(1.0, delta - cls.SPEED_BUFFER_MPH)
            fine = base_fine + (over_margin * 10.00)
            res["recommendedFine"] = cls.round_to_cent(fine)
            res["sentenceMonths"] = months
            res["severity"] = "warning"
            res["triggerDispatchWarning"] = False

        elif delta <= 30.0:
            res["tier"] = 2
            res["tierLabel"] = "TIER_2_MAJOR"
            base_fine = 750.00
            months = 5
            if laws and "penal:speeding_major" in laws:
                val = laws["penal:speeding_major"].get("currentValue", {})
                base_fine = float(val.get("fine", 750.00))
                months = int(val.get("months", 5))

            over_margin = max(1.0, delta - 15.0)
            fine = base_fine + (over_margin * 25.00)
            res["recommendedFine"] = cls.round_to_cent(fine)
            res["sentenceMonths"] = months
            res["severity"] = "warning"
            res["triggerDispatchWarning"] = True

        else:
            res["tier"] = 3
            res["tierLabel"] = "TIER_3_RECKLESS"
            base_fine = 2500.00
            months = 15
            if laws and "penal:reckless_driving" in laws:
                val = laws["penal:reckless_driving"].get("currentValue", {})
                base_fine = float(val.get("fine", 2500.00))
                months = int(val.get("months", 15))

            over_margin = max(1.0, delta - 30.0)
            fine = base_fine + (over_margin * 50.00)
            res["recommendedFine"] = cls.round_to_cent(fine)
            res["sentenceMonths"] = months
            res["severity"] = "critical"
            res["triggerDispatchWarning"] = True
            res["impoundRecommended"] = True

        return res

    @classmethod
    def calculate_sales_tax(cls, subtotal, requested_tax_rate, laws=None):
        sub = max(0.0, cls.round_to_cent(subtotal))
        raw_rate = max(0.0, float(requested_tax_rate or 0.0))
        cap = cls.get_sales_tax_cap(laws)

        eff_rate = min(raw_rate, cap)
        was_capped = raw_rate > cap

        tax_amt = cls.round_to_cent(sub * eff_rate)
        gross = cls.round_to_cent(sub + tax_amt)

        # Closed-loop economic conservation check
        diff = cls.round_to_cent(gross - (sub + tax_amt))
        if abs(diff) > 0.0001:
            tax_amt = cls.round_to_cent(tax_amt + diff)

        is_conserved = abs(gross - (sub + tax_amt)) < 0.001

        return {
            "subtotal": sub,
            "requestedRate": raw_rate,
            "effectiveRate": eff_rate,
            "statutoryCap": cap,
            "wasCapped": was_capped,
            "taxAmount": tax_amt,
            "grossTotal": gross,
            "isConserved": is_conserved,
        }

    @classmethod
    def evaluate_zoning_policy(cls, zone_classification, base_tax_rate, laws=None):
        base_rate = max(0.0, float(base_tax_rate or 0.0))
        z_type = str(zone_classification or "general").lower()

        rebate = 0.0
        surcharge = 0.0

        if "storefront" in z_type or "retail" in z_type or "commercial" in z_type:
            rebate = 0.02
            if laws and "zoning:commercial_tax_rebate" in laws:
                val = laws["zoning:commercial_tax_rebate"].get("currentValue", {})
                rebate = float(val.get("rebate", 0.02))
        elif "industrial" in z_type or "warehouse" in z_type:
            surcharge = 0.03
            if laws and "zoning:industrial_environmental_surcharge" in laws:
                val = laws["zoning:industrial_environmental_surcharge"].get("currentValue", {})
                surcharge = float(val.get("surcharge", 0.03))

        net_rate = max(0.0, base_rate - rebate + surcharge)
        adj_pct = surcharge - rebate

        return {
            "classification": z_type,
            "baseRate": base_rate,
            "rebatePct": rebate,
            "surchargePct": surcharge,
            "adjustmentPct": adj_pct,
            "netRate": net_rate,
        }

    @classmethod
    def validate_statutory_bill_actions(cls, actions, laws):
        if not actions or not isinstance(actions, list) or len(actions) == 0:
            return False, "ACTIONS_EMPTY"

        clean_actions = []
        for idx, act in enumerate(actions):
            if not isinstance(act, dict):
                return False, f"ACTION_INVALID_STRUCTURE_AT_{idx}"

            law_id = act.get("targetLawId")
            field = act.get("field")
            new_val = act.get("newValue")

            if not law_id or not field or new_val is None:
                return False, f"ACTION_MISSING_REQUIRED_FIELDS_AT_{idx}"

            if not laws or law_id not in laws:
                return False, f"TARGET_LAW_NOT_FOUND_{law_id}"

            law = laws[law_id]
            min_allowed = law.get("minAllowed", {}).get(field)
            max_allowed = law.get("maxAllowed", {}).get(field)

            if min_allowed is None or max_allowed is None:
                return False, f"FIELD_NOT_CONSTITUTIONALLY_MUTABLE_{field}_ON_{law_id}"

            num_val = float(new_val)
            if num_val < float(min_allowed) or num_val > float(max_allowed):
                return False, f"STATUTORY_VALUE_OUT_OF_BOUNDS_{law_id}_{field}"

            clean_actions.append({
                "targetLawId": str(law_id),
                "field": str(field),
                "newValue": num_val,
                "previousValue": law.get("currentValue", {}).get(field),
            })

        return True, clean_actions

    @classmethod
    def is_point_in_radar_zone(cls, point_coords, zone_coords, radius):
        px = float(point_coords.get("x", 0.0))
        py = float(point_coords.get("y", 0.0))
        pz = float(point_coords.get("z", 0.0))

        zx = float(zone_coords.get("x", 0.0))
        zy = float(zone_coords.get("y", 0.0))
        zz = float(zone_coords.get("z", 0.0))

        dx = px - zx
        dy = py - zy
        dz = pz - zz
        dist = math.sqrt(dx * dx + dy * dy + dz * dz)

        rad = max(10.0, float(radius or 150.0))
        return dist <= rad, dist

    @classmethod
    def format_warning_overlay(cls, warning):
        sev = str(warning.get("severity", "info")).lower()
        badge_cls = "badge-info"
        if sev == "critical":
            badge_cls = "badge-danger"
        elif sev == "warning":
            badge_cls = "badge-warning"

        cat = str(warning.get("category", "traffic")).lower()
        icon = "fa-car"
        if cat == "speeding_anpr":
            icon = "fa-tachometer-alt"
        elif cat == "statutory_reform":
            icon = "fa-landmark"
        elif cat == "tax_evasion":
            icon = "fa-file-invoice-dollar"

        return {
            "id": warning.get("id"),
            "category": cat,
            "severity": sev,
            "badgeClass": badge_cls,
            "icon": icon,
            "title": str(warning.get("title", "ALERT")),
            "locationLabel": str(warning.get("location_label") or warning.get("locationLabel") or "Unknown Area"),
            "status": str(warning.get("status", "active")),
        }

    @classmethod
    def generate_warning_uuid(cls):
        raw = str(uuid.uuid4()).replace("-", "")[:12].lower()
        return f"wrn-{raw}"


# ---------------------------------------------------------
# Test Cases
# ---------------------------------------------------------

def test_sql_migration_059_schema_and_mirroring():
    """Verify SQL migration 059 exists, is mirrored across resources, and is registered in index.json."""
    core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "059_dynamic_speed_limits_statutory_laws_and_mdt_overlays.sql")
    parl_mig = os.path.join(FIVEM_DIR, "nyx_parliament", "sql", "migrations", "059_dynamic_speed_limits_statutory_laws_and_mdt_overlays.sql")
    mdt_mig = os.path.join(FIVEM_DIR, "nyx_mdt", "sql", "migrations", "059_dynamic_speed_limits_statutory_laws_and_mdt_overlays.sql")
    idx_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")

    assert os.path.isfile(core_mig), "Core migration 059 missing"
    assert os.path.isfile(parl_mig), "Parliament migration 059 mirror missing"
    assert os.path.isfile(mdt_mig), "MDT migration 059 mirror missing"
    assert os.path.isfile(idx_path), "Migrations index.json missing"

    with open(core_mig, "r", encoding="utf-8") as f:
        core_sql = f.read()

    assert "nyx_parliament_laws" in core_sql
    assert "subsystem_target" in core_sql
    assert "nyx_mdt_dispatch_warnings" in core_sql
    assert "nyx_mdt_traffic_radar_zones" in core_sql
    assert "nyx_mdt_statutory_overrides" in core_sql
    assert "speed:urban" in core_sql
    assert "speed:highway" in core_sql
    assert "tax:sales_cap" in core_sql

    with open(idx_path, "r", encoding="utf-8") as f:
        idx_data = json.load(f)

    mig_059 = [m for m in idx_data if "059" in str(m)]
    assert len(mig_059) > 0, "Migration 059 not registered in index.json"
    assert "059_dynamic_speed_limits_statutory_laws_and_mdt_overlays.sql" in idx_data


def test_manifest_declarations():
    """Verify fxmanifest.lua updates in nyx_parliament, nyx_mdt, and nyx_vehicles."""
    parl_mf = os.path.join(FIVEM_DIR, "nyx_parliament", "fxmanifest.lua")
    mdt_mf = os.path.join(FIVEM_DIR, "nyx_mdt", "fxmanifest.lua")
    veh_mf = os.path.join(FIVEM_DIR, "nyx_vehicles", "fxmanifest.lua")

    with open(parl_mf, "r", encoding="utf-8") as f:
        p_content = f.read()
    with open(mdt_mf, "r", encoding="utf-8") as f:
        m_content = f.read()
    with open(veh_mf, "r", encoding="utf-8") as f:
        v_content = f.read()

    assert "shared/statutory_enforcement.lua" in p_content
    assert "@nyx_parliament/shared/statutory_enforcement.lua" in m_content
    assert "@nyx_parliament/shared/statutory_enforcement.lua" in v_content
    assert "client/speedometer.lua" in v_content
    assert "'nyx_parliament'" in v_content


def test_in_engine_test_54_registered():
    """Verify TestDynamicSpeedLimitsStatutoryLawsAndMDTOverlays is registered in server/tests.lua."""
    tests_lua = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
    with open(tests_lua, "r", encoding="utf-8") as f:
        content = f.read()

    assert "function Nyx.Tests.TestDynamicSpeedLimitsStatutoryLawsAndMDTOverlays()" in content
    assert "local t54 = Nyx.Tests.TestDynamicSpeedLimitsStatutoryLawsAndMDTOverlays()" in content
    assert "suites1to50Passed and t51 and t52 and t53 and t54" in content


def test_statutory_speed_limits_resolution():
    """Verify speed limits resolve correctly by zone taxonomy and fallback."""
    mock_laws = {
        "speed:urban": {"id": "speed:urban", "currentValue": {"mph": 45}},
        "speed:highway": {"id": "speed:highway", "currentValue": {"mph": 75}},
        "speed:industrial": {"id": "speed:industrial", "currentValue": {"mph": 35}},
        "speed:school_residential": {"id": "speed:school_residential", "currentValue": {"mph": 25}},
    }

    assert StatutoryEnforcementEngine.resolve_speed_limit("urban", mock_laws) == 45.0
    assert StatutoryEnforcementEngine.resolve_speed_limit("city", mock_laws) == 45.0
    assert StatutoryEnforcementEngine.resolve_speed_limit("highway", mock_laws) == 75.0
    assert StatutoryEnforcementEngine.resolve_speed_limit("freeway", mock_laws) == 75.0
    assert StatutoryEnforcementEngine.resolve_speed_limit("industrial", mock_laws) == 35.0
    assert StatutoryEnforcementEngine.resolve_speed_limit("factory", mock_laws) == 35.0
    assert StatutoryEnforcementEngine.resolve_speed_limit("school_residential", mock_laws) == 25.0
    assert StatutoryEnforcementEngine.resolve_speed_limit("school", mock_laws) == 25.0
    assert StatutoryEnforcementEngine.resolve_speed_limit("residential", mock_laws) == 25.0
    # Fallback without laws
    assert StatutoryEnforcementEngine.resolve_speed_limit("unknown_zone", None) == 45.0


def test_speeding_evaluation_tiers_and_penalties():
    """Verify 4-tier speeding evaluation, buffer margin (5 mph), and impound recommendations."""
    mock_laws = {
        "speed:urban": {"id": "speed:urban", "currentValue": {"mph": 45}},
        "penal:speeding_minor": {"id": "penal:speeding_minor", "currentValue": {"fine": 250, "months": 0}},
        "penal:speeding_major": {"id": "penal:speeding_major", "currentValue": {"fine": 750, "months": 5}},
        "penal:reckless_driving": {"id": "penal:reckless_driving", "currentValue": {"fine": 2500, "months": 15}},
    }

    # Within buffer margin: 45 + 3 = 48 mph <= 50 mph
    c = StatutoryEnforcementEngine.evaluate_speeding(48.0, "urban", mock_laws)
    assert c["isViolation"] is False
    assert c["tier"] == 0
    assert c["triggerDispatchWarning"] is False
    assert c["impoundRecommended"] is False

    # Tier 1 Minor: 45 + 10 = 55 mph (delta 10, > 5 and <= 15)
    m = StatutoryEnforcementEngine.evaluate_speeding(55.0, "urban", mock_laws)
    assert m["isViolation"] is True
    assert m["tier"] == 1
    assert m["recommendedFine"] >= 250.00
    assert m["sentenceMonths"] == 0
    assert m["severity"] == "warning"
    assert m["triggerDispatchWarning"] is False
    assert m["impoundRecommended"] is False

    # Tier 2 Major: 45 + 27 = 72 mph (delta 27, > 15 and <= 30)
    maj = StatutoryEnforcementEngine.evaluate_speeding(72.0, "urban", mock_laws)
    assert maj["isViolation"] is True
    assert maj["tier"] == 2
    assert maj["recommendedFine"] >= 750.00
    assert maj["sentenceMonths"] == 5
    assert maj["severity"] == "warning"
    assert maj["triggerDispatchWarning"] is True
    assert maj["impoundRecommended"] is False

    # Tier 3 Reckless: 45 + 53 = 98 mph (delta 53, > 30)
    rec = StatutoryEnforcementEngine.evaluate_speeding(98.0, "urban", mock_laws)
    assert rec["isViolation"] is True
    assert rec["tier"] == 3
    assert rec["recommendedFine"] >= 2500.00
    assert rec["sentenceMonths"] == 15
    assert rec["severity"] == "critical"
    assert rec["triggerDispatchWarning"] is True
    assert rec["impoundRecommended"] is True


def test_sales_tax_cap_and_closed_loop_conservation():
    """Verify sales tax statutory cap and exact-cent closed-loop economic conservation."""
    mock_laws = {
        "tax:sales_cap": {"id": "tax:sales_cap", "currentValue": {"rate": 0.12}},
    }

    # Standard uncapped rate: 8%
    std = StatutoryEnforcementEngine.calculate_sales_tax(2500.00, 0.08, mock_laws)
    assert std["effectiveRate"] == 0.08
    assert std["wasCapped"] is False
    assert std["taxAmount"] == 200.00
    assert std["grossTotal"] == 2700.00
    assert std["isConserved"] is True

    # Capped rate: 20% requested, capped at 12%
    cap = StatutoryEnforcementEngine.calculate_sales_tax(2500.00, 0.20, mock_laws)
    assert cap["effectiveRate"] == 0.12
    assert cap["wasCapped"] is True
    assert cap["taxAmount"] == 300.00
    assert cap["grossTotal"] == 2800.00
    assert cap["isConserved"] is True

    # Fractional cent rounding check: 99.99 with 8.5% tax
    odd = StatutoryEnforcementEngine.calculate_sales_tax(99.99, 0.085, mock_laws)
    assert odd["isConserved"] is True
    assert abs(odd["grossTotal"] - (odd["subtotal"] + odd["taxAmount"])) < 0.0001


def test_zoning_policy_adjustments():
    """Verify commercial rebate and industrial environmental surcharges."""
    mock_laws = {
        "zoning:commercial_tax_rebate": {"id": "zoning:commercial_tax_rebate", "currentValue": {"rebate": 0.02}},
        "zoning:industrial_environmental_surcharge": {"id": "zoning:industrial_environmental_surcharge", "currentValue": {"surcharge": 0.03}},
    }

    comm = StatutoryEnforcementEngine.evaluate_zoning_policy("retail_storefront", 0.08, mock_laws)
    assert round(comm["netRate"], 4) == 0.0600
    assert round(comm["adjustmentPct"], 4) == -0.0200

    ind = StatutoryEnforcementEngine.evaluate_zoning_policy("industrial_warehouse", 0.08, mock_laws)
    assert round(ind["netRate"], 4) == 0.1100
    assert round(ind["adjustmentPct"], 4) == 0.0300

    gen = StatutoryEnforcementEngine.evaluate_zoning_policy("general", 0.08, mock_laws)
    assert round(gen["netRate"], 4) == 0.0800
    assert round(gen["adjustmentPct"], 4) == 0.0000


def test_statutory_bill_proposal_actions_validation():
    """Verify validation of structured bill actions against constitutional bounds."""
    mock_laws = {
        "speed:highway": {"id": "speed:highway", "currentValue": {"mph": 75}, "minAllowed": {"mph": 55}, "maxAllowed": {"mph": 100}},
        "speed:urban": {"id": "speed:urban", "currentValue": {"mph": 45}, "minAllowed": {"mph": 25}, "maxAllowed": {"mph": 65}},
        "tax:sales_cap": {"id": "tax:sales_cap", "currentValue": {"rate": 0.12}, "minAllowed": {"rate": 0.05}, "maxAllowed": {"rate": 0.20}},
        "penal:speeding_minor": {"id": "penal:speeding_minor", "currentValue": {"fine": 250}, "minAllowed": {"fine": 50}, "maxAllowed": {"fine": 1000}},
    }

    # Valid multi-action proposal
    valid_actions = [
        {"targetLawId": "speed:highway", "field": "mph", "newValue": 80},
        {"targetLawId": "tax:sales_cap", "field": "rate", "newValue": 0.15},
        {"targetLawId": "penal:speeding_minor", "field": "fine", "newValue": 350},
    ]
    ok_val, clean_acts = StatutoryEnforcementEngine.validate_statutory_bill_actions(valid_actions, mock_laws)
    assert ok_val is True
    assert len(clean_acts) == 3

    # Out of bounds speed (> 65 on urban)
    bad_speed = [{"targetLawId": "speed:urban", "field": "mph", "newValue": 140}]
    ok_speed, err_speed = StatutoryEnforcementEngine.validate_statutory_bill_actions(bad_speed, mock_laws)
    assert ok_speed is False
    assert "STATUTORY_VALUE_OUT_OF_BOUNDS" in err_speed

    # Out of bounds tax cap (> 0.20)
    bad_tax = [{"targetLawId": "tax:sales_cap", "field": "rate", "newValue": 0.75}]
    ok_tax, err_tax = StatutoryEnforcementEngine.validate_statutory_bill_actions(bad_tax, mock_laws)
    assert ok_tax is False
    assert "STATUTORY_VALUE_OUT_OF_BOUNDS" in err_tax

    # Invalid non-mutable field
    bad_field = [{"targetLawId": "speed:urban", "field": "arbitrary_field", "newValue": 50}]
    ok_field, err_field = StatutoryEnforcementEngine.validate_statutory_bill_actions(bad_field, mock_laws)
    assert ok_field is False
    assert "FIELD_NOT_CONSTITUTIONALLY_MUTABLE" in err_field


def test_3d_euclidean_radar_zone_spatial_gating():
    """Verify 3D Euclidean spatial distance calculation and radar zone gating."""
    radar_coords = {"x": 312.4, "y": 182.5, "z": 103.8}
    inside_pt = {"x": 320.0, "y": 190.0, "z": 103.8}
    outside_pt = {"x": 600.0, "y": 500.0, "z": 103.8}

    in_zone, dist_in = StatutoryEnforcementEngine.is_point_in_radar_zone(inside_pt, radar_coords, 150.0)
    assert in_zone is True
    assert dist_in <= 150.0

    out_zone, dist_out = StatutoryEnforcementEngine.is_point_in_radar_zone(outside_pt, radar_coords, 150.0)
    assert out_zone is False
    assert dist_out > 150.0


def test_dispatch_warning_overlay_formatting_and_uuid():
    """Verify MDT warning overlay formatting, badge styling, and unique serial generation."""
    warning = {
        "id": "wrn-test-01",
        "category": "speeding_anpr",
        "severity": "critical",
        "title": "TRAFFIPAX: Vinewood Blvd (95.0 / 45.0 mph)",
        "location_label": "Vinewood Boulevard Speed Trap",
        "status": "active",
    }

    fmt = StatutoryEnforcementEngine.format_warning_overlay(warning)
    assert fmt["badgeClass"] == "badge-danger"
    assert fmt["icon"] == "fa-tachometer-alt"
    assert fmt["severity"] == "critical"
    assert "Vinewood" in fmt["locationLabel"]

    uuid1 = StatutoryEnforcementEngine.generate_warning_uuid()
    uuid2 = StatutoryEnforcementEngine.generate_warning_uuid()
    assert uuid1.startswith("wrn-")
    assert uuid2.startswith("wrn-")
    assert uuid1 != uuid2
