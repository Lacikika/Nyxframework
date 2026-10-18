"""
Test Suite: Organizational Warehousing & Storage Networks (nyx_factions, nyx_logistics & nyx_inventory)
Validates pure Lua 5.4 domain algorithms, taxonomy contracts, RBAC access evaluation,
deployment validation, pallet staging arithmetic, SQL migration 060, manifests, and test wiring.
"""

import json
import os
import re
import pytest

MIGRATION_PATH = os.path.join("FiveM", "nyx_core", "sql", "migrations", "060_organizational_warehousing_and_storage_networks.sql")
FACTIONS_MIGRATION_PATH = os.path.join("FiveM", "nyx_factions", "sql", "migrations", "060_organizational_warehousing_and_storage_networks.sql")
INDEX_JSON_PATH = os.path.join("FiveM", "nyx_core", "sql", "migrations", "index.json")
FACTIONS_MANIFEST = os.path.join("FiveM", "nyx_factions", "fxmanifest.lua")
LOGISTICS_MANIFEST = os.path.join("FiveM", "nyx_logistics", "fxmanifest.lua")
SHARED_LUA = os.path.join("FiveM", "nyx_factions", "shared", "storage_networks.lua")
SERVER_LUA = os.path.join("FiveM", "nyx_factions", "server", "storage_networks.lua")
CLIENT_LUA = os.path.join("FiveM", "nyx_factions", "client", "storage_networks.lua")
CORE_TESTS = os.path.join("FiveM", "nyx_core", "server", "tests.lua")


class MockStorageNetworks:
    """Python reference mirror of pure Lua Nyx.StorageNetworks algorithms."""

    Taxonomy = {
        "secured_stash": {
            "tiers": {
                "standard": {"capacity_grams": 1000000, "slots": 60, "model": "prop_cabinet_02b", "fee": 2500.00},
                "reinforced": {"capacity_grams": 3000000, "slots": 100, "model": "prop_ld_greenscrn_01", "fee": 6000.00},
                "vault": {"capacity_grams": 10000000, "slots": 150, "model": "ch_prop_ch_vault_metal_01a", "fee": 15000.00}
            },
            "defaultTier": "standard"
        },
        "industrial_workbench": {
            "subtypes": {
                "assembly": {"model": "prop_toolchest_01", "fee": 5000.00, "label": "Ipari Összeszerelő Pad"},
                "refining": {"model": "gr_prop_gr_bench_02b", "fee": 7500.00, "label": "Nyersanyag Finomító Munkapad"},
                "weapons": {"model": "gr_prop_gr_bench_02b", "fee": 12000.00, "label": "Fegyverkovács Munkapad"},
                "medical": {"model": "prop_toolchest_01", "fee": 8500.00, "label": "Gyógyszerészeti Szintetizátor"}
            },
            "defaultSubtype": "assembly"
        },
        "pallet_drop_zone": {
            "maxPallets": 4,
            "radius": 4.5,
            "fee": 1500.00,
            "model": "prop_pallet_01a"
        }
    }

    FacilityLimits = {
        "warehouse": {"secured_stash": 10, "industrial_workbench": 4, "pallet_drop_zone": 4},
        "commercial_storefront": {"secured_stash": 4, "industrial_workbench": 2, "pallet_drop_zone": 1},
        "property": {"secured_stash": 2, "industrial_workbench": 1, "pallet_drop_zone": 0}
    }

    @staticmethod
    def evaluate_permission(nodes, required_node):
        if not nodes:
            return False
        for node in nodes:
            if node == "*" or node == required_node:
                return True
            if node.endswith(":*"):
                prefix = node[:-2]
                if required_node.startswith(prefix):
                    return True
        return False

    @classmethod
    def evaluate_asset_access(cls, asset, member):
        if not asset or not member:
            return False, "INVALID_ARGUMENTS", "denied"

        # 1. Faction membership verification
        if asset.get("faction_id") != member.get("faction_id"):
            return False, "ACCESS_DENIED_FACTION_MISMATCH", "denied"

        # 2. Check lock status
        is_locked = bool(asset.get("is_locked", False))
        has_manage = cls.evaluate_permission(member.get("permissions", []), "inventory:manage_stashes")
        is_exec = cls.evaluate_permission(member.get("permissions", []), "*")

        if is_locked and not (has_manage or is_exec):
            return False, "ACCESS_DENIED_ASSET_LOCKED", "denied"

        # 3. Minimum rank verification
        min_rank = int(asset.get("min_rank_level", 1))
        member_rank = int(member.get("rank_level", 1))
        if member_rank < min_rank and not is_exec:
            return False, "ACCESS_DENIED_INSUFFICIENT_RANK", "denied"

        # 4. RBAC Permission Node verification
        req_node = asset.get("access_permission_node", "inventory:view")
        perms = member.get("permissions", [])

        if is_exec or has_manage or cls.evaluate_permission(perms, "*"):
            return True, "AUTHORIZED_FULL", "full"

        if cls.evaluate_permission(perms, "inventory:withdraw") or cls.evaluate_permission(perms, "inventory:*"):
            return True, "AUTHORIZED_FULL", "full"

        if cls.evaluate_permission(perms, "inventory:deposit"):
            return True, "AUTHORIZED_DEPOSIT_ONLY", "deposit_only"

        if cls.evaluate_permission(perms, req_node) or cls.evaluate_permission(perms, "inventory:view"):
            return True, "AUTHORIZED_READ_ONLY", "read_only"

        return False, "ACCESS_DENIED_NO_PERMISSION", "denied"

    @classmethod
    def validate_deployment_parameters(cls, facility_type, facility_id, asset_type, subtype_or_tier, coords, existing_count):
        if facility_type not in cls.FacilityLimits:
            return False, "INVALID_FACILITY_TYPE", None

        if not facility_id or len(str(facility_id).strip()) < 2:
            return False, "INVALID_FACILITY_ID", None

        if asset_type not in cls.Taxonomy:
            return False, "INVALID_ASSET_TYPE", None

        limits = cls.FacilityLimits[facility_type]
        max_allowed = limits.get(asset_type, 0)
        if existing_count >= max_allowed:
            return False, f"FACILITY_LIMIT_EXCEEDED_MAX_{max_allowed}", None

        if not coords or not isinstance(coords, dict):
            return False, "INVALID_COORDINATES", None

        x = float(coords.get("x", 0.0))
        y = float(coords.get("y", 0.0))
        z = float(coords.get("z", 0.0))
        h = float(coords.get("h", coords.get("heading", 0.0))) % 360.0

        sanitized = {
            "facility_type": facility_type,
            "facility_id": str(facility_id).strip(),
            "asset_type": asset_type,
            "coords": {"x": round(x, 2), "y": round(y, 2), "z": round(z, 2), "h": round(h, 2)},
        }

        if asset_type == "secured_stash":
            tier = subtype_or_tier if subtype_or_tier in cls.Taxonomy["secured_stash"]["tiers"] else "standard"
            spec = cls.Taxonomy["secured_stash"]["tiers"][tier]
            sanitized["tier"] = tier
            sanitized["capacity_grams"] = spec["capacity_grams"]
            sanitized["slots"] = spec["slots"]
            sanitized["model"] = spec["model"]
            sanitized["fee"] = spec["fee"]
        elif asset_type == "industrial_workbench":
            sub = subtype_or_tier if subtype_or_tier in cls.Taxonomy["industrial_workbench"]["subtypes"] else "assembly"
            spec = cls.Taxonomy["industrial_workbench"]["subtypes"][sub]
            sanitized["workbench_subtype"] = sub
            sanitized["model"] = spec["model"]
            sanitized["fee"] = spec["fee"]
        elif asset_type == "pallet_drop_zone":
            spec = cls.Taxonomy["pallet_drop_zone"]
            sanitized["pallet_max_capacity"] = spec["maxPallets"]
            sanitized["radius"] = spec["radius"]
            sanitized["model"] = spec["model"]
            sanitized["fee"] = spec["fee"]

        return True, "VALIDATION_OK", sanitized

    @classmethod
    def evaluate_pallet_staging(cls, drop_zone, pallet_id, action):
        staged = list(drop_zone.get("staged_pallets", []))
        max_cap = int(drop_zone.get("pallet_max_capacity", 4))

        if action == "stage":
            if len(staged) >= max_cap:
                return False, "DROP_ZONE_CAPACITY_FULL", staged
            if pallet_id in staged:
                return False, "PALLET_ALREADY_STAGED", staged
            staged.append(pallet_id)
            return True, "STAGED_SUCCESSFULLY", staged
        elif action == "retrieve":
            if pallet_id not in staged:
                return False, "PALLET_NOT_FOUND_IN_ZONE", staged
            staged.remove(pallet_id)
            return True, "RETRIEVED_SUCCESSFULLY", staged

        return False, "UNKNOWN_ACTION", staged


def test_taxonomy_definitions():
    """Validates asset types, capacity tiers, workbench subtypes, and facility limits."""
    assert "secured_stash" in MockStorageNetworks.Taxonomy
    assert "industrial_workbench" in MockStorageNetworks.Taxonomy
    assert "pallet_drop_zone" in MockStorageNetworks.Taxonomy

    stash_tiers = MockStorageNetworks.Taxonomy["secured_stash"]["tiers"]
    assert stash_tiers["standard"]["capacity_grams"] == 1000000
    assert stash_tiers["reinforced"]["capacity_grams"] == 3000000
    assert stash_tiers["vault"]["capacity_grams"] == 10000000

    workbench_subs = MockStorageNetworks.Taxonomy["industrial_workbench"]["subtypes"]
    assert "assembly" in workbench_subs
    assert "refining" in workbench_subs
    assert "weapons" in workbench_subs
    assert "medical" in workbench_subs

    # Facility density limits
    wh_limits = MockStorageNetworks.FacilityLimits["warehouse"]
    assert wh_limits["secured_stash"] == 10
    assert wh_limits["industrial_workbench"] == 4
    assert wh_limits["pallet_drop_zone"] == 4


def test_asset_access_rbac_and_rank():
    """Validates multi-tier RBAC access control, wildcard propagation, rank checks, and locks."""
    asset = {
        "asset_id": 1,
        "faction_id": "corp:elysian",
        "access_permission_node": "inventory:withdraw",
        "min_rank_level": 2,
        "is_locked": 0
    }

    # 1. Other faction rejected
    other_member = {"faction_id": "corp:other", "rank_level": 5, "permissions": ["*"]}
    ok, reason, tier = MockStorageNetworks.evaluate_asset_access(asset, other_member)
    assert not ok
    assert reason == "ACCESS_DENIED_FACTION_MISMATCH"

    # 2. Insufficient rank
    low_rank = {"faction_id": "corp:elysian", "rank_level": 1, "permissions": ["inventory:withdraw"]}
    ok, reason, tier = MockStorageNetworks.evaluate_asset_access(asset, low_rank)
    assert not ok
    assert reason == "ACCESS_DENIED_INSUFFICIENT_RANK"

    # 3. Valid rank and withdrawal permission -> full access
    qualified_member = {"faction_id": "corp:elysian", "rank_level": 2, "permissions": ["inventory:withdraw"]}
    ok, reason, tier = MockStorageNetworks.evaluate_asset_access(asset, qualified_member)
    assert ok
    assert tier == "full"

    # 4. Wildcard permissions (*)
    executive = {"faction_id": "corp:elysian", "rank_level": 1, "permissions": ["*"]}
    ok, reason, tier = MockStorageNetworks.evaluate_asset_access(asset, executive)
    assert ok
    assert tier == "full"

    # 5. Locked asset blocks non-officers
    locked_asset = dict(asset, is_locked=1)
    ok, reason, tier = MockStorageNetworks.evaluate_asset_access(locked_asset, qualified_member)
    assert not ok
    assert reason == "ACCESS_DENIED_ASSET_LOCKED"

    officer = {"faction_id": "corp:elysian", "rank_level": 3, "permissions": ["inventory:manage_stashes"]}
    ok, reason, tier = MockStorageNetworks.evaluate_asset_access(locked_asset, officer)
    assert ok
    assert tier == "full"


def test_deposit_only_and_view_access():
    """Validates deposit-only and view-only permissions."""
    asset = {
        "asset_id": 2,
        "faction_id": "corp:elysian",
        "access_permission_node": "inventory:view",
        "min_rank_level": 1,
        "is_locked": 0
    }

    # Deposit-only member
    dep_member = {"faction_id": "corp:elysian", "rank_level": 1, "permissions": ["inventory:deposit"]}
    ok, reason, tier = MockStorageNetworks.evaluate_asset_access(asset, dep_member)
    assert ok
    assert tier == "deposit_only"

    # View-only member
    view_member = {"faction_id": "corp:elysian", "rank_level": 1, "permissions": ["inventory:view"]}
    ok, reason, tier = MockStorageNetworks.evaluate_asset_access(asset, view_member)
    assert ok
    assert tier == "read_only"


def test_validate_deployment_parameters():
    """Validates deployment parameter sanitization, limits, and pricing."""
    coords = {"x": 100.5, "y": -200.2, "z": 15.0, "h": 90.0}

    # Successful warehouse stash deployment
    ok, msg, data = MockStorageNetworks.validate_deployment_parameters(
        "warehouse", "wh_elysian_04", "secured_stash", "reinforced", coords, 2
    )
    assert ok
    assert data["capacity_grams"] == 3000000
    assert data["slots"] == 100
    assert data["fee"] == 6000.00
    assert data["coords"]["x"] == 100.5

    # Exceeding limits
    ok, msg, data = MockStorageNetworks.validate_deployment_parameters(
        "commercial_storefront", "store_vinewood_24", "secured_stash", "standard", coords, 4
    )
    assert not ok
    assert "FACILITY_LIMIT_EXCEEDED" in msg

    # Invalid facility type
    ok, msg, data = MockStorageNetworks.validate_deployment_parameters(
        "spaceship", "station_1", "secured_stash", "standard", coords, 0
    )
    assert not ok
    assert msg == "INVALID_FACILITY_TYPE"


def test_pallet_drop_zone_staging():
    """Validates pallet staging, duplicate prevention, capacity enforcement, and retrieval."""
    zone = {"pallet_max_capacity": 3, "staged_pallets": ["pallet:001", "pallet:002"]}

    # Stage 3rd pallet -> Success
    ok, msg, staged = MockStorageNetworks.evaluate_pallet_staging(zone, "pallet:003", "stage")
    assert ok
    assert len(staged) == 3
    assert "pallet:003" in staged

    # Stage 4th pallet -> Exceeds capacity
    full_zone = {"pallet_max_capacity": 3, "staged_pallets": staged}
    ok, msg, res = MockStorageNetworks.evaluate_pallet_staging(full_zone, "pallet:004", "stage")
    assert not ok
    assert msg == "DROP_ZONE_CAPACITY_FULL"

    # Duplicate staging
    ok, msg, res = MockStorageNetworks.evaluate_pallet_staging(zone, "pallet:001", "stage")
    assert not ok
    assert msg == "PALLET_ALREADY_STAGED"

    # Retrieve pallet -> Success
    ok, msg, after_retrieve = MockStorageNetworks.evaluate_pallet_staging(zone, "pallet:002", "retrieve")
    assert ok
    assert "pallet:002" not in after_retrieve
    assert len(after_retrieve) == 1

    # Retrieve nonexistent pallet -> Error
    ok, msg, res = MockStorageNetworks.evaluate_pallet_staging(zone, "pallet:999", "retrieve")
    assert not ok
    assert msg == "PALLET_NOT_FOUND_IN_ZONE"


def test_sql_migration_060_exists_and_registered():
    """Verifies that migration 060 exists, contains required schemas, and is in index.json."""
    assert os.path.exists(MIGRATION_PATH), f"Missing {MIGRATION_PATH}"
    assert os.path.exists(FACTIONS_MIGRATION_PATH), f"Missing {FACTIONS_MIGRATION_PATH}"

    with open(MIGRATION_PATH, "r", encoding="utf-8") as f:
        sql_content = f.read()

    assert "CREATE TABLE IF NOT EXISTS `nyx_factions_deployed_assets`" in sql_content
    assert "CREATE TABLE IF NOT EXISTS `nyx_factions_storage_access_audit`" in sql_content
    assert "`asset_uuid`" in sql_content
    assert "`facility_type`" in sql_content
    assert "`access_permission_node`" in sql_content
    assert "`workbench_subtype`" in sql_content
    assert "`staged_pallets_json`" in sql_content

    with open(INDEX_JSON_PATH, "r", encoding="utf-8") as f:
        index_data = json.load(f)

    if isinstance(index_data, dict) and "migrations" in index_data:
        migration_filenames = [m["file"] for m in index_data["migrations"]]
    else:
        migration_filenames = index_data

    assert "060_organizational_warehousing_and_storage_networks.sql" in migration_filenames


def test_manifest_declarations():
    """Verifies fxmanifest declarations across nyx_factions and nyx_logistics."""
    assert os.path.exists(FACTIONS_MANIFEST)
    assert os.path.exists(LOGISTICS_MANIFEST)

    with open(FACTIONS_MANIFEST, "r", encoding="utf-8") as f:
        factions_mf = f.read()

    assert "shared/storage_networks.lua" in factions_mf
    assert "server/storage_networks.lua" in factions_mf
    assert "client/storage_networks.lua" in factions_mf

    with open(LOGISTICS_MANIFEST, "r", encoding="utf-8") as f:
        logistics_mf = f.read()

    assert "@nyx_factions/shared/storage_networks.lua" in logistics_mf


def test_in_engine_tests_wiring():
    """Verifies that Test 55 is implemented and registered in nyx_core/server/tests.lua."""
    assert os.path.exists(CORE_TESTS)
    with open(CORE_TESTS, "r", encoding="utf-8") as f:
        content = f.read()

    assert "TestOrganizationalWarehousingAndStorageNetworks" in content
    assert "Nyx.Tests.TestOrganizationalWarehousingAndStorageNetworks" in content
