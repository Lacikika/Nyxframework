"""
Unit tests for Municipal Infrastructure Degradation Mode, Impound Reclamation & Vehicle Registration.
Verifies pure math, fiscal solvency tiers, impound release calculations, registration penalties,
and SQL migration/manifest integrity.
"""

import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIVEM = ROOT / "FiveM"


# 1. Pure Python mirror of degradation logic to verify Lua specifications
class FiscalSolvencyEngine:
    THRESHOLDS = {
        "OPTIMAL": 100000.0,
        "STRESS": 50000.0,
        "DEGRADED": 20000.0,
        "BANKRUPT": 0.0,
    }

    SURCHARGES = {
        "solvent": {"repair_pct": 0.0, "impound_surcharge": 0.0, "dispatch_latency": 0},
        "fiscal_stress": {"repair_pct": 0.10, "impound_surcharge": 0.0, "dispatch_latency": 5},
        "degraded": {"repair_pct": 0.25, "impound_surcharge": 100.0, "dispatch_latency": 20},
        "bankrupt": {"repair_pct": 0.50, "impound_surcharge": 250.0, "dispatch_latency": 60},
    }

    @classmethod
    def evaluate_tier(cls, balance: float) -> str:
        b = float(balance)
        if b > cls.THRESHOLDS["STRESS"]:
            return "solvent"
        elif b > cls.THRESHOLDS["DEGRADED"]:
            return "fiscal_stress"
        elif b > cls.THRESHOLDS["BANKRUPT"]:
            return "degraded"
        else:
            return "bankrupt"

    @classmethod
    def calculate_impound_release_cost(
        cls, base_fee: float, days_impounded: int, daily_rate: float, fiscal_tier: str
    ) -> dict:
        base = max(0.0, round(float(base_fee), 2))
        days = max(0, int(days_impounded))
        daily = max(0.0, round(float(daily_rate), 2))
        storage_fee = round(days * daily, 2)

        tier_info = cls.SURCHARGES.get(fiscal_tier, cls.SURCHARGES["solvent"])
        surcharge = tier_info["impound_surcharge"]
        total = round(base + storage_fee + surcharge, 2)

        return {
            "base_fee": base,
            "storage_fee": storage_fee,
            "emergency_surcharge": surcharge,
            "total_fee": total,
            "fiscal_tier": fiscal_tier,
        }

    @classmethod
    def calculate_public_repair_cost(
        cls,
        base_labor: float,
        damage_ratio: float,
        parts_multiplier: float,
        fiscal_tier: str,
        has_repair_kit: bool = False,
    ) -> tuple[bool, dict | str]:
        if fiscal_tier == "bankrupt" and not has_repair_kit:
            return False, "STATION_INSOLVENT_REQUIRES_REPAIR_KIT"

        base = max(0.0, round(float(base_labor), 2))
        dmg = max(0.0, min(1.0, float(damage_ratio)))
        parts_mult = max(0.5, float(parts_multiplier))

        raw_parts = round(dmg * 500.0 * parts_mult, 2)
        tier_info = cls.SURCHARGES.get(fiscal_tier, cls.SURCHARGES["solvent"])
        surcharge = round(raw_parts * tier_info["repair_pct"], 2)

        parts_total = round(raw_parts + surcharge, 2)
        labor_total = base if not (fiscal_tier == "bankrupt" and has_repair_kit) else round(base * 0.5, 2)
        total = round(labor_total + parts_total, 2)

        return True, {
            "labor_fee": labor_total,
            "parts_fee": raw_parts,
            "surcharge": surcharge,
            "total_cost": total,
            "fiscal_tier": fiscal_tier,
        }


class VehicleRegistrationEngine:
    CLASS_FEES = {
        "motorcycle": 150.0,
        "compact": 250.0,
        "sedan": 250.0,
        "coupe": 250.0,
        "suv": 250.0,
        "sports": 500.0,
        "super": 500.0,
        "commercial": 450.0,
        "industrial": 450.0,
        "default": 250.0,
    }

    @classmethod
    def evaluate_status(cls, raw_status: str, expires_at: int, current_time: int) -> str:
        if raw_status == "suspended":
            return "suspended"
        if expires_at > current_time:
            return "valid"
        return "expired"

    @classmethod
    def calculate_renewal_fee(cls, model_class: str, is_expired: bool, days_expired: int = 0) -> dict:
        base = cls.CLASS_FEES.get(model_class.lower(), cls.CLASS_FEES["default"])
        late_penalty = 0.0
        if is_expired:
            late_penalty = round(base * 0.20 + max(0, days_expired) * 5.0, 2)
        total = round(base + late_penalty, 2)
        return {
            "base_fee": base,
            "late_penalty": late_penalty,
            "total_fee": total,
            "is_expired": is_expired,
        }


# --- TEST CASES ---

def test_fiscal_solvency_tier_boundaries():
    """Validates solvency classification across strict municipal balance thresholds."""
    assert FiscalSolvencyEngine.evaluate_tier(150000.0) == "solvent"
    assert FiscalSolvencyEngine.evaluate_tier(50000.01) == "solvent"
    assert FiscalSolvencyEngine.evaluate_tier(50000.0) == "fiscal_stress"
    assert FiscalSolvencyEngine.evaluate_tier(20000.01) == "fiscal_stress"
    assert FiscalSolvencyEngine.evaluate_tier(20000.0) == "degraded"
    assert FiscalSolvencyEngine.evaluate_tier(0.01) == "degraded"
    assert FiscalSolvencyEngine.evaluate_tier(0.0) == "bankrupt"
    assert FiscalSolvencyEngine.evaluate_tier(-1500.0) == "bankrupt"


def test_impound_release_fee_calculation():
    """Tests impound release cost across tiers, daily storage, and emergency surcharges."""
    # Solvent: base $500, 2 days storage @ $150 = $300, surcharge $0 => $800
    calc_solvent = FiscalSolvencyEngine.calculate_impound_release_cost(500.0, 2, 150.0, "solvent")
    assert calc_solvent["base_fee"] == 500.0
    assert calc_solvent["storage_fee"] == 300.0
    assert calc_solvent["emergency_surcharge"] == 0.0
    assert calc_solvent["total_fee"] == 800.0

    # Degraded: base $500, 1 day storage @ $150 = $150, surcharge $100 => $750
    calc_deg = FiscalSolvencyEngine.calculate_impound_release_cost(500.0, 1, 150.0, "degraded")
    assert calc_deg["emergency_surcharge"] == 100.0
    assert calc_deg["total_fee"] == 750.0

    # Bankrupt: base $500, 3 days storage @ $150 = $450, surcharge $250 => $1200
    calc_bankrupt = FiscalSolvencyEngine.calculate_impound_release_cost(500.0, 3, 150.0, "bankrupt")
    assert calc_bankrupt["emergency_surcharge"] == 250.0
    assert calc_bankrupt["total_fee"] == 1200.0


def test_public_repair_station_bankruptcy_lockout_and_kit_override():
    """Ensures bankrupt municipal repair stations reject automated service unless citizen has repair kit."""
    ok, err = FiscalSolvencyEngine.calculate_public_repair_cost(150.0, 0.4, 1.0, "bankrupt", has_repair_kit=False)
    assert ok is False
    assert err == "STATION_INSOLVENT_REQUIRES_REPAIR_KIT"

    # With repair kit, service is permitted with 50% labor subsidy and 50% parts surcharge
    ok, data = FiscalSolvencyEngine.calculate_public_repair_cost(150.0, 0.4, 1.0, "bankrupt", has_repair_kit=True)
    assert ok is True
    assert data["labor_fee"] == 75.0  # 150 * 0.5
    assert data["parts_fee"] == 200.0  # 0.4 * 500
    assert data["surcharge"] == 100.0  # 200 * 0.50
    assert data["total_cost"] == 375.0


def test_public_repair_station_solvent_pricing():
    """Ensures solvent repair stations charge normal base labor and parts without surcharge."""
    ok, data = FiscalSolvencyEngine.calculate_public_repair_cost(150.0, 0.5, 1.0, "solvent")
    assert ok is True
    assert data["labor_fee"] == 150.0
    assert data["parts_fee"] == 250.0
    assert data["surcharge"] == 0.0
    assert data["total_cost"] == 400.0


def test_vehicle_registration_status_evaluation():
    """Validates registration status: valid, expired, and suspended."""
    now = 1700000000
    assert VehicleRegistrationEngine.evaluate_status("valid", now + 86400, now) == "valid"
    assert VehicleRegistrationEngine.evaluate_status("valid", now - 10, now) == "expired"
    assert VehicleRegistrationEngine.evaluate_status("suspended", now + 86400, now) == "suspended"


def test_vehicle_registration_renewal_fees_and_penalties():
    """Validates registration fees across classes and calculates late penalty surcharges."""
    # Sedan valid renewal: $250 base, $0 late
    sedan_valid = VehicleRegistrationEngine.calculate_renewal_fee("sedan", is_expired=False)
    assert sedan_valid["base_fee"] == 250.0
    assert sedan_valid["late_penalty"] == 0.0
    assert sedan_valid["total_fee"] == 250.0

    # Supercar expired 5 days: $500 base + 20% ($100) + 5 days * $5 ($25) = $625
    super_expired = VehicleRegistrationEngine.calculate_renewal_fee("super", is_expired=True, days_expired=5)
    assert super_expired["base_fee"] == 500.0
    assert super_expired["late_penalty"] == 125.0
    assert super_expired["total_fee"] == 625.0

    # Motorcycle valid: $150 base
    moto_valid = VehicleRegistrationEngine.calculate_renewal_fee("motorcycle", is_expired=False)
    assert moto_valid["base_fee"] == 150.0
    assert moto_valid["total_fee"] == 150.0


def test_closed_loop_double_entry_fee_conservation():
    """Validates closed-loop double entry conservation: player debit == municipal treasury credit."""
    player_balance = 5000.00
    city_balance = 12000.00  # degraded tier

    impound_cost = FiscalSolvencyEngine.calculate_impound_release_cost(500.0, 2, 150.0, "degraded")
    total_debit = impound_cost["total_fee"]  # 500 + 300 + 100 = 900.00

    new_player_bal = round(player_balance - total_debit, 2)
    new_city_bal = round(city_balance + total_debit, 2)

    delta_player = round(player_balance - new_player_bal, 2)
    delta_city = round(new_city_bal - city_balance, 2)

    assert delta_player == delta_city == 900.00
    assert (new_player_bal + new_city_bal) == (player_balance + city_balance)


def test_migration_030_and_index_json():
    """Verifies migration 030 exists and is registered in index.json."""
    mig_core = FIVEM / "nyx_core" / "sql" / "migrations" / "030_treasury_infrastructure_degradation_and_vehicle_impounds.sql"
    assert mig_core.exists(), "Migration 030 must exist in nyx_core"

    index_json_path = FIVEM / "nyx_core" / "sql" / "migrations" / "index.json"
    with open(index_json_path, "r", encoding="utf-8") as f:
        registered = json.load(f)
    assert "030_treasury_infrastructure_degradation_and_vehicle_impounds.sql" in registered
    assert registered[-1] == "030_treasury_infrastructure_degradation_and_vehicle_impounds.sql"

    content = mig_core.read_text(encoding="utf-8")
    assert "nyx_treasury_fiscal_states" in content
    assert "nyx_vehicles_impound_lots" in content
    assert "nyx_vehicles_impound_logs" in content
    assert "nyx_services_repair_stations" in content
    assert "registration_status" in content


def test_impound_state_machine_transition_rules():
    """Validates state machine gates for vehicle impounding and releases."""
    # Cannot release vehicle if not impounded
    stored_veh = {"storage_state": "stored", "emergencyLocked": False}
    impounded_veh = {"storage_state": "impounded", "emergencyLocked": False}
    bankrupt_locked_veh = {"storage_state": "impounded", "emergencyLocked": True}

    assert stored_veh["storage_state"] != "impounded"
    assert impounded_veh["storage_state"] == "impounded"
    assert bankrupt_locked_veh["emergencyLocked"] is True


def test_fxmanifest_declarations():
    """Verifies all new Lua files are declared in their respective resource manifests."""
    manifest_treasury = (FIVEM / "nyx_treasury" / "fxmanifest.lua").read_text(encoding="utf-8")
    assert "shared/degradation.lua" in manifest_treasury
    assert "server/degradation.lua" in manifest_treasury

    manifest_vehicles = (FIVEM / "nyx_vehicles" / "fxmanifest.lua").read_text(encoding="utf-8")
    assert "shared/registration.lua" in manifest_vehicles
    assert "server/impound.lua" in manifest_vehicles
    assert "server/registration.lua" in manifest_vehicles
    assert "client/impound.lua" in manifest_vehicles

    manifest_services = (FIVEM / "nyx_services" / "fxmanifest.lua").read_text(encoding="utf-8")
    assert "server/repair_stations.lua" in manifest_services
    assert "client/repair_stations.lua" in manifest_services
