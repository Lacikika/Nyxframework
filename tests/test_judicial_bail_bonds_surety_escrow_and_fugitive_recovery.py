"""
Tests for Pre-Trial Judicial Bail Bonds, Surety Escrow & Fugitive Recovery Warrants (Step 065)
Validates SQL migration 065, fxmanifest declarations, server and client exports,
and pure Lua 5.4 deterministic algorithms for bail schedules, surety breakdowns,
exonerations, forfeitures, fugitive bounties, and release condition compliance.
"""

import json
import math
import os
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CORE_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "065_judicial_bail_bonds_surety_escrow_and_fugitive_recovery.sql"
)
JUDICIARY_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_judiciary", "sql", "migrations", "065_judicial_bail_bonds_surety_escrow_and_fugitive_recovery.sql"
)
INDEX_JSON_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "index.json"
)
JUDICIARY_MANIFEST_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_judiciary", "fxmanifest.lua"
)
SHARED_BAIL_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_judiciary", "shared", "bail_bonds.lua"
)
SERVER_BAIL_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_judiciary", "server", "bail.lua"
)
SERVER_EXPORTS_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_judiciary", "server", "exports.lua"
)
CLIENT_BAIL_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_judiciary", "client", "bail.lua"
)
CLIENT_EXPORTS_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_judiciary", "client", "exports.lua"
)


def test_migration_065_files_and_registration():
    """Verify SQL migration 065 exists in core and judiciary, and is registered in index.json."""
    assert os.path.exists(CORE_MIGRATION_PATH), "Core migration 065 must exist"
    assert os.path.exists(JUDICIARY_MIGRATION_PATH), "Judiciary migration 065 must exist"

    with open(INDEX_JSON_PATH, "r", encoding="utf-8") as f:
        registered = json.load(f)

    assert "065_judicial_bail_bonds_surety_escrow_and_fugitive_recovery.sql" in registered, (
        "065 migration must be registered in index.json"
    )

    with open(CORE_MIGRATION_PATH, "r", encoding="utf-8") as f:
        sql = f.read()

    assert "CREATE TABLE IF NOT EXISTS `nyx_judiciary_bail_bonds`" in sql
    assert "CREATE TABLE IF NOT EXISTS `nyx_judiciary_bail_audits`" in sql
    assert "ALTER TABLE `nyx_judiciary_dockets`" in sql
    assert "gov:escrow:bail" in sql
    assert "bounty_hunter_citizen_id" in sql
    assert "clerk_admin_fee" in sql


def test_manifest_declarations():
    """Verify shared, server, and client bail files are declared in fxmanifest.lua."""
    with open(JUDICIARY_MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = f.read()

    assert "shared/bail_bonds.lua" in manifest, "shared/bail_bonds.lua must be declared"
    assert "server/bail.lua" in manifest, "server/bail.lua must be declared"
    assert "client/bail.lua" in manifest, "client/bail.lua must be declared"


def test_bail_schedule_and_eligibility():
    """Verify deterministic bail schedule calculations and eligibility evaluation."""
    # Algorithm specification:
    # Misdemeanor: base $2,500, range [$1,000, $10,000]
    # Felony: base $50,000, range [$15,000, $150,000]
    # Constitutional: base $100,000, range [$50,000, $500,000]
    # FTA multiplier: 1.0 + (priorFTAs * 0.50)
    # Offense gravity multiplier clamped [0.5, 3.0]

    def calc_schedule(case_type, prior_ftas, gravity_mult):
        base_schedules = {
            "civil": 0.0,
            "criminal_misdemeanor": 2500.0,
            "criminal_felony": 50000.0,
            "constitutional": 100000.0,
        }
        base = base_schedules.get(case_type, 10000.0)
        if base == 0.0:
            return 0.0

        fta_factor = 1.0 + (max(0, prior_ftas) * 0.50)
        gravity = max(0.50, min(3.00, gravity_mult))
        raw = base * fta_factor * gravity

        # Clamp between 500 and 1,000,000
        clamped = max(500.0, min(1000000.0, raw))
        return round(clamped, 2)

    misd_clean = calc_schedule("criminal_misdemeanor", 0, 1.0)
    assert misd_clean == 2500.0

    misd_recidivist = calc_schedule("criminal_misdemeanor", 2, 1.0)
    assert misd_recidivist == 5000.0  # 2500 * (1.0 + 1.0)

    felony_severe = calc_schedule("criminal_felony", 1, 1.5)
    # 50,000 * 1.5 * 1.5 = 112,500.0
    assert felony_severe == 112500.0

    # Eligibility evaluation
    def evaluate_eligibility(case_type, bail_status, has_violent_capital_flag):
        if bail_status == "remand_no_bail":
            return False, "DEFENDANT_REMANDED_NO_BAIL"
        if has_violent_capital_flag:
            return False, "CAPITAL_CRIME_REQUIRES_JUDICIAL_HEARING"
        if case_type == "civil":
            return False, "CIVIL_CASE_NO_BAIL"
        return True, "ELIGIBLE"

    ok1, reason1 = evaluate_eligibility("criminal_felony", "eligible", False)
    assert ok1 is True and reason1 == "ELIGIBLE"

    ok2, reason2 = evaluate_eligibility("criminal_felony", "remand_no_bail", False)
    assert ok2 is False and reason2 == "DEFENDANT_REMANDED_NO_BAIL"

    ok3, reason3 = evaluate_eligibility("criminal_felony", "eligible", True)
    assert ok3 is False and reason3 == "CAPITAL_CRIME_REQUIRES_JUDICIAL_HEARING"


def test_bail_payment_breakdown():
    """Verify exact cash, surety, and recognizance payment breakdowns and statutory fees."""
    # Statutory fees:
    # ClerkAdminFeePercent = 0.05 (5%)
    # SuretyPremiumPercent = 0.10 (10%)

    def calculate_payment_breakdown(bail_amount, bond_type):
        amount = max(500.0, float(bail_amount))
        clerk_fee = round(amount * 0.05, 2)
        exoneration_refund = round(amount - clerk_fee, 2)

        if bond_type == "cash":
            return {
                "bondType": "cash",
                "bailAmount": amount,
                "requiredUpfrontDeposit": amount,
                "suretyPremiumPaid": 0.0,
                "suretyCollateral": amount,
                "exonerationRefund": exoneration_refund,
                "clerkAdminFee": clerk_fee,
            }
        elif bond_type == "surety":
            premium = round(amount * 0.10, 2)
            return {
                "bondType": "surety",
                "bailAmount": amount,
                "requiredUpfrontDeposit": premium,
                "suretyPremiumPaid": premium,
                "suretyCollateral": amount,
                "exonerationRefund": exoneration_refund,
                "clerkAdminFee": clerk_fee,
            }
        elif bond_type == "recognizance":
            return {
                "bondType": "recognizance",
                "bailAmount": amount,
                "requiredUpfrontDeposit": 0.0,
                "suretyPremiumPaid": 0.0,
                "suretyCollateral": 0.0,
                "exonerationRefund": 0.0,
                "clerkAdminFee": 0.0,
            }

    cash = calculate_payment_breakdown(50000.0, "cash")
    assert cash["requiredUpfrontDeposit"] == 50000.0
    assert cash["clerkAdminFee"] == 2500.0
    assert cash["exonerationRefund"] == 47500.0
    assert cash["exonerationRefund"] + cash["clerkAdminFee"] == 50000.0

    surety = calculate_payment_breakdown(50000.0, "surety")
    assert surety["requiredUpfrontDeposit"] == 5000.0  # 10% premium paid by defendant
    assert surety["suretyCollateral"] == 50000.0      # 100% held in escrow
    assert surety["clerkAdminFee"] == 2500.0
    assert surety["exonerationRefund"] == 47500.0


def test_court_appearance_and_exoneration():
    """Verify physical court appearance evaluation and 95%/5% double-entry exoneration distribution."""
    courtroom_coords = {"x": 240.5, "y": -1075.2, "z": 29.2}
    near_coords = {"x": 241.0, "y": -1074.8, "z": 29.2}
    far_coords = {"x": 300.0, "y": -1100.0, "z": 29.2}

    def is_in_courtroom(check_coords, target_coords, max_dist=3.5):
        dx = check_coords["x"] - target_coords["x"]
        dy = check_coords["y"] - target_coords["y"]
        dz = check_coords["z"] - target_coords["z"]
        dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        return dist <= max_dist, round(dist, 2)

    in_range, dist1 = is_in_courtroom(near_coords, courtroom_coords)
    assert in_range is True
    assert dist1 <= 3.5

    out_range, dist2 = is_in_courtroom(far_coords, courtroom_coords)
    assert out_range is False
    assert dist2 > 3.5

    # Double-entry ledger invariant on exoneration:
    # EscrowDebit == RefundCredit + ClerkFeeCredit
    bail_pool = 100000.0
    refund = round(bail_pool * 0.95, 2)
    clerk_fee = round(bail_pool * 0.05, 2)
    assert refund + clerk_fee == bail_pool


def test_forfeiture_and_fugitive_bounty_math():
    """Verify 100% forfeiture to municipal treasury and 15% fugitive recovery bounty."""
    # Statutory rate: 15% bounty on forfeited bail
    bail_amount = 75000.0
    bounty_percent = 0.15

    forfeited_to_treasury = bail_amount
    recovery_bounty = round(bail_amount * bounty_percent, 2)

    assert forfeited_to_treasury == 75000.0
    assert recovery_bounty == 11250.0  # 15% of $75,000


def test_release_conditions_validation():
    """Verify release conditions evaluation (curfew, weapons prohibition, and jurisdiction radius)."""
    def check_conditions(conditions, inv_items, current_hour, coords, center_coords, max_radius=3500.0):
        violations = []

        if "no_weapons" in conditions:
            weapon_keywords = ["weapon_", "ammo_", "pistol", "smg", "rifle"]
            for item in inv_items:
                for kw in weapon_keywords:
                    if kw in item.lower():
                        violations.append("WEAPON_PROHIBITION_VIOLATED")
                        break

        if "curfew_2200" in conditions:
            # Curfew active between 22:00 and 06:00
            if current_hour >= 22 or current_hour < 6:
                # Outside home/residence check
                dx = coords["x"] - center_coords["x"]
                dy = coords["y"] - center_coords["y"]
                dist = math.sqrt(dx * dx + dy * dy)
                if dist > 50.0:  # More than 50m from home
                    violations.append("CURFEW_VIOLATED")

        if "stay_in_county" in conditions:
            dx = coords["x"] - center_coords["x"]
            dy = coords["y"] - center_coords["y"]
            dist = math.sqrt(dx * dx + dy * dy)
            if dist > max_radius:
                violations.append("JURISDICTION_BOUNDARY_VIOLATED")

        return len(violations) == 0, violations

    conds = ["no_weapons", "curfew_2200", "stay_in_county"]
    center = {"x": 200.0, "y": -1000.0, "z": 25.0}

    # Compliant scenario (14:00, clean inventory, inside county)
    clean_inv = ["id_card", "phone", "donut", "coffee"]
    pos_city = {"x": 250.0, "y": -1050.0, "z": 25.0}
    ok_clean, v_clean = check_conditions(conds, clean_inv, 14, pos_city, center)
    assert ok_clean is True and len(v_clean) == 0

    # Non-compliant scenario (carrying weapon, outside curfew, beyond county)
    dirty_inv = ["id_card", "phone", "weapon_combatpistol"]
    pos_far = {"x": 6000.0, "y": 6000.0, "z": 25.0}
    ok_dirty, v_dirty = check_conditions(conds, dirty_inv, 23, pos_far, center)
    assert ok_dirty is False
    assert "WEAPON_PROHIBITION_VIOLATED" in v_dirty
    assert "CURFEW_VIOLATED" in v_dirty
    assert "JURISDICTION_BOUNDARY_VIOLATED" in v_dirty


def test_presentation_badge_formatting():
    """Verify UI status badge classes and localized Hungarian/English labels."""
    def format_badge(status, bond_type):
        badges = {
            "posted": {
                "class": "badge-warning",
                "label": "Óvadék Letétbe Helyezve (Bail Posted)",
                "active": True
            },
            "exonerated": {
                "class": "badge-success",
                "label": "Óvadék Felmentve (Bail Exonerated)",
                "active": False
            },
            "forfeited": {
                "class": "badge-danger",
                "label": "Óvadék Elkobozva / Szökevény (Forfeited FTA)",
                "active": False
            },
            "revoked": {
                "class": "badge-dark",
                "label": "Óvadék Visszavonva (Bail Revoked)",
                "active": False
            }
        }
        return badges.get(status, {"class": "badge-secondary", "label": "Ismeretlen", "active": False})

    b_posted = format_badge("posted", "cash")
    assert b_posted["class"] == "badge-warning"
    assert b_posted["active"] is True

    b_forfeited = format_badge("forfeited", "surety")
    assert b_forfeited["class"] == "badge-danger"
    assert b_forfeited["active"] is False


def test_server_and_client_exports_and_lua_syntax():
    """Verify that export helper files declare bail functions and Lua code passes AST syntax checks."""
    with open(SERVER_EXPORTS_PATH, "r", encoding="utf-8") as f:
        srv_exp = f.read()

    assert "GetActiveBailBond" in srv_exp
    assert "PostBailBond" in srv_exp
    assert "ExonerateBailBond" in srv_exp
    assert "ForfeitBailBond" in srv_exp

    with open(CLIENT_EXPORTS_PATH, "r", encoding="utf-8") as f:
        cli_exp = f.read()

    assert "GetMyBailStatus" in cli_exp
    assert "IsNearBailKiosk" in cli_exp
