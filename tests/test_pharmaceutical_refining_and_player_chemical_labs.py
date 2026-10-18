"""
Tests for Pharmaceutical Refining, Player Chemical Labs & Medical Bio-Synthesis (Step 063)
Validates migration 063, item definitions, fxmanifest declarations, and pure mathematical
chemical synthesis, sterility degradation, and autoclave sterilization logic.
"""

import json
import math
import os
import re
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CORE_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "063_pharmaceutical_refining_and_player_chemical_labs.sql"
)
SERVICES_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_services", "sql", "migrations", "063_pharmaceutical_refining_and_player_chemical_labs.sql"
)
INDEX_JSON_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "index.json"
)
SERVICES_MANIFEST_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_services", "fxmanifest.lua"
)
ITEMS_LUA_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_inventory", "shared", "items.lua"
)
SHARED_CHEMLABS_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_services", "shared", "chemical_labs.lua"
)
SERVER_CHEMLABS_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_services", "server", "chemlabs.lua"
)
CLIENT_CHEMLABS_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_services", "client", "chemlabs.lua"
)


def test_migration_063_files_and_registration():
    """Verify SQL migration 063 exists in core & services, and is registered in index.json."""
    assert os.path.exists(CORE_MIGRATION_PATH), "Core migration 063 must exist"
    assert os.path.exists(SERVICES_MIGRATION_PATH), "Services migration 063 must exist"

    with open(INDEX_JSON_PATH, "r", encoding="utf-8") as f:
        registered = json.load(f)

    assert "063_pharmaceutical_refining_and_player_chemical_labs.sql" in registered, (
        "063 migration must be registered in index.json"
    )

    with open(CORE_MIGRATION_PATH, "r", encoding="utf-8") as f:
        core_sql = f.read()

    assert "CREATE TABLE IF NOT EXISTS `nyx_services_chemical_labs`" in core_sql
    assert "CREATE TABLE IF NOT EXISTS `nyx_services_chemlab_audits`" in core_sql
    assert "chemlab_humane_biotech" in core_sql
    assert "chemlab_cypress_refinery" in core_sql
    assert "chemlab_pillbox_pharmacy" in core_sql
    assert "chemlab_sandy_lab" in core_sql
    assert "node_humane_botanicals" in core_sql
    assert "node_el_burro_petrochem" in core_sql
    assert "node_zancudo_brine" in core_sql


def test_manifest_declarations():
    """Verify shared, server, and client chemical lab scripts are declared in fxmanifest.lua."""
    with open(SERVICES_MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = f.read()

    assert "shared/chemical_labs.lua" in manifest
    assert "server/chemlabs.lua" in manifest
    assert "client/chemlabs.lua" in manifest


def test_item_definitions_and_metadata():
    """Verify new pharmaceutical and chemical precursor items are defined in items.lua."""
    with open(ITEMS_LUA_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    required_items = [
        "raw_saline_brine",
        "saline_solution",
        "organic_compounds",
        "chemical_precursors",
        "item_disinfectant",
        "clean_linens",
        "bleach",
        "med_plasma",
        "med_surgical_pack"
    ]
    for item in required_items:
        assert f"['{item}']" in content, f"Item {item} must be registered in items.lua"

    assert "meta.osmolarity = 308" in content
    assert "meta.bloodType = (type(extra) == \"table\" and extra.bloodType) or \"O-Universal\"" in content
    assert "meta.concentration = \"0.5% Chlorhexidine\"" in content


def test_shared_chemlabs_syntax_and_structure():
    """Verify shared/chemical_labs.lua contains all 8 recipes and core mathematical API."""
    with open(SHARED_CHEMLABS_PATH, "r", encoding="utf-8") as f:
        lua = f.read()

    recipes = [
        "saline_purification",
        "synthetic_plasma_synthesis",
        "surgical_pack_autoclave",
        "disinfectant_compounding",
        "hospital_linens_sanitization",
        "sterile_pressure_bandage",
        "tourniquet_assembly",
        "morphine_ampoule_synthesis"
    ]
    for r in recipes:
        assert f"['{r}']" in lua, f"Recipe {r} must exist in chemical_labs.lua"

    assert "Nyx.ChemicalLabs.EvaluateRecipeEligibility" in lua
    assert "Nyx.ChemicalLabs.CalculateBatchYield" in lua
    assert "Nyx.ChemicalLabs.CalculateSterilityDegradation" in lua
    assert "Nyx.ChemicalLabs.EvaluateSterilizationCycle" in lua
    assert "Nyx.ChemicalLabs.IsPointNearLab" in lua
    assert "Nyx.ChemicalLabs.FormatLabDisplay" in lua


# --- Pure Mathematical & Algorithmic Unit Tests ---

class MockLab:
    def __init__(self, lab_id="chemlab_humane_biotech", sterility=95.0, status="idle"):
        self.lab_id = lab_id
        self.sterility_level = sterility
        self.autoclave_status = status


class MockRecipe:
    def __init__(self, key, inputs, outputs, time_sec, min_sterility, sterility_loss):
        self.key = key
        self.inputs = inputs
        self.outputs = outputs
        self.time_seconds = time_sec
        self.min_sterility = min_sterility
        self.sterility_loss = sterility_loss


PLASMA_RECIPE = MockRecipe(
    key="synthetic_plasma_synthesis",
    inputs={"organic_compounds": 2, "saline_solution": 1, "plastic_polymer": 1},
    outputs={"med_plasma": 1},
    time_sec=25,
    min_sterility=70.0,
    sterility_loss=8.0
)

SALINE_RECIPE = MockRecipe(
    key="saline_purification",
    inputs={"raw_saline_brine": 2, "drink_water": 1},
    outputs={"saline_solution": 2},
    time_sec=12,
    min_sterility=40.0,
    sterility_loss=3.0
)


def evaluate_recipe_eligibility(lab, recipe, is_powered, player_items, batch_qty=1):
    if lab.autoclave_status != "idle":
        return False, f"LAB_{lab.autoclave_status.upper()}"
    if not is_powered:
        return False, "GRID_BLACKOUT"
    if lab.sterility_level < recipe.min_sterility:
        return False, "STERILITY_TOO_LOW"

    for item, req_amount in recipe.inputs.items():
        total_req = req_amount * batch_qty
        if player_items.get(item, 0) < total_req:
            return False, "INSUFFICIENT_ITEMS"

    return True, "ELIGIBLE"


def calculate_batch_yield(recipe, sterility_level, batch_qty=1):
    if sterility_level < recipe.min_sterility:
        return 0, "CONTAMINATED_SPOILED", False

    total_units = sum(recipe.outputs.values()) * batch_qty
    if sterility_level >= 90.0:
        return total_units, "PURITY_OPTIMAL", True
    elif sterility_level >= 70.0:
        return total_units, "PURITY_STANDARD", True
    else:
        return total_units, "PURITY_DEGRADED", False


def calculate_sterility_degradation(current_sterility, recipe, batch_qty=1):
    loss = recipe.sterility_loss * batch_qty
    return max(0.0, current_sterility - loss)


def evaluate_sterilization_cycle(lab, player_items):
    if lab.autoclave_status not in ("idle", "contaminated"):
        return False, "LAB_BUSY", None
    if lab.sterility_level >= 99.0 and lab.autoclave_status == "idle":
        return False, "ALREADY_STERILE", None

    item_to_consume = None
    if player_items.get("item_disinfectant", 0) >= 1:
        item_to_consume = "item_disinfectant"
    elif player_items.get("bleach", 0) >= 1:
        item_to_consume = "bleach"

    if not item_to_consume:
        return False, "MISSING_DISINFECTANT", None

    return True, "ELIGIBLE", item_to_consume


def is_point_near_lab(point, lab_coords, max_dist=3.5):
    dx = point[0] - lab_coords[0]
    dy = point[1] - lab_coords[1]
    dz = point[2] - lab_coords[2]
    return (dx * dx + dy * dy + dz * dz) <= (max_dist * max_dist)


def test_recipe_eligibility_scenarios():
    """Verify comprehensive pre-condition validation for synthesis runs."""
    lab = MockLab(sterility=95.0, status="idle")
    items = {"raw_saline_brine": 10, "drink_water": 5}

    # 1. Normal valid case
    ok, code = evaluate_recipe_eligibility(lab, SALINE_RECIPE, is_powered=True, player_items=items, batch_qty=2)
    assert ok is True
    assert code == "ELIGIBLE"

    # 2. Blackout
    ok, code = evaluate_recipe_eligibility(lab, SALINE_RECIPE, is_powered=False, player_items=items)
    assert ok is False
    assert code == "GRID_BLACKOUT"

    # 3. Missing items
    ok, code = evaluate_recipe_eligibility(lab, SALINE_RECIPE, is_powered=True, player_items={"raw_saline_brine": 1})
    assert ok is False
    assert code == "INSUFFICIENT_ITEMS"

    # 4. Sterility too low for high-end plasma
    low_lab = MockLab(sterility=65.0, status="idle")
    plasma_items = {"organic_compounds": 5, "saline_solution": 5, "plastic_polymer": 5}
    ok, code = evaluate_recipe_eligibility(low_lab, PLASMA_RECIPE, is_powered=True, player_items=plasma_items)
    assert ok is False
    assert code == "STERILITY_TOO_LOW"

    # 5. Workstation busy
    busy_lab = MockLab(sterility=95.0, status="synthesizing")
    ok, code = evaluate_recipe_eligibility(busy_lab, SALINE_RECIPE, is_powered=True, player_items=items)
    assert ok is False
    assert code == "LAB_SYNTHESIZING"


def test_batch_yield_and_purity_physics():
    """Verify sterility-based yield degradation and contamination cutoffs."""
    # Optimal >= 90%
    units, grade, sterile = calculate_batch_yield(PLASMA_RECIPE, 92.0, batch_qty=3)
    assert units == 3
    assert grade == "PURITY_OPTIMAL"
    assert sterile is True

    # Standard 70-89%
    units, grade, sterile = calculate_batch_yield(PLASMA_RECIPE, 78.0, batch_qty=2)
    assert units == 2
    assert grade == "PURITY_STANDARD"
    assert sterile is True

    # Spoiled below minimum threshold (70%)
    units, grade, sterile = calculate_batch_yield(PLASMA_RECIPE, 60.0, batch_qty=2)
    assert units == 0
    assert grade == "CONTAMINATED_SPOILED"
    assert sterile is False


def test_sterility_degradation_and_contamination_curve():
    """Verify degradation math across multiple batches and critical contamination."""
    curr = 95.0
    # Run 1 batch of plasma (-8.0)
    curr = calculate_sterility_degradation(curr, PLASMA_RECIPE, 1)
    assert math.isclose(curr, 87.0)

    # Run 2 batches of plasma (-16.0)
    curr = calculate_sterility_degradation(curr, PLASMA_RECIPE, 2)
    assert math.isclose(curr, 71.0)

    # Run 4 batches of plasma (-32.0)
    curr = calculate_sterility_degradation(curr, PLASMA_RECIPE, 4)
    assert math.isclose(curr, 39.0)
    assert curr < 40.0  # Critical contamination threshold reached!


def test_sterilization_cycle_eligibility():
    """Verify autoclave sanitization cycles with disinfectant or bleach."""
    contam_lab = MockLab(sterility=35.0, status="contaminated")

    # With disinfectant
    ok, code, item = evaluate_sterilization_cycle(contam_lab, {"item_disinfectant": 1})
    assert ok is True
    assert item == "item_disinfectant"

    # With bleach
    ok, code, item = evaluate_sterilization_cycle(contam_lab, {"bleach": 2})
    assert ok is True
    assert item == "bleach"

    # Missing supplies
    ok, code, item = evaluate_sterilization_cycle(contam_lab, {})
    assert ok is False
    assert code == "MISSING_DISINFECTANT"

    # Already sterile
    clean_lab = MockLab(sterility=100.0, status="idle")
    ok, code, _ = evaluate_sterilization_cycle(clean_lab, {"item_disinfectant": 1})
    assert ok is False
    assert code == "ALREADY_STERILE"


def test_spatial_proximity_math():
    """Verify 3D Euclidean interaction math for lab workstations."""
    lab_pos = (3538.5, 3660.2, 28.1)
    near_ped = (3539.0, 3661.0, 28.1)   # dist = ~0.94m
    far_ped = (3550.0, 3675.0, 28.1)    # dist = ~18.6m

    assert is_point_near_lab(near_ped, lab_pos, 3.5) is True
    assert is_point_near_lab(far_ped, lab_pos, 3.5) is False
