"""
Unit tests for Physical Freight Pallets & Power-Dependent Industrial Assembly
(nyx_logistics / nyx_services / nyx_core).
"""

import math
import os
import json
import pytest

# ---------------------------------------------------------------------------
# Python Reference Implementations Mirroring Pure Lua 5.4 Algorithms
# ---------------------------------------------------------------------------

PALLET_MAX_WEIGHT = 1000000  # 1,000,000 grams = 1,000 kg
PALLET_MAX_SLOTS = 20        # 20 heavy slots

PALLET_MODELS = {
    "Empty": "prop_pallet_01a",
    "Light": "prop_boxpile_02b",
    "Medium": "prop_boxpile_05a",
    "Heavy": "prop_boxpile_06a"
}

VEHICLE_PROFILES = {
    "flatbed": {
        "name": "flatbed",
        "maxSlots": 3,
        "slots": {
            1: {"offset": {"x": 0.0, "y": -1.20, "z": 0.45}, "heading": 0.0, "bone": 0},
            2: {"offset": {"x": 0.0, "y": -2.80, "z": 0.45}, "heading": 0.0, "bone": 0},
            3: {"offset": {"x": 0.0, "y": -4.40, "z": 0.45}, "heading": 0.0, "bone": 0}
        }
    },
    "mule": {
        "name": "mule",
        "maxSlots": 2,
        "slots": {
            1: {"offset": {"x": 0.0, "y": -1.50, "z": 0.20}, "heading": 0.0, "bone": 0},
            2: {"offset": {"x": 0.0, "y": -3.20, "z": 0.20}, "heading": 0.0, "bone": 0}
        }
    },
    "benson": {
        "name": "benson",
        "maxSlots": 4,
        "slots": {
            1: {"offset": {"x": 0.0, "y": -1.00, "z": 0.30}, "heading": 0.0, "bone": 0},
            2: {"offset": {"x": 0.0, "y": -2.40, "z": 0.30}, "heading": 0.0, "bone": 0},
            3: {"offset": {"x": 0.0, "y": -3.80, "z": 0.30}, "heading": 0.0, "bone": 0},
            4: {"offset": {"x": 0.0, "y": -5.20, "z": 0.30}, "heading": 0.0, "bone": 0}
        }
    },
    "pounder": {
        "name": "pounder",
        "maxSlots": 6,
        "slots": {
            1: {"offset": {"x": -0.45, "y": -1.20, "z": 0.40}, "heading": 0.0, "bone": 0},
            2: {"offset": {"x": 0.45, "y": -1.20, "z": 0.40}, "heading": 0.0, "bone": 0},
            3: {"offset": {"x": -0.45, "y": -2.80, "z": 0.40}, "heading": 0.0, "bone": 0},
            4: {"offset": {"x": 0.45, "y": -2.80, "z": 0.40}, "heading": 0.0, "bone": 0},
            5: {"offset": {"x": -0.45, "y": -4.40, "z": 0.40}, "heading": 0.0, "bone": 0},
            6: {"offset": {"x": 0.45, "y": -4.40, "z": 0.40}, "heading": 0.0, "bone": 0}
        }
    },
    "forklift": {
        "name": "forklift",
        "maxSlots": 1,
        "slots": {
            1: {"offset": {"x": 0.0, "y": 1.40, "z": -0.20}, "heading": 0.0, "bone": 0}
        }
    }
}

POWER_STATES = {
    "OPTIMAL": "OPTIMAL",
    "NO_GRID": "NO_GRID",
    "GRID_BLACKOUT": "GRID_BLACKOUT",
    "BREAKER_TRIPPED": "BREAKER_TRIPPED",
    "FUEL_DEPLETED": "FUEL_DEPLETED",
    "MECHANICAL_BREAKDOWN": "MECHANICAL_BREAKDOWN"
}

def resolve_pallet_model(total_weight, item_count):
    count = int(item_count) if item_count else 0
    weight = max(0, float(total_weight)) if total_weight else 0.0

    if count <= 0 or weight <= 0:
        return PALLET_MODELS["Empty"]
    elif weight <= 300000:
        return PALLET_MODELS["Light"]
    elif weight <= 700000:
        return PALLET_MODELS["Medium"]
    else:
        return PALLET_MODELS["Heavy"]

def can_hold_weight(current_weight, added_weight):
    cur = max(0, float(current_weight)) if current_weight else 0.0
    add = max(0, float(added_weight)) if added_weight else 0.0
    return (cur + add) <= PALLET_MAX_WEIGHT

def can_hold_slot(current_slots):
    cur = max(0, int(current_slots)) if current_slots else 0
    return cur < PALLET_MAX_SLOTS

def can_seal_pallet(item_count, total_weight):
    count = int(item_count) if item_count else 0
    weight = float(total_weight) if total_weight else 0.0
    if count <= 0:
        return False, "CANNOT_SEAL_EMPTY_PALLET"
    if weight <= 0:
        return False, "INVALID_WEIGHT"
    return True, None

def get_vehicle_profile(model):
    if not model:
        return None
    lower = str(model).lower()
    return VEHICLE_PROFILES.get(lower)

def find_available_slot(model, occupied_slots):
    prof = get_vehicle_profile(model)
    if not prof:
        return None, "VEHICLE_NOT_PALLET_CARRIER"
    occupied = occupied_slots or {}
    for i in range(1, prof["maxSlots"] + 1):
        if not occupied.get(i):
            return i, None
    return None, "VEHICLE_PALLET_SLOTS_FULL"

def evaluate_power_status(substation_data, recipe_power_kw=15):
    if not substation_data:
        return False, POWER_STATES["NO_GRID"]
    if substation_data.get("isBlackout"):
        return False, POWER_STATES["GRID_BLACKOUT"]
    if substation_data.get("breakerTripped"):
        return False, POWER_STATES["BREAKER_TRIPPED"]
    fuel = float(substation_data.get("fuelLevel", 100.0))
    if fuel <= 0.0:
        return False, POWER_STATES["FUEL_DEPLETED"]
    health = float(substation_data.get("conditionHealth", 100.0))
    if health <= 10.0:
        return False, POWER_STATES["MECHANICAL_BREAKDOWN"]
    return True, POWER_STATES["OPTIMAL"]

def calculate_energy_usage_kwh(power_kw, duration_seconds):
    kw = max(0.0, float(power_kw))
    sec = max(0.0, float(duration_seconds))
    kwh = kw * (sec / 3600.0)
    return round(kwh, 4)

def calculate_grid_load_spike(power_kw, batch_count):
    kw = max(0.0, float(power_kw))
    batches = max(1, int(batch_count))
    concurrency_factor = 1.0 + ((batches - 1) * 0.15)
    total_kw = kw * batches * concurrency_factor
    mw = total_kw / 1000.0
    return round(mw, 4)

def calculate_progress_step(processing_time, tick_seconds, is_power_active):
    if not is_power_active:
        return 0.0
    total_time = max(1.0, float(processing_time))
    tick = max(0.0, float(tick_seconds))
    step = (tick / total_time) * 100.0
    return round(step, 2)

def should_auto_palletize(output_mode, total_weight, batch_count):
    if output_mode == "pallet":
        return True
    weight = max(0, float(total_weight))
    if weight >= 50000:
        return True
    return False

# ---------------------------------------------------------------------------
# Test Cases
# ---------------------------------------------------------------------------

def test_pallet_capacity_and_slot_boundaries():
    """Validates 1,000 kg capacity and 20 slot boundary enforcement."""
    # Under capacity
    assert can_hold_weight(800000, 150000) is True  # 950 kg <= 1000 kg
    assert can_hold_weight(0, 1000000) is True      # exactly 1000 kg

    # Exceeding capacity
    assert can_hold_weight(800000, 250000) is False # 1050 kg > 1000 kg
    assert can_hold_weight(1000000, 1) is False

    # Slot counts
    assert can_hold_slot(0) is True
    assert can_hold_slot(19) is True
    assert can_hold_slot(20) is False
    assert can_hold_slot(25) is False

def test_dynamic_pallet_prop_resolution():
    """Validates dynamic 3D prop model selection across load weight tiers."""
    # Empty
    assert resolve_pallet_model(0, 0) == "prop_pallet_01a"
    assert resolve_pallet_model(50000, 0) == "prop_pallet_01a"
    assert resolve_pallet_model(0, 5) == "prop_pallet_01a"

    # Light (<= 300kg)
    assert resolve_pallet_model(150000, 2) == "prop_boxpile_02b"
    assert resolve_pallet_model(300000, 4) == "prop_boxpile_02b"

    # Medium (301kg - 700kg)
    assert resolve_pallet_model(300001, 5) == "prop_boxpile_05a"
    assert resolve_pallet_model(500000, 6) == "prop_boxpile_05a"
    assert resolve_pallet_model(700000, 8) == "prop_boxpile_05a"

    # Heavy (> 700kg)
    assert resolve_pallet_model(700001, 10) == "prop_boxpile_06a"
    assert resolve_pallet_model(950000, 15) == "prop_boxpile_06a"

def test_commercial_vehicle_pallet_carrier_profiles():
    """Validates carrier vehicle profiles, capacity, and discrete slot offsets."""
    flatbed = get_vehicle_profile("flatbed")
    assert flatbed is not None
    assert flatbed["maxSlots"] == 3
    # Verify discrete bed positioning along Y-axis
    assert flatbed["slots"][1]["offset"]["y"] == -1.20
    assert flatbed["slots"][2]["offset"]["y"] == -2.80
    assert flatbed["slots"][3]["offset"]["y"] == -4.40

    mule = get_vehicle_profile("mule")
    assert mule is not None
    assert mule["maxSlots"] == 2

    benson = get_vehicle_profile("benson")
    assert benson is not None
    assert benson["maxSlots"] == 4

    pounder = get_vehicle_profile("pounder")
    assert pounder is not None
    assert pounder["maxSlots"] == 6

    forklift = get_vehicle_profile("forklift")
    assert forklift is not None
    assert forklift["maxSlots"] == 1
    assert forklift["slots"][1]["offset"]["y"] == 1.40
    assert forklift["slots"][1]["offset"]["z"] == -0.20

    # Non-carrier passenger vehicle rejection
    assert get_vehicle_profile("adder") is None
    assert get_vehicle_profile("police") is None

def test_collision_free_vehicle_slot_allocation():
    """Validates atomic slot assignment and boundary full detection."""
    # Empty flatbed -> slot 1
    slot, err = find_available_slot("flatbed", {})
    assert slot == 1 and err is None

    # Slot 1 occupied -> selects slot 2
    slot, err = find_available_slot("flatbed", {1: True})
    assert slot == 2 and err is None

    # Gapped: 1 and 3 occupied -> selects slot 2
    slot, err = find_available_slot("flatbed", {1: True, 3: True})
    assert slot == 2 and err is None

    # Full flatbed (3/3 slots) -> rejected
    slot, err = find_available_slot("flatbed", {1: True, 2: True, 3: True})
    assert slot is None
    assert err == "VEHICLE_PALLET_SLOTS_FULL"

    # Non-carrier vehicle -> rejected
    slot, err = find_available_slot("sultan", {})
    assert slot is None
    assert err == "VEHICLE_NOT_PALLET_CARRIER"

def test_pallet_sealing_and_tamper_proofing():
    """Validates security seal prerequisites."""
    # Empty pallet cannot be sealed
    ok, err = can_seal_pallet(0, 0)
    assert ok is False
    assert err == "CANNOT_SEAL_EMPTY_PALLET"

    # Zero weight cannot be sealed
    ok, err = can_seal_pallet(2, 0)
    assert ok is False
    assert err == "INVALID_WEIGHT"

    # Valid pallet with goods
    ok, err = can_seal_pallet(4, 250000)
    assert ok is True
    assert err is None

def test_power_grid_substation_interlock():
    """Validates power status evaluator under normal, blackout, and tripped conditions."""
    # 1. Optimal energized substation
    sub_optimal = {"isBlackout": False, "breakerTripped": False, "fuelLevel": 85.0, "conditionHealth": 90.0}
    ok, reason = evaluate_power_status(sub_optimal, 25)
    assert ok is True and reason == "OPTIMAL"

    # 2. Blackout state
    sub_blackout = {"isBlackout": True, "breakerTripped": True, "fuelLevel": 0.0, "conditionHealth": 85.0}
    ok, reason = evaluate_power_status(sub_blackout, 25)
    assert ok is False and reason == "GRID_BLACKOUT"

    # 3. Tripped circuit breaker
    sub_breaker = {"isBlackout": False, "breakerTripped": True, "fuelLevel": 50.0, "conditionHealth": 80.0}
    ok, reason = evaluate_power_status(sub_breaker, 25)
    assert ok is False and reason == "BREAKER_TRIPPED"

    # 4. Dry fuel reserves
    sub_dry = {"isBlackout": False, "breakerTripped": False, "fuelLevel": 0.0, "conditionHealth": 80.0}
    ok, reason = evaluate_power_status(sub_dry, 25)
    assert ok is False and reason == "FUEL_DEPLETED"

    # 5. Critical mechanical breakdown (<= 10%)
    sub_broken = {"isBlackout": False, "breakerTripped": False, "fuelLevel": 50.0, "conditionHealth": 8.0}
    ok, reason = evaluate_power_status(sub_broken, 25)
    assert ok is False and reason == "MECHANICAL_BREAKDOWN"

    # 6. Nil substation
    ok, reason = evaluate_power_status(None, 25)
    assert ok is False and reason == "NO_GRID"

def test_metered_energy_and_grid_load_spikes():
    """Validates kilowatt-hour energy integration and MW load spike calculations."""
    # 25 kW running for 3600 seconds (1 hour) = 25.0 kWh
    e1 = calculate_energy_usage_kwh(25.0, 3600.0)
    assert abs(e1 - 25.0) < 0.001

    # 15 kW running for 60 seconds = 0.25 kWh
    e2 = calculate_energy_usage_kwh(15.0, 60.0)
    assert abs(e2 - 0.25) < 0.001

    # Single batch 25 kW load spike = 0.025 MW
    spike1 = calculate_grid_load_spike(25.0, 1)
    assert abs(spike1 - 0.0250) < 0.001

    # 3 concurrent batches: 25 kW * 3 * (1.0 + 2 * 0.15) = 25 * 3 * 1.30 = 97.5 kW = 0.0975 MW
    spike3 = calculate_grid_load_spike(25.0, 3)
    assert abs(spike3 - 0.0975) < 0.001

def test_assembly_progress_hysteresis_and_pallet_output():
    """Validates machinery freeze during blackout and pallet output criteria."""
    # Progress step with power on (5s tick over 30s processing = 16.67%)
    step_on = calculate_progress_step(30.0, 5.0, True)
    assert abs(step_on - 16.67) < 0.02

    # Progress step with power offline (frozen machinery)
    step_off = calculate_progress_step(30.0, 5.0, False)
    assert step_off == 0.0

    # Auto-palletization decision
    # 1. Heavy machinery parts (55kg >= 50kg) auto-palletizes
    assert should_auto_palletize("inventory", 55000, 1) is True

    # 2. Light repair kit (2kg < 50kg) stays in stash
    assert should_auto_palletize("inventory", 2000, 1) is False

    # 3. Explicit pallet output mode forces palletization even for small loads
    assert should_auto_palletize("pallet", 2000, 1) is True

def test_database_migration_and_manifest_declarations():
    """Validates that migration 026 and scripts are properly declared and mirrored."""
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    core_mig = os.path.join(base_dir, "FiveM", "nyx_core", "sql", "migrations", "026_logistics_physical_pallets_and_power_assembly.sql")
    log_mig = os.path.join(base_dir, "FiveM", "nyx_logistics", "sql", "migrations", "026_logistics_physical_pallets_and_power_assembly.sql")
    index_file = os.path.join(base_dir, "FiveM", "nyx_core", "sql", "migrations", "index.json")

    assert os.path.exists(core_mig), f"Missing core migration: {core_mig}"
    assert os.path.exists(log_mig), f"Missing logistics migration: {log_mig}"
    assert os.path.exists(index_file), f"Missing index.json: {index_file}"

    with open(index_file, "r", encoding="utf-8") as f:
        migrations = json.load(f)
    assert "026_logistics_physical_pallets_and_power_assembly.sql" in migrations

    # Check fxmanifest.lua declarations in nyx_logistics
    manifest_path = os.path.join(base_dir, "FiveM", "nyx_logistics", "fxmanifest.lua")
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest_content = f.read()

    assert "shared/pallets.lua" in manifest_content
    assert "shared/assembly.lua" in manifest_content
    assert "server/pallets.lua" in manifest_content
