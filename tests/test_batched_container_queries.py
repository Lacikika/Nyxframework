"""
Unit test suite for Nyxframework Batched Container Queries on Boot:
- Pure Lua/Python Query Planning, Chunking & Deduplication
- Cache Partitioning (Hot Memory Hits vs Cold Database Misses)
- ANSI Parameterized SQL WHERE id IN (...) Generation
- Mathematical Query Savings Efficiency Proof (97.5% - 98.0% Reduction)
- Relational Item Grouping & Startup Container Pattern Recognition
- Manifest & Cross-Resource Integration Integrity (nyx_inventory, nyx_logistics, nyx_properties)
"""

import math
import os
import re
import pytest

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ============================================================================
# PYTHON REFERENCE MIRROR: BATCH CONTAINER QUERY ENGINE
# ============================================================================

class BatchContainerEngine:
    """Python reference mirror of nyx_inventory/shared/batch.lua and state.lua."""

    @staticmethod
    def sanitize_container_ids(ids):
        if not isinstance(ids, list):
            return [], {}
        clean_list = []
        id_set = {}
        for raw in ids:
            if isinstance(raw, str):
                trimmed = raw.strip()
                if trimmed and trimmed not in id_set:
                    id_set[trimmed] = True
                    clean_list.append(trimmed)
        return clean_list, id_set

    @staticmethod
    def partition_existing(ids, existing_map):
        if not isinstance(ids, list):
            return [], []
        existing = existing_map if isinstance(existing_map, dict) else {}
        hits = []
        misses = []
        for cid in ids:
            if cid in existing:
                hits.append(cid)
            else:
                misses.append(cid)
        return hits, misses

    @staticmethod
    def chunk_ids(ids, chunk_size=50):
        if not isinstance(ids, list):
            return []
        chunk_size = max(1, int(chunk_size))
        chunks = []
        cur = []
        for cid in ids:
            cur.append(cid)
            if len(cur) >= chunk_size:
                chunks.append(cur)
                cur = []
        if cur:
            chunks.append(cur)
        return chunks

    @staticmethod
    def build_query_plan(misses, chunk_size=50):
        chunks = BatchContainerEngine.chunk_ids(misses, chunk_size)
        query_chunks = []
        for i, chunk in enumerate(chunks, 1):
            placeholders = ",".join(["?"] * len(chunk))
            header_sql = f"SELECT * FROM `nyx_inventories` WHERE `id` IN ({placeholders})"
            item_sql = f"SELECT * FROM `nyx_inventory_items` WHERE `inventory_id` IN ({placeholders}) ORDER BY `slot` ASC"
            query_chunks.append({
                "chunkIndex": i,
                "ids": chunk,
                "idCount": len(chunk),
                "headerQuery": header_sql,
                "headerParams": chunk,
                "itemQuery": item_sql,
                "itemParams": chunk
            })

        total_misses = len(misses)
        expected_seq = total_misses * 2
        batched_queries = len(chunks) * 2
        queries_saved = max(0, expected_seq - batched_queries)
        ratio = (queries_saved / expected_seq) if expected_seq > 0 else 0.0

        return {
            "chunks": query_chunks,
            "chunkCount": len(chunks),
            "totalMisses": total_misses,
            "expectedSequentialQueries": expected_seq,
            "batchedQueries": batched_queries,
            "queriesSaved": queries_saved,
            "efficiencyRatio": round(ratio, 4)
        }

    @staticmethod
    def calculate_query_savings(container_count, chunk_size=50):
        count = max(0, int(container_count))
        chunk_size = max(1, int(chunk_size))
        if count == 0:
            return 0, 0, 0, 0.0
        seq = count * 2
        chunks = math.ceil(count / chunk_size)
        batched = chunks * 2
        saved = max(0, seq - batched)
        reduction = round((saved / seq) * 100.0, 2)
        return seq, batched, saved, reduction

    @staticmethod
    def group_items_by_inventory(item_rows):
        grouped = {}
        if not isinstance(item_rows, list):
            return grouped
        for row in item_rows:
            inv_id = row.get("inventory_id")
            if inv_id:
                grouped.setdefault(inv_id, []).append(row)
        return grouped

    @staticmethod
    def is_startup_container(inv_id):
        if not isinstance(inv_id, str):
            return False
        return inv_id.startswith("stash:") or inv_id.startswith("property:")


# ============================================================================
# UNIT TESTS
# ============================================================================

def test_sanitize_container_ids():
    raw = [
        "  stash:refinery_in  ",
        "property:apt_integrity_101:main",
        "stash:refinery_in",  # Duplicate
        "",                   # Empty
        None,                 # Non-string
        999,                  # Non-string
        "stash:vinewood_tools",
        "   ",                # Whitespace
        "property:store_vinewood_24:main"
    ]
    clean_list, id_set = BatchContainerEngine.sanitize_container_ids(raw)
    assert len(clean_list) == 4
    assert clean_list[0] == "stash:refinery_in"
    assert clean_list[1] == "property:apt_integrity_101:main"
    assert clean_list[2] == "stash:vinewood_tools"
    assert clean_list[3] == "property:store_vinewood_24:main"
    assert id_set["stash:refinery_in"] is True
    assert id_set["stash:vinewood_tools"] is True


def test_partition_existing_cache():
    ids = [
        "stash:refinery_in",
        "property:apt_integrity_101:main",
        "stash:vinewood_tools",
        "property:store_vinewood_24:main"
    ]
    mock_cache = {
        "stash:refinery_in": {"id": "stash:refinery_in"},
        "stash:vinewood_tools": {"id": "stash:vinewood_tools"}
    }
    hits, misses = BatchContainerEngine.partition_existing(ids, mock_cache)
    assert len(hits) == 2
    assert len(misses) == 2
    assert hits == ["stash:refinery_in", "stash:vinewood_tools"]
    assert misses == ["property:apt_integrity_101:main", "property:store_vinewood_24:main"]


def test_chunk_ids_bounded_arrays():
    bulk = [f"stash:box_{i:03d}" for i in range(1, 126)]
    chunks = BatchContainerEngine.chunk_ids(bulk, chunk_size=50)
    assert len(chunks) == 3
    assert len(chunks[0]) == 50
    assert len(chunks[1]) == 50
    assert len(chunks[2]) == 25
    assert chunks[0][0] == "stash:box_001"
    assert chunks[1][0] == "stash:box_051"
    assert chunks[2][-1] == "stash:box_125"

    # Edge cases
    assert BatchContainerEngine.chunk_ids([], 50) == []
    single_chunk = BatchContainerEngine.chunk_ids(["stash:a", "stash:b"], 50)
    assert len(single_chunk) == 1
    assert len(single_chunk[0]) == 2


def test_build_query_plan_and_placeholders():
    misses = ["stash:refinery_in", "stash:refinery_out", "property:apt_101:main"]
    plan = BatchContainerEngine.build_query_plan(misses, chunk_size=50)

    assert plan["totalMisses"] == 3
    assert plan["chunkCount"] == 1
    assert plan["expectedSequentialQueries"] == 6  # 3 * 2
    assert plan["batchedQueries"] == 2             # 1 * 2
    assert plan["queriesSaved"] == 4
    assert plan["efficiencyRatio"] == 0.6667

    chunk0 = plan["chunks"][0]
    assert chunk0["headerQuery"] == "SELECT * FROM `nyx_inventories` WHERE `id` IN (?,?,?)"
    assert chunk0["itemQuery"] == "SELECT * FROM `nyx_inventory_items` WHERE `inventory_id` IN (?,?,?) ORDER BY `slot` ASC"
    assert chunk0["headerParams"] == misses
    assert chunk0["itemParams"] == misses


def test_calculate_query_savings_math():
    # 40 containers: 80 seq vs 2 batched -> 78 saved (97.5%)
    seq, batched, saved, pct = BatchContainerEngine.calculate_query_savings(40, 50)
    assert seq == 80
    assert batched == 2
    assert saved == 78
    assert pct == 97.5

    # 100 containers: 200 seq vs 4 batched -> 196 saved (98.0%)
    seq, batched, saved, pct = BatchContainerEngine.calculate_query_savings(100, 50)
    assert seq == 200
    assert batched == 4
    assert saved == 196
    assert pct == 98.0

    # 1 container: 2 seq vs 2 batched -> 0 saved (0.0%)
    seq, batched, saved, pct = BatchContainerEngine.calculate_query_savings(1, 50)
    assert seq == 2
    assert batched == 2
    assert saved == 0
    assert pct == 0.0

    # 0 containers
    seq, batched, saved, pct = BatchContainerEngine.calculate_query_savings(0, 50)
    assert seq == 0
    assert batched == 0
    assert saved == 0
    assert pct == 0.0


def test_group_items_by_inventory():
    items = [
        {"item_uuid": "u1", "inventory_id": "stash:chem_in", "slot": 1, "item_id": "oil", "amount": 20},
        {"item_uuid": "u2", "inventory_id": "property:villa:main", "slot": 1, "item_id": "cash", "amount": 500},
        {"item_uuid": "u3", "inventory_id": "stash:chem_in", "slot": 2, "item_id": "catalyst", "amount": 2},
        {"item_uuid": "u4", "inventory_id": "property:villa:main", "slot": 2, "item_id": "gold_bar", "amount": 1},
        {"item_uuid": "u5", "inventory_id": "stash:tools", "slot": 1, "item_id": "wrench", "amount": 5}
    ]
    grouped = BatchContainerEngine.group_items_by_inventory(items)
    assert len(grouped["stash:chem_in"]) == 2
    assert len(grouped["property:villa:main"]) == 2
    assert len(grouped["stash:tools"]) == 1
    assert grouped["stash:chem_in"][0]["item_id"] == "oil"
    assert grouped["stash:chem_in"][1]["item_id"] == "catalyst"
    assert grouped["property:villa:main"][1]["item_id"] == "gold_bar"


def test_startup_container_pattern_recognition():
    assert BatchContainerEngine.is_startup_container("stash:refinery_in") is True
    assert BatchContainerEngine.is_startup_container("stash:vinewood_tools") is True
    assert BatchContainerEngine.is_startup_container("stash:pillbox_meds") is True
    assert BatchContainerEngine.is_startup_container("property:apt_integrity_101:main") is True
    assert BatchContainerEngine.is_startup_container("property:wh_elysian_04:main") is True

    # Non-startup containers
    assert BatchContainerEngine.is_startup_container("char:CITIZEN_001:main") is False
    assert BatchContainerEngine.is_startup_container("drop:f89a2b1c") is False
    assert BatchContainerEngine.is_startup_container("trunk:ABC12345") is False
    assert BatchContainerEngine.is_startup_container("glovebox:XYZ98765") is False
    assert BatchContainerEngine.is_startup_container(12345) is False
    assert BatchContainerEngine.is_startup_container(None) is False


def test_batch_load_simulation_hot_and_cold():
    """Simulate complete batch loading workflow with mock database and hot cache."""
    hot_cache = {
        "stash:cached_01": {"id": "stash:cached_01", "items": [{"slot": 1, "item_id": "iron"}]}
    }

    mock_db_inventories = {
        "stash:cold_01": {
            "id": "stash:cold_01", "type": "stash", "max_weight": 500000, "max_slots": 60,
            "coords": '{"x": 100.0, "y": 200.0, "z": 30.0}', "last_decay_at": 1000
        },
        "property:cold_02": {
            "id": "property:cold_02", "type": "stash", "max_weight": 100000, "max_slots": 50,
            "coords": None, "last_decay_at": 1000
        }
    }

    mock_db_items = [
        {"item_uuid": "item-1", "inventory_id": "stash:cold_01", "slot": 1, "item_id": "fuel", "amount": 100},
        {"item_uuid": "item-2", "inventory_id": "property:cold_02", "slot": 1, "item_id": "deed", "amount": 1}
    ]

    requested = ["stash:cached_01", "stash:cold_01", "property:cold_02", "stash:unpersisted_03"]

    clean, _ = BatchContainerEngine.sanitize_container_ids(requested)
    hits, misses = BatchContainerEngine.partition_existing(clean, hot_cache)

    results = {}
    for h in hits:
        results[h] = hot_cache[h]

    assert len(results) == 1
    assert "stash:cached_01" in results

    plan = BatchContainerEngine.build_query_plan(misses, chunk_size=50)
    assert plan["batchedQueries"] == 2
    assert plan["queriesSaved"] == 4

    # Simulated DB fetch
    for chunk in plan["chunks"]:
        inv_rows = [mock_db_inventories[cid] for cid in chunk["ids"] if cid in mock_db_inventories]
        found_ids = {r["id"] for r in inv_rows}
        item_rows = [it for it in mock_db_items if it["inventory_id"] in found_ids]
        grouped = BatchContainerEngine.group_items_by_inventory(item_rows)

        for inv in inv_rows:
            cid = inv["id"]
            results[cid] = {
                "id": cid,
                "type": inv["type"],
                "maxWeight": inv["max_weight"],
                "maxSlots": inv["max_slots"],
                "items": grouped.get(cid, [])
            }
            hot_cache[cid] = results[cid]

        # Auto-create unpersisted
        for cid in chunk["ids"]:
            if cid not in found_ids:
                new_c = {"id": cid, "type": "stash", "maxWeight": 100000, "maxSlots": 40, "items": []}
                results[cid] = new_c
                hot_cache[cid] = new_c

    assert len(results) == 4
    assert results["stash:cached_01"]["id"] == "stash:cached_01"
    assert results["stash:cold_01"]["maxWeight"] == 500000
    assert len(results["stash:cold_01"]["items"]) == 1
    assert results["stash:cold_01"]["items"][0]["item_id"] == "fuel"
    assert results["property:cold_02"]["maxSlots"] == 50
    assert results["stash:unpersisted_03"]["id"] == "stash:unpersisted_03"


def test_fxmanifest_and_source_integrity():
    """Verify that all files declare and use the batched container queries API."""
    inv_manifest = os.path.join(ROOT_DIR, "FiveM", "nyx_inventory", "fxmanifest.lua")
    with open(inv_manifest, "r", encoding="utf-8") as f:
        inv_manifest_content = f.read()
    assert "shared/batch.lua" in inv_manifest_content, "shared/batch.lua not declared in nyx_inventory fxmanifest"

    inv_exports = os.path.join(ROOT_DIR, "FiveM", "nyx_inventory", "server", "exports.lua")
    with open(inv_exports, "r", encoding="utf-8") as f:
        inv_exports_content = f.read()
    assert 'exports("BatchLoadInventories"' in inv_exports_content
    assert 'exports("PreloadInventories"' in inv_exports_content
    assert 'exports("GetInventoriesBatch"' in inv_exports_content
    assert 'exports("RegisterContainersBatch"' in inv_exports_content

    inv_state = os.path.join(ROOT_DIR, "FiveM", "nyx_inventory", "server", "state.lua")
    with open(inv_state, "r", encoding="utf-8") as f:
        inv_state_content = f.read()
    assert "function Nyx.Inventory.HydrateContainerFromRow" in inv_state_content
    assert "function Nyx.Inventory.BatchLoad" in inv_state_content
    assert "SELECT `id` FROM `nyx_inventories`" in inv_state_content

    # Logistics facilities batching
    fac_file = os.path.join(ROOT_DIR, "FiveM", "nyx_logistics", "server", "facilities.lua")
    with open(fac_file, "r", encoding="utf-8") as f:
        fac_content = f.read()
    assert "BatchLoadInventories(stashIds" in fac_content

    # Logistics shelves batching
    shelves_file = os.path.join(ROOT_DIR, "FiveM", "nyx_logistics", "server", "shelves.lua")
    with open(shelves_file, "r", encoding="utf-8") as f:
        shelves_content = f.read()
    assert "BatchLoadInventories(shelfInvIds" in shelves_content

    # Logistics pallets batching
    pallets_file = os.path.join(ROOT_DIR, "FiveM", "nyx_logistics", "server", "pallets.lua")
    with open(pallets_file, "r", encoding="utf-8") as f:
        pallets_content = f.read()
    assert "BatchLoadInventories(palletInvIds" in pallets_content

    # Properties stashes batching
    prop_file = os.path.join(ROOT_DIR, "FiveM", "nyx_properties", "server", "main.lua")
    with open(prop_file, "r", encoding="utf-8") as f:
        prop_content = f.read()
    assert "BatchLoadInventories(stashIds" in prop_content

    # Core in-engine test suite
    tests_file = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "server", "tests.lua")
    with open(tests_file, "r", encoding="utf-8") as f:
        tests_content = f.read()
    assert "function Nyx.Tests.TestBatchedContainerQueriesOnBoot()" in tests_content
    assert "local t27 = Nyx.Tests.TestBatchedContainerQueriesOnBoot()" in tests_content
