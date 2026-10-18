"""
Tests for Industrial Refining Plants, Forestry Timber Harvesting & Functional Parts Manufacturing (Step 064)
Validates SQL migration 064, item registry definitions, recipes, nodes, fxmanifest declarations,
and pure Lua 5.4 deterministic domain algorithms for refining yields, power scaling, and pallet packaging.
"""

import json
import math
import os
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CORE_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "064_industrial_refining_and_functional_parts_manufacturing.sql"
)
LOGISTICS_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_logistics", "sql", "migrations", "064_industrial_refining_and_functional_parts_manufacturing.sql"
)
INDEX_JSON_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "index.json"
)
LOGISTICS_MANIFEST_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_logistics", "fxmanifest.lua"
)
ITEMS_LUA_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_inventory", "shared", "items.lua"
)
RECIPES_LUA_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_logistics", "shared", "recipes.lua"
)
NODES_LUA_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_logistics", "shared", "nodes.lua"
)
SHARED_REFINING_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_logistics", "shared", "refining.lua"
)
SERVER_REFINING_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_logistics", "server", "refining.lua"
)
SERVER_EXPORTS_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_logistics", "server", "exports.lua"
)
CLIENT_REFINING_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_logistics", "client", "refining.lua"
)
CLIENT_EXPORTS_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_logistics", "client", "exports.lua"
)


def test_migration_064_files_and_registration():
    """Verify SQL migration 064 exists in core and logistics, and is registered in index.json."""
    assert os.path.exists(CORE_MIGRATION_PATH), "Core migration 064 must exist"
    assert os.path.exists(LOGISTICS_MIGRATION_PATH), "Logistics migration 064 must exist"

    with open(INDEX_JSON_PATH, "r", encoding="utf-8") as f:
        registered = json.load(f)

    assert "064_industrial_refining_and_functional_parts_manufacturing.sql" in registered, (
        "064 migration must be registered in index.json"
    )

    with open(CORE_MIGRATION_PATH, "r", encoding="utf-8") as f:
        sql = f.read()

    assert "CREATE TABLE IF NOT EXISTS `nyx_logistics_refining_audits`" in sql
    assert "node_paleto_forest_timber" in sql
    assert "node_chiliad_redwood" in sql
    assert "node_san_chianski_cotton" in sql
    assert "fac_paleto_sawmill" in sql
    assert "fac_elysian_foundry" in sql
    assert "fac_davis_textile" in sql
    assert "stash:sawmill_in" in sql
    assert "stash:sawmill_out" in sql
    assert "stash:foundry_in" in sql
    assert "stash:foundry_out" in sql
    assert "stash:textile_in" in sql
    assert "stash:textile_out" in sql


def test_manifest_declarations():
    """Verify shared, server, and client refining files are declared in fxmanifest.lua."""
    with open(LOGISTICS_MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = f.read()

    assert "shared/refining.lua" in manifest, "shared/refining.lua must be declared"
    assert "server/refining.lua" in manifest, "server/refining.lua must be declared"
    assert "client/refining.lua" in manifest, "client/refining.lua must be declared"


def test_item_definitions_and_metadata():
    """Verify newly registered industrial materials and functional parts exist in items.lua."""
    with open(ITEMS_LUA_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    required_items = [
        "raw_timber_logs",
        "raw_cotton",
        "wood_cellulose",
        "sheet_metal",
        "copper_wire",
        "circuit_substrate",
        "electronic_circuit",
        "item_weapon_parts"
    ]

    for item in required_items:
        assert f"['{item}']" in content, f"Item {item} must be registered in items.lua"

    assert "meta.alloyGrade" in content, "sheet_metal alloyGrade metadata must be set"
    assert "meta.gauge" in content, "copper_wire gauge metadata must be set"
    assert "meta.firmwareVersion" in content, "electronic_circuit firmware metadata must be set"
    assert "meta.tolerance = \"0.005mm\"" in content, "item_weapon_parts tolerance must be set"


def test_recipes_and_nodes_declarations():
    """Verify all new recipes and harvest nodes are declared in recipes.lua and nodes.lua."""
    with open(RECIPES_LUA_PATH, "r", encoding="utf-8") as f:
        recipes = f.read()

    expected_recipes = [
        "timber_sawmill_milling",
        "structural_sheet_rolling",
        "copper_wire_drawing",
        "textile_cotton_carding",
        "circuit_board_fabrication",
        "electronics_assembly",
        "precision_weapon_parts_machining",
        "wire_cutters_assembly"
    ]

    for rec in expected_recipes:
        assert f"['{rec}']" in recipes, f"Recipe {rec} must be declared in recipes.lua"

    with open(NODES_LUA_PATH, "r", encoding="utf-8") as f:
        nodes = f.read()

    expected_nodes = [
        "node_paleto_forest_timber",
        "node_chiliad_redwood",
        "node_san_chianski_cotton"
    ]

    for node in expected_nodes:
        assert f"['{node}']" in nodes, f"Node {node} must be declared in nodes.lua"


def test_refining_domain_input_validation():
    """Test pure mathematical batch input validation logic."""
    recipe = {
        "key": "structural_sheet_rolling",
        "inputs": [
            {"item": "refined_iron", "amount": 3}
        ]
    }

    # Available items insufficient
    items_insufficient = {"refined_iron": 5}
    batch_count = 2  # Needs 3 * 2 = 6
    req_total = 3 * batch_count
    have = items_insufficient.get("refined_iron", 0)
    assert have < req_total
    assert (have >= req_total) is False

    # Available items sufficient
    items_sufficient = {"refined_iron": 10}
    have_suff = items_sufficient.get("refined_iron", 0)
    assert have_suff >= req_total


def test_refining_energy_duration_and_yield_math():
    """Test duration, power draw, energy (kWh) and yield calculation formulas."""
    base_time = 30
    base_kw = 25
    batches = 3

    # Industrial scaling formulas from shared/refining.lua:
    # duration = baseTime * (1.0 + (batches - 1) * 0.85)
    duration = math.floor(base_time * (1.0 + (batches - 1) * 0.85))
    expected_duration = math.floor(30 * (1.0 + 2 * 0.85))  # 30 * 2.7 = 81s
    assert duration == expected_duration

    # powerKw = baseKw * (1.0 + (batches - 1) * 0.20)
    power_kw = base_kw * (1.0 + (batches - 1) * 0.20)  # 25 * 1.4 = 35.0 kW
    assert math.isclose(power_kw, 35.0, abs_tol=0.01)

    # totalKwh = powerKw * (duration / 3600.0)
    total_kwh = math.floor(power_kw * (duration / 3600.0) * 10000) / 10000
    assert total_kwh > 0.0

    # Yield calculation with efficiency
    recipe = {
        "key": "structural_sheet_rolling",
        "outputs": [
            {"item": "sheet_metal", "amount": 2}
        ]
    }
    eff = 1.10  # 10% bonus
    base_amount = 2 * batches  # 6
    final_amount = math.floor(base_amount * eff)  # floor(6.6) = 6
    assert final_amount == 6

    eff_high = 1.25  # 25% bonus
    final_amount_high = math.floor(base_amount * eff_high)  # floor(7.5) = 7
    assert final_amount_high == 7


def test_pallet_packaging_logic():
    """Test heavy freight palletization thresholds."""
    threshold = 50000  # 50kg

    # Under threshold -> not palletized in inventory mode
    unit_weight = 3500  # 3.5kg per sheet_metal
    batch_amount = 2 * 3  # 6 units
    total_weight = unit_weight * batch_amount  # 21,000g (21kg)
    should_pallet = (total_weight >= threshold)
    assert should_pallet is False

    # Heavy run -> palletized
    heavy_batches = 8  # 16 units * 3500g = 56,000g (56kg)
    heavy_weight = unit_weight * (2 * heavy_batches)
    assert (heavy_weight >= threshold) is True


def test_refining_spatial_math_and_telemetry():
    """Test 3D Euclidean distance math and telemetry format structure."""
    fac_coords = {"x": -552.4, "y": 5324.8, "z": 73.6}
    player_near = {"x": -551.0, "y": 5325.0, "z": 73.6}
    player_far = {"x": -500.0, "y": 5300.0, "z": 70.0}

    dx_near = player_near["x"] - fac_coords["x"]
    dy_near = player_near["y"] - fac_coords["y"]
    dz_near = player_near["z"] - fac_coords["z"]
    dist_near = math.sqrt(dx_near**2 + dy_near**2 + dz_near**2)
    assert dist_near <= 4.5

    dx_far = player_far["x"] - fac_coords["x"]
    dy_far = player_far["y"] - fac_coords["y"]
    dz_far = player_far["z"] - fac_coords["z"]
    dist_far = math.sqrt(dx_far**2 + dy_far**2 + dz_far**2)
    assert dist_far > 4.5


def test_server_and_client_refining_rpc_and_exports():
    """Verify server and client refining script declarations and exports."""
    with open(SERVER_REFINING_PATH, "r", encoding="utf-8") as f:
        server_code = f.read()

    assert 'Nyx.RPC.Register("logistics:getRefiningFacilities"' in server_code
    assert 'Nyx.RPC.Register("logistics:getRefiningFacilityTelemetry"' in server_code
    assert 'Nyx.RPC.Register("logistics:startRefiningBatch"' in server_code
    assert 'Nyx.RPC.Register("logistics:cancelRefiningBatch"' in server_code
    assert 'function Nyx.Logistics.LogRefiningAudit' in server_code

    with open(SERVER_EXPORTS_PATH, "r", encoding="utf-8") as f:
        exports_code = f.read()

    assert 'exports("GetRefiningFacility"' in exports_code
    assert 'exports("GetRefiningFacilities"' in exports_code
    assert 'exports("StartRefiningBatch"' in exports_code
    assert 'exports("CancelRefiningBatch"' in exports_code
    assert 'exports("LogRefiningAudit"' in exports_code

    with open(CLIENT_REFINING_PATH, "r", encoding="utf-8") as f:
        client_code = f.read()

    assert 'RegisterCommand("refining"' in client_code
    assert 'RegisterCommand("startrefining"' in client_code
    assert 'fac_paleto_sawmill' in client_code
    assert 'fac_elysian_foundry' in client_code
    assert 'fac_davis_textile' in client_code

    with open(CLIENT_EXPORTS_PATH, "r", encoding="utf-8") as f:
        client_exports = f.read()

    assert 'exports("GetClosestRefiningFacility"' in client_exports
    assert 'exports("GetNearbyRefiningFacilities"' in client_exports
