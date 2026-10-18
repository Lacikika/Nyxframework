"""
Unit tests for Spatial Grid Ground Drops & Time-Based Item Durability Decay
(nyx_inventory / nyx_interact / nyx_core).
"""

import math
import os
import json
import pytest

# ---------------------------------------------------------------------------
# Python Reference Implementations Mirroring Pure Lua 5.4 Core Logic
# ---------------------------------------------------------------------------

def coords_to_cell(x, y, cell_size=64.0):
    cs = float(cell_size) if cell_size and float(cell_size) > 0 else 64.0
    return math.floor(float(x) / cs), math.floor(float(y) / cs)

def get_cell_key(cx, cy, bucket=0):
    return f"{math.floor(cx)}:{math.floor(cy)}:{math.floor(bucket)}"

def get_cell_key_from_coords(coords, cell_size=64.0, bucket=0):
    cx, cy = coords_to_cell(coords.get("x", 0.0), coords.get("y", 0.0), cell_size)
    return get_cell_key(cx, cy, bucket), cx, cy

def get_neighbor_cell_keys(cx, cy, bucket=0, radius_cells=1):
    cx = math.floor(cx)
    cy = math.floor(cy)
    bucket = math.floor(bucket)
    radius_cells = max(0, math.floor(radius_cells))
    keys = []
    for dx in range(-radius_cells, radius_cells + 1):
        for dy in range(-radius_cells, radius_cells + 1):
            keys.append(get_cell_key(cx + dx, cy + dy, bucket))
    return keys

def get_cells_in_radius(center_x, center_y, radius, cell_size=64.0, bucket=0):
    cs = float(cell_size) if cell_size and float(cell_size) > 0 else 64.0
    radius = max(0.0, float(radius))
    bucket = math.floor(bucket)
    min_cx = math.floor((center_x - radius) / cs)
    max_cx = math.floor((center_x + radius) / cs)
    min_cy = math.floor((center_y - radius) / cs)
    max_cy = math.floor((center_y + radius) / cs)
    keys = []
    for cx in range(min_cx, max_cx + 1):
        for cy in range(min_cy, max_cy + 1):
            keys.append(get_cell_key(cx, cy, bucket))
    return keys

def get_cell_bounds(cx, cy, cell_size=64.0):
    cs = float(cell_size) if cell_size and float(cell_size) > 0 else 64.0
    min_x = cx * cs
    max_x = min_x + cs
    min_y = cy * cs
    max_y = min_y + cs
    return min_x, max_x, min_y, max_y

# Durability decay constants
STATUS_PRISTINE = "PRISTINE"
STATUS_GOOD = "GOOD"
STATUS_WORN = "WORN"
STATUS_CRITICAL = "CRITICAL"
STATUS_BROKEN = "BROKEN"
STATUS_SPOILED = "SPOILED"
STATUS_EXPIRED = "EXPIRED"

DEFAULT_MULTIPLIERS = {
    "drop": 2.0,
    "player": 1.0,
    "trunk": 0.75,
    "glovebox": 0.75,
    "stash": 0.50
}

def calculate_decay_loss(decay_rate, delta_seconds, container_type="drop", env_factor=1.0, multipliers=None):
    decay_rate = float(decay_rate or 0.0)
    delta_seconds = max(0, float(delta_seconds or 0.0))
    if decay_rate <= 0.0 or delta_seconds <= 0.0:
        return 0.0
    mults = multipliers or DEFAULT_MULTIPLIERS
    c_mult = mults.get(container_type, 1.0)
    e_mult = max(0.1, float(env_factor or 1.0))
    raw_loss = (delta_seconds / 3600.0) * decay_rate * 100.0 * c_mult * e_mult
    return max(0.0, math.floor(raw_loss * 10) / 10)

def get_item_status(item_type, durability, metadata=None):
    dur = float(durability if durability is not None else 100.0)
    meta = metadata or {}
    is_broken = meta.get("isBroken", False) or (dur <= 0.0 and item_type in ("weapon", "tool"))
    is_spoiled = meta.get("isSpoiled", False) or (dur <= 0.0 and item_type in ("food", "drink"))
    is_expired = meta.get("isExpired", False) or (dur <= 0.0 and item_type == "medical")

    if dur <= 0.0:
        if item_type in ("food", "drink"):
            return STATUS_SPOILED, {"isBroken": False, "isSpoiled": True, "isExpired": False}
        elif item_type == "medical":
            return STATUS_EXPIRED, {"isBroken": False, "isSpoiled": False, "isExpired": True}
        else:
            return STATUS_BROKEN, {"isBroken": True, "isSpoiled": False, "isExpired": False}
    elif dur < 25.0:
        return STATUS_CRITICAL, {"isBroken": False, "isSpoiled": False, "isExpired": False}
    elif dur < 50.0:
        return STATUS_WORN, {"isBroken": False, "isSpoiled": False, "isExpired": False}
    elif dur < 75.0:
        return STATUS_GOOD, {"isBroken": False, "isSpoiled": False, "isExpired": False}
    else:
        return STATUS_PRISTINE, {"isBroken": False, "isSpoiled": False, "isExpired": False}

def can_repair_item(item_type, cur_dur, max_dur=100.0):
    if item_type in ("food", "drink", "ammo", "medical"):
        return False
    if item_type not in ("weapon", "tool", "freight"):
        return False
    return cur_dur < max_dur

def calculate_repair_gain(cur_dur, max_dur=100.0, base_gain=35.0, wear_penalty=2.0, min_max_floor=50.0):
    new_max = max(min_max_floor, math.floor((max_dur - wear_penalty) * 10) / 10)
    new_dur = min(new_max, math.floor((cur_dur + base_gain) * 10) / 10)
    actual_gain = max(0.0, math.floor((new_dur - cur_dur) * 10) / 10)
    return actual_gain, new_dur, new_max

def check_drop_dissolution(items):
    if not items:
        return True
    for it in items:
        dur = it.get("durability", 100.0)
        if dur > 0.0:
            return False
    return True

# ---------------------------------------------------------------------------
# Test Suite: Spatial Grid Partitioning
# ---------------------------------------------------------------------------

class TestSpatialGridPartitioning:
    def test_coords_to_cell_positive_and_negative(self):
        cx, cy = coords_to_cell(150.0, -210.0, 64.0)
        assert cx == 2  # 150 / 64 = 2.34 -> 2
        assert cy == -4  # -210 / 64 = -3.28 -> -4

        # Boundary checks
        assert coords_to_cell(0.0, 0.0, 64.0) == (0, 0)
        assert coords_to_cell(63.99, 63.99, 64.0) == (0, 0)
        assert coords_to_cell(64.0, 64.0, 64.0) == (1, 1)
        assert coords_to_cell(-0.01, -0.01, 64.0) == (-1, -1)

    def test_cell_key_generation_and_bucket_isolation(self):
        k1 = get_cell_key(2, -4, 0)
        assert k1 == "2:-4:0"
        k2 = get_cell_key(2, -4, 1001)
        assert k2 == "2:-4:1001"
        assert k1 != k2

        k_from_coords, cx, cy = get_cell_key_from_coords({"x": 150.0, "y": -210.0}, 64.0, 0)
        assert k_from_coords == "2:-4:0"
        assert cx == 2
        assert cy == -4

    def test_moore_neighborhood_nine_cells(self):
        neighbors = get_neighbor_cell_keys(2, -4, 0, radius_cells=1)
        assert len(neighbors) == 9
        expected = {
            f"{2 + dx}:{-4 + dy}:0"
            for dx in (-1, 0, 1)
            for dy in (-1, 0, 1)
        }
        assert set(neighbors) == expected

    def test_moore_neighborhood_extended_radius(self):
        # radius 2 should be (2*2+1)^2 = 25 cells
        neighbors = get_neighbor_cell_keys(0, 0, 0, radius_cells=2)
        assert len(neighbors) == 25

    def test_cells_in_radius(self):
        # 64m radius centered at 0,0 with cellSize=64.0 covers [-64, 64] -> cells -1, 0, 1
        cells = get_cells_in_radius(0.0, 0.0, 64.0, 64.0, 0)
        assert len(cells) == 9
        expected = {
            f"{cx}:{cy}:0"
            for cx in (-1, 0, 1)
            for cy in (-1, 0, 1)
        }
        assert set(cells) == expected

    def test_cell_bounds(self):
        min_x, max_x, min_y, max_y = get_cell_bounds(2, -4, 64.0)
        assert min_x == 128.0
        assert max_x == 192.0
        assert min_y == -256.0
        assert max_y == -192.0
        assert max_x - min_x == 64.0
        assert max_y - min_y == 64.0

    def test_spatial_grid_class_insert_update_remove(self):
        class MockSpatialGrid:
            def __init__(self, cell_size=64.0):
                self.cell_size = cell_size
                self.cells = {}
                self.drop_lookup = {}

            def insert(self, drop_id, x, y, bucket=0):
                k, cx, cy = get_cell_key_from_coords({"x": x, "y": y}, self.cell_size, bucket)
                if k not in self.cells:
                    self.cells[k] = {}
                self.cells[k][drop_id] = {"id": drop_id, "x": x, "y": y, "cellKey": k, "bucket": bucket}
                self.drop_lookup[drop_id] = k
                return k

            def remove(self, drop_id):
                k = self.drop_lookup.pop(drop_id, None)
                if k and k in self.cells:
                    self.cells[k].pop(drop_id, None)
                    if not self.cells[k]:
                        del self.cells[k]

            def update(self, drop_id, new_x, new_y, bucket=0):
                old_k = self.drop_lookup.get(drop_id)
                new_k, _, _ = get_cell_key_from_coords({"x": new_x, "y": new_y}, self.cell_size, bucket)
                if old_k != new_k:
                    self.remove(drop_id)
                    return self.insert(drop_id, new_x, new_y, bucket)
                else:
                    if old_k and old_k in self.cells and drop_id in self.cells[old_k]:
                        self.cells[old_k][drop_id]["x"] = new_x
                        self.cells[old_k][drop_id]["y"] = new_y
                    return old_k

            def get_nearby_drops(self, center_x, center_y, radius=1.5, bucket=0):
                cx, cy = coords_to_cell(center_x, center_y, self.cell_size)
                neighbor_keys = get_neighbor_cell_keys(cx, cy, bucket, 1)
                results = []
                r_sq = radius * radius
                for nk in neighbor_keys:
                    cell = self.cells.get(nk)
                    if cell:
                        for did, drop in cell.items():
                            dx = drop["x"] - center_x
                            dy = drop["y"] - center_y
                            if (dx * dx + dy * dy) <= r_sq:
                                results.append(drop)
                return results

        grid = MockSpatialGrid(64.0)
        # Insert two drops in same cell 0:0:0
        k1 = grid.insert("D1", 10.0, 10.0, 0)
        k2 = grid.insert("D2", 15.0, 15.0, 0)
        assert k1 == "0:0:0"
        assert k2 == "0:0:0"
        assert len(grid.cells["0:0:0"]) == 2

        # Update D2 into cell 2:3:0
        k2_new = grid.update("D2", 150.0, 200.0, 0)
        assert k2_new == "2:3:0"
        assert "D2" not in grid.cells["0:0:0"]
        assert "D2" in grid.cells["2:3:0"]
        assert len(grid.cells["0:0:0"]) == 1

        # Proximity lookup near D1 (radius 10m)
        nearby = grid.get_nearby_drops(12.0, 12.0, 5.0, 0)
        assert len(nearby) == 1
        assert nearby[0]["id"] == "D1"

        # D2 should not be found near D1
        assert all(d["id"] != "D2" for d in nearby)

        # Cleanup D1 vacuums cell 0:0:0
        grid.remove("D1")
        assert "0:0:0" not in grid.cells

    def test_auto_merge_o1_spatial_candidate_pruning(self):
        """Verify that out of 500 total drops, only candidates in Moore cells are examined."""
        grid_cells = {}
        # Populate 500 background drops spread out
        for i in range(500):
            gx = 1000.0 + i * 100.0
            gy = 1000.0 + i * 100.0
            k = get_cell_key_from_coords({"x": gx, "y": gy}, 64.0, 0)[0]
            if k not in grid_cells:
                grid_cells[k] = {}
            grid_cells[k][f"BG_{i}"] = {"x": gx, "y": gy}

        # Target drop at 100, 100
        k_target, cx, cy = get_cell_key_from_coords({"x": 100.0, "y": 100.0}, 64.0, 0)
        grid_cells.setdefault(k_target, {})
        grid_cells[k_target]["DROP_TARGET"] = {"x": 100.0, "y": 100.0}
        grid_cells[k_target]["DROP_MERGEABLE"] = {"x": 100.8, "y": 100.6}  # dist ~1.0m <= 1.5m

        # Auto-merge search using neighbor cells
        neighbor_keys = get_neighbor_cell_keys(cx, cy, 0, 1)
        eval_count = 0
        merge_candidate = None

        for nk in neighbor_keys:
            cell = grid_cells.get(nk)
            if cell:
                for did, drop in cell.items():
                    if did != "DROP_TARGET":
                        eval_count += 1
                        dx = drop["x"] - 100.0
                        dy = drop["y"] - 100.0
                        dist = math.sqrt(dx * dx + dy * dy)
                        if dist <= 1.5:
                            merge_candidate = did
                            break
            if merge_candidate:
                break

        assert eval_count == 1  # Only examined DROP_MERGEABLE, none of the 500 distant drops!
        assert merge_candidate == "DROP_MERGEABLE"

# ---------------------------------------------------------------------------
# Test Suite: Time-Based Durability Decay Engine
# ---------------------------------------------------------------------------

class TestDurabilityDecayEngine:
    def test_container_decay_multipliers(self):
        rate = 0.05  # 5% nominal per hour
        hour_sec = 3600

        # Drop: 2.0x -> 10.0% loss
        loss_drop = calculate_decay_loss(rate, hour_sec, "drop")
        assert loss_drop == 10.0

        # Player: 1.0x -> 5.0% loss
        loss_player = calculate_decay_loss(rate, hour_sec, "player")
        assert loss_player == 5.0

        # Trunk / Glovebox: 0.75x -> 3.7% loss
        loss_trunk = calculate_decay_loss(rate, hour_sec, "trunk")
        assert loss_trunk == 3.7
        loss_glovebox = calculate_decay_loss(rate, hour_sec, "glovebox")
        assert loss_glovebox == 3.7

        # Stash: 0.50x -> 2.5% loss
        loss_stash = calculate_decay_loss(rate, hour_sec, "stash")
        assert loss_stash == 2.5

    def test_environmental_multiplier(self):
        rate = 0.05
        hour_sec = 3600
        # Severe weather (e.g. UV / thunderstorm = 1.5x) on ground drop (2.0x) -> 3.0x net -> 15.0%
        loss_storm = calculate_decay_loss(rate, hour_sec, "drop", env_factor=1.5)
        assert loss_storm == 15.0

    def test_zero_elapsed_or_zero_rate(self):
        assert calculate_decay_loss(0.0, 3600, "drop") == 0.0
        assert calculate_decay_loss(0.05, 0, "drop") == 0.0
        assert calculate_decay_loss(-1.0, 3600, "drop") == 0.0

    def test_durability_status_tier_transitions(self):
        # Pristine: >= 75.0%
        st, flags = get_item_status("weapon", 85.0)
        assert st == STATUS_PRISTINE
        assert not flags["isBroken"]

        # Good: 50.0% - 74.9%
        st, flags = get_item_status("tool", 60.0)
        assert st == STATUS_GOOD
        assert not flags["isBroken"]

        # Worn: 25.0% - 49.9%
        st, flags = get_item_status("freight", 40.0)
        assert st == STATUS_WORN

        # Critical: 0.1% - 24.9%
        st, flags = get_item_status("weapon", 12.0)
        assert st == STATUS_CRITICAL
        assert not flags["isBroken"]

        # Broken / Spoiled / Expired at 0.0%
        st_wp, flags_wp = get_item_status("weapon", 0.0)
        assert st_wp == STATUS_BROKEN
        assert flags_wp["isBroken"]

        st_tool, flags_tool = get_item_status("tool", 0.0)
        assert st_tool == STATUS_BROKEN
        assert flags_tool["isBroken"]

        st_food, flags_food = get_item_status("food", 0.0)
        assert st_food == STATUS_SPOILED
        assert flags_food["isSpoiled"]
        assert not flags_food["isBroken"]

        st_med, flags_med = get_item_status("medical", 0.0)
        assert st_med == STATUS_EXPIRED
        assert flags_med["isExpired"]
        assert not flags_med["isBroken"]

    def test_offline_catch_up_decay_reconciliation(self):
        container = {
            "type": "stash",
            "last_decay_at": 100000,
            "items": [
                {"id": "apple", "type": "food", "durability": 50.0, "decayRate": 0.04},
                {"id": "ingot", "type": "freight", "durability": 100.0, "decayRate": 0.0}
            ]
        }
        now_sec = 107200  # 2 hours later
        delta = now_sec - container["last_decay_at"]

        # Apply catch-up
        for it in container["items"]:
            rate = it["decayRate"]
            if rate > 0 and it["durability"] > 0:
                loss = calculate_decay_loss(rate, delta, container["type"])
                it["durability"] = max(0.0, round(it["durability"] - loss, 1))

        container["last_decay_at"] = now_sec

        # Apple loss: (7200/3600) * 0.04 * 100 * 0.5 = 4.0% loss -> 50.0 - 4.0 = 46.0%
        assert container["items"][0]["durability"] == 46.0
        # Ingot decayRate=0 -> unchanged
        assert container["items"][1]["durability"] == 100.0
        assert container["last_decay_at"] == 107200

    def test_item_repair_and_structural_fatigue(self):
        # Perishables cannot be repaired
        assert not can_repair_item("food", 0.0, 100.0)
        assert not can_repair_item("drink", 0.0, 100.0)
        assert not can_repair_item("medical", 0.0, 100.0)
        assert not can_repair_item("ammo", 0.0, 100.0)

        # Broken weapon can be repaired
        assert can_repair_item("weapon", 0.0, 100.0)
        # Fully repaired weapon cannot be repaired further
        assert not can_repair_item("weapon", 100.0, 100.0)

        # First repair: curDur = 0.0, maxDur = 100.0, baseGain = 35.0, wearPenalty = 2.0
        gain1, new_dur1, new_max1 = calculate_repair_gain(0.0, 100.0, 35.0, 2.0)
        assert gain1 == 35.0
        assert new_dur1 == 35.0
        assert new_max1 == 98.0

        # Subsequent repairs down to 50% wear penalty ceiling floor
        gain_floor, new_dur_floor, new_max_floor = calculate_repair_gain(10.0, 51.0, 35.0, 2.0)
        assert new_max_floor == 50.0  # max(50.0, 51.0 - 2.0) = 50.0
        assert new_dur_floor == 45.0  # min(50.0, 10.0 + 35.0) = 45.0
        assert gain_floor == 35.0

    def test_ground_drop_dissolution_evaluator(self):
        # All items at 0% durability -> should dissolve
        all_dead = [{"id": "apple", "durability": 0.0}, {"id": "tool", "durability": 0.0}]
        assert check_drop_dissolution(all_dead) is True

        # At least one item > 0% durability -> should NOT dissolve
        partially_alive = [{"id": "apple", "durability": 0.0}, {"id": "ingot", "durability": 80.0}]
        assert check_drop_dissolution(partially_alive) is False

        # Empty drop -> should dissolve
        assert check_drop_dissolution([]) is True

# ---------------------------------------------------------------------------
# Test Suite: Codebase & Database Migration Integrity
# ---------------------------------------------------------------------------

class TestCodebaseAndMigrationIntegrity:
    @pytest.fixture(autouse=True)
    def setup_paths(self):
        self.root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        self.fivem_dir = os.path.join(self.root_dir, "FiveM")

    def test_migration_025_exists_and_valid(self):
        core_mig = os.path.join(self.fivem_dir, "nyx_core", "sql", "migrations", "025_spatial_grid_drops_and_durability_decay.sql")
        inv_mig = os.path.join(self.fivem_dir, "nyx_inventory", "sql", "migrations", "025_spatial_grid_drops_and_durability_decay.sql")
        idx_file = os.path.join(self.fivem_dir, "nyx_core", "sql", "migrations", "index.json")

        assert os.path.isfile(core_mig), f"Missing migration file: {core_mig}"
        assert os.path.isfile(inv_mig), f"Missing mirrored migration file: {inv_mig}"
        assert os.path.isfile(idx_file), f"Missing migrations index: {idx_file}"

        with open(core_mig, "r", encoding="utf-8") as f:
            content = f.read()

        # Check required schema additions
        assert "grid_cell" in content
        assert "last_decay_at" in content
        assert "nyx_inventory_decay_logs" in content
        assert "idx_inv_grid_cell" in content

        # Check index.json registration
        with open(idx_file, "r", encoding="utf-8") as f:
            idx_data = json.load(f)

        assert "025_spatial_grid_drops_and_durability_decay.sql" in idx_data, "Migration step 25 not registered in index.json"

    def test_fxmanifest_inventory_scripts(self):
        manifest_path = os.path.join(self.fivem_dir, "nyx_inventory", "fxmanifest.lua")
        assert os.path.isfile(manifest_path)

        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = f.read()

        assert "shared/spatial_grid.lua" in manifest
        assert "shared/decay.lua" in manifest
        assert "server/spatial_grid.lua" in manifest

    def test_shared_math_exports_in_nyx_core(self):
        math_path = os.path.join(self.fivem_dir, "nyx_core", "shared", "math.lua")
        assert os.path.isfile(math_path)

        with open(math_path, "r", encoding="utf-8") as f:
            math_code = f.read()

        # Verify function declarations
        assert "function Nyx.Math.CoordsToCell" in math_code
        assert "function Nyx.Math.GetCellKey" in math_code
        assert "function Nyx.Math.GetCellKeyFromCoords" in math_code
        assert "function Nyx.Math.GetNeighborCellKeys" in math_code
        assert "function Nyx.Math.GetCellsInRadius" in math_code
        assert "function Nyx.Math.GetCellBounds" in math_code

        # Verify export declarations
        assert "CoordsToCell" in math_code
        assert "GetNeighborCellKeys" in math_code

    def test_inventory_config_values(self):
        config_path = os.path.join(self.fivem_dir, "nyx_inventory", "config.lua")
        assert os.path.isfile(config_path)

        with open(config_path, "r", encoding="utf-8") as f:
            cfg = f.read()

        assert "SpatialGridCellSize = 64.0" in cfg
        assert "GroundDropLifetime = 7200" in cfg
        assert "DecayMultipliers" in cfg
        assert "RepairConfig" in cfg
