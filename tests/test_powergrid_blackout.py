"""
Unit tests for municipal power grid substation failure & blackout simulation
(nyx_services).
"""

import math
import pytest


class MockSubstation:
    def __init__(self, sub_id, label, coords, radius, fuel_level=100.0, condition_health=100.0,
                 is_blackout=False, failure_reason=None, breaker_tripped=False, peak_load_mw=45.0):
        self.id = sub_id
        self.label = label
        self.coords = coords
        self.radius = radius
        self.fuel_level = fuel_level
        self.condition_health = condition_health
        self.is_blackout = is_blackout
        self.failure_reason = failure_reason
        self.breaker_tripped = breaker_tripped
        self.peak_load_mw = peak_load_mw
        self.blackout_started_at = None
        self.total_blackouts_count = 0


class PowerGridEngine:
    def __init__(self, config=None):
        self.config = config or {
            "FuelConsumptionPerMinute": 0.50,
            "HealthDegradationPerMinute": 0.15,
            "BlackoutFuelThreshold": 0.00,
            "BlackoutHealthThreshold": 10.00,
            "CriticalWarningThreshold": 20.00,
            "MaxRatedCapacityMw": 75.00,
            "FuelDrumRefuelAmount": 25.00,
            "RepairKitRestoreAmount": 30.00,
        }
        self.substations = {}
        self.blackout_logs = []
        self.logistics_contracts = []

    def register_substation(self, sub: MockSubstation):
        self.substations[sub.id] = sub

    def evaluate_substation_state(self, s: MockSubstation):
        fuel_thresh = self.config["BlackoutFuelThreshold"]
        health_thresh = self.config["BlackoutHealthThreshold"]

        should_blackout = (s.fuel_level <= fuel_thresh or
                           s.condition_health <= health_thresh or
                           s.breaker_tripped)

        if should_blackout and not s.is_blackout:
            s.is_blackout = True
            s.total_blackouts_count += 1
            if not s.failure_reason:
                if s.fuel_level <= fuel_thresh:
                    s.failure_reason = "fuel_exhaustion"
                elif s.condition_health <= health_thresh:
                    s.failure_reason = "mechanical_breakdown"
                elif s.breaker_tripped:
                    s.failure_reason = "overload_trip"
                else:
                    s.failure_reason = "unknown_failure"
            
            # Record audit log
            self.blackout_logs.append({
                "substation_id": s.id,
                "reason": s.failure_reason,
                "status": "active"
            })

            # Check and trigger emergency logistics restock contracts
            self.check_emergency_logistics(s)

        elif not should_blackout and s.is_blackout:
            s.is_blackout = False
            s.failure_reason = None
            s.breaker_tripped = False
            # Close active log
            for log in reversed(self.blackout_logs):
                if log["substation_id"] == s.id and log["status"] == "active":
                    log["status"] = "resolved"
                    break

        return s.is_blackout

    def check_emergency_logistics(self, s: MockSubstation):
        crit_thresh = self.config["CriticalWarningThreshold"]
        dest_shelf_id = f"substation:{s.id}"

        # If low on fuel, generate fuel contract if not already active
        if s.fuel_level <= crit_thresh:
            existing = any(c["dest_shelf_id"] == dest_shelf_id and c["item_id"] == "industrial_fuel" and c["status"] == "available" for c in self.logistics_contracts)
            if not existing:
                self.logistics_contracts.append({
                    "dest_shelf_id": dest_shelf_id,
                    "item_id": "industrial_fuel",
                    "quantity": 4,
                    "payout_per_unit": 200.0,
                    "status": "available"
                })

        # If damaged, generate repair kit contract
        if s.condition_health <= crit_thresh:
            existing = any(c["dest_shelf_id"] == dest_shelf_id and c["item_id"] == "tool_repairkit" and c["status"] == "available" for c in self.logistics_contracts)
            if not existing:
                self.logistics_contracts.append({
                    "dest_shelf_id": dest_shelf_id,
                    "item_id": "tool_repairkit",
                    "quantity": 3,
                    "payout_per_unit": 250.0,
                    "status": "available"
                })

    def trigger_substation_failure(self, sub_id: str, reason: str = "sabotage"):
        s = self.substations.get(sub_id)
        if not s:
            return False, "SUBSTATION_NOT_FOUND"

        s.breaker_tripped = True
        s.failure_reason = reason
        self.evaluate_substation_state(s)
        return True, s

    def reset_circuit_breaker(self, sub_id: str):
        s = self.substations.get(sub_id)
        if not s:
            return False, "SUBSTATION_NOT_FOUND"

        if not s.breaker_tripped and not s.is_blackout:
            return False, "BREAKER_NOT_TRIPPED"

        fuel_thresh = self.config["BlackoutFuelThreshold"]
        health_thresh = self.config["BlackoutHealthThreshold"]

        if s.fuel_level <= fuel_thresh:
            return False, "CANNOT_RESET_FUEL_DEPLETED"

        if s.condition_health <= health_thresh:
            return False, "CANNOT_RESET_CRITICAL_DAMAGE"

        s.breaker_tripped = False
        s.failure_reason = None
        self.evaluate_substation_state(s)
        return True, s

    def simulate_grid_overload(self, sub_id: str, spike_mw: float):
        s = self.substations.get(sub_id)
        if not s:
            return False, "SUBSTATION_NOT_FOUND"

        total_load = s.peak_load_mw + spike_mw
        max_capacity = self.config["MaxRatedCapacityMw"]

        if total_load > max_capacity:
            s.condition_health = max(0.0, s.condition_health - 15.0)
            s.breaker_tripped = True
            s.failure_reason = "overload_trip"
            self.evaluate_substation_state(s)
            return True, {"tripped": True, "load": total_load, "capacity": max_capacity}

        return True, {"tripped": False, "load": total_load, "capacity": max_capacity}

    def refuel_substation(self, sub_id: str, amount: float = None):
        s = self.substations.get(sub_id)
        if not s:
            return False, "SUBSTATION_NOT_FOUND"

        if s.fuel_level >= 100.0:
            return False, "FUEL_TANK_FULL"

        amt = amount or self.config["FuelDrumRefuelAmount"]
        s.fuel_level = min(100.0, s.fuel_level + amt)

        # Fulfill open fuel contract if restored above critical
        if s.fuel_level > self.config["CriticalWarningThreshold"]:
            dest_shelf_id = f"substation:{s.id}"
            for c in self.logistics_contracts:
                if c["dest_shelf_id"] == dest_shelf_id and c["item_id"] == "industrial_fuel" and c["status"] == "available":
                    c["status"] = "fulfilled"

        self.evaluate_substation_state(s)
        return True, s.fuel_level

    def repair_substation(self, sub_id: str, amount: float = None):
        s = self.substations.get(sub_id)
        if not s:
            return False, "SUBSTATION_NOT_FOUND"

        if s.condition_health >= 100.0:
            return False, "MAINTENANCE_OPTIMAL"

        amt = amount or self.config["RepairKitRestoreAmount"]
        s.condition_health = min(100.0, s.condition_health + amt)

        # Fulfill open repair contract if restored above critical
        if s.condition_health > self.config["CriticalWarningThreshold"]:
            dest_shelf_id = f"substation:{s.id}"
            for c in self.logistics_contracts:
                if c["dest_shelf_id"] == dest_shelf_id and c["item_id"] == "tool_repairkit" and c["status"] == "available":
                    c["status"] = "fulfilled"

        self.evaluate_substation_state(s)
        return True, s.condition_health

    def is_coords_powered(self, coords: tuple):
        x, y, z = coords
        for s in self.substations.values():
            dist = math.sqrt((x - s.coords[0])**2 + (y - s.coords[1])**2)
            if dist <= s.radius:
                if s.is_blackout:
                    return False, s.id
        return True, None

    def get_diagnostics(self, sub_id: str):
        s = self.substations.get(sub_id)
        if not s:
            return None

        burn_rate = self.config["FuelConsumptionPerMinute"]
        est_hours = (s.fuel_level / burn_rate) / 60.0 if burn_rate > 0 else 999.0

        status = "BLACKOUT" if s.is_blackout else ("WARNING" if (s.fuel_level <= 30 or s.condition_health <= 30) else "OPTIMAL")

        return {
            "substation_id": s.id,
            "label": s.label,
            "status": status,
            "fuel_level": s.fuel_level,
            "condition_health": s.condition_health,
            "is_blackout": s.is_blackout,
            "breaker_tripped": s.breaker_tripped,
            "failure_reason": s.failure_reason,
            "estimated_runtime_hours": round(est_hours, 2),
            "peak_load_mw": s.peak_load_mw,
            "total_blackouts_count": s.total_blackouts_count
        }


# ==============================================================================
# PYTEST TEST CASES
# ==============================================================================

def test_substation_degradation_and_automatic_blackout():
    engine = PowerGridEngine()
    sub = MockSubstation("grid_central", "Central Substation", (711.5, -963.2, 30.4), 1600.0, fuel_level=1.0, condition_health=50.0)
    engine.register_substation(sub)

    assert sub.is_blackout is False
    assert engine.is_coords_powered((711.5, -963.2, 30.4)) == (True, None)

    # Burn remaining fuel to 0.0%
    sub.fuel_level = 0.0
    engine.evaluate_substation_state(sub)

    assert sub.is_blackout is True
    assert sub.failure_reason == "fuel_exhaustion"
    assert sub.total_blackouts_count == 1
    powered, failed_sub = engine.is_coords_powered((711.5, -963.2, 30.4))
    assert powered is False
    assert failed_sub == "grid_central"


def test_substation_mechanical_failure_threshold():
    engine = PowerGridEngine()
    sub = MockSubstation("grid_port", "Port Substation", (1072.0, -2006.0, 31.5), 1800.0, fuel_level=80.0, condition_health=10.0)
    engine.register_substation(sub)

    engine.evaluate_substation_state(sub)
    assert sub.is_blackout is True
    assert sub.failure_reason == "mechanical_breakdown"


def test_manual_failure_trigger_and_audit_log():
    engine = PowerGridEngine()
    sub = MockSubstation("grid_rockford", "Rockford Substation", (-1440.0, -250.0, 48.0), 2000.0)
    engine.register_substation(sub)

    ok, res = engine.trigger_substation_failure("grid_rockford", "sabotage")
    assert ok is True
    assert sub.is_blackout is True
    assert sub.breaker_tripped is True
    assert sub.failure_reason == "sabotage"
    assert len(engine.blackout_logs) == 1
    assert engine.blackout_logs[0]["reason"] == "sabotage"


def test_circuit_breaker_reset_mechanics():
    engine = PowerGridEngine()
    sub = MockSubstation("grid_sandy", "Sandy Substation", (2732.0, 1572.0, 24.5), 2500.0, fuel_level=0.0, condition_health=80.0)
    engine.register_substation(sub)
    engine.trigger_substation_failure("grid_sandy", "overload_trip")

    # Attempt to reset breaker with 0 fuel: MUST FAIL
    ok, err = engine.reset_circuit_breaker("grid_sandy")
    assert ok is False
    assert err == "CANNOT_RESET_FUEL_DEPLETED"
    assert sub.is_blackout is True

    # Refuel substation
    refuel_ok, new_fuel = engine.refuel_substation("grid_sandy", 50.0)
    assert refuel_ok is True
    assert new_fuel == 50.0

    # Reset breaker with fuel restored: MUST SUCCEED
    reset_ok, res = engine.reset_circuit_breaker("grid_sandy")
    assert reset_ok is True
    assert sub.breaker_tripped is False
    assert sub.is_blackout is False
    assert engine.blackout_logs[-1]["status"] == "resolved"


def test_grid_overload_simulation():
    engine = PowerGridEngine()
    sub = MockSubstation("grid_paleto", "Paleto Substation", (140.0, 6600.0, 31.8), 2200.0, peak_load_mw=50.0)
    engine.register_substation(sub)

    # Moderate spike (15 MW -> total 65 MW <= 75 MW rated capacity)
    ok, res1 = engine.simulate_grid_overload("grid_paleto", 15.0)
    assert ok is True
    assert res1["tripped"] is False
    assert sub.is_blackout is False

    # Massive surge (30 MW -> total 80 MW > 75 MW capacity): Breaker trips!
    ok, res2 = engine.simulate_grid_overload("grid_paleto", 30.0)
    assert ok is True
    assert res2["tripped"] is True
    assert sub.is_blackout is True
    assert sub.breaker_tripped is True
    assert sub.failure_reason == "overload_trip"


def test_emergency_logistics_contract_generation_on_failure():
    engine = PowerGridEngine()
    sub = MockSubstation("grid_central", "Central Substation", (711.5, -963.2, 30.4), 1600.0, fuel_level=15.0, condition_health=10.0)
    engine.register_substation(sub)

    engine.evaluate_substation_state(sub)
    assert sub.is_blackout is True

    # Both fuel and repair kit emergency contracts should be created
    fuel_contract = next((c for c in engine.logistics_contracts if c["item_id"] == "industrial_fuel"), None)
    repair_contract = next((c for c in engine.logistics_contracts if c["item_id"] == "tool_repairkit"), None)

    assert fuel_contract is not None
    assert fuel_contract["status"] == "available"
    assert repair_contract is not None
    assert repair_contract["status"] == "available"

    # Refuel substation above 20%
    engine.refuel_substation("grid_central", 50.0)
    assert fuel_contract["status"] == "fulfilled"


def test_substation_diagnostics_telemetry():
    engine = PowerGridEngine()
    sub = MockSubstation("grid_central", "Central Substation", (711.5, -963.2, 30.4), 1600.0, fuel_level=60.0, condition_health=85.0)
    engine.register_substation(sub)

    diag = engine.get_diagnostics("grid_central")
    assert diag is not None
    assert diag["substation_id"] == "grid_central"
    assert diag["status"] == "OPTIMAL"
    assert diag["fuel_level"] == 60.0
    assert diag["condition_health"] == 85.0
    assert diag["is_blackout"] is False
    assert diag["estimated_runtime_hours"] == 2.0  # 60 / 0.5 = 120 mins = 2.0 hrs
