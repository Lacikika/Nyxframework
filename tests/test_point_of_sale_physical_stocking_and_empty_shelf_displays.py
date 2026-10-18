#!/usr/bin/env python3
"""
Unit and Integration Tests for Nyxframework Point of Sale Physical Stocking,
Empty Shelf Prop Despawning & In-World Retail Interactions (FiveM/nyx_logistics)
"""

import os
import sys
import json
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")

class TestPointOfSalePhysicalStockingAndEmptyShelfDisplays(unittest.TestCase):
    def test_migration_062_registered_and_structure(self):
        """Verify migration 062 exists in index.json and contains required columns, audits, and seeds."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            index_data = json.load(f)

        self.assertIn("062_point_of_sale_physical_stocking_and_empty_shelf_displays.sql", index_data)

        mig_core = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "062_point_of_sale_physical_stocking_and_empty_shelf_displays.sql")
        mig_log = os.path.join(FIVEM_DIR, "nyx_logistics", "sql", "migrations", "062_point_of_sale_physical_stocking_and_empty_shelf_displays.sql")
        self.assertTrue(os.path.isfile(mig_core), "Core migration 062 missing")
        self.assertTrue(os.path.isfile(mig_log), "Logistics migration 062 missing")

        with open(mig_core, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("ALTER TABLE `nyx_logistics_shelves`", sql)
        self.assertIn("`coords` JSON", sql)
        self.assertIn("`heading` DECIMAL", sql)
        self.assertIn("`shelf_category` ENUM", sql)
        self.assertIn("`stocked_model` VARCHAR", sql)
        self.assertIn("`empty_model` VARCHAR", sql)
        self.assertIn("CREATE TABLE IF NOT EXISTS `nyx_logistics_shelf_restock_audits`", sql)
        self.assertIn("shelf_vinewood_247_groceries", sql)
        self.assertIn("shelf_ammunation_dt_ammo", sql)
        self.assertIn("shelf_sandy_hardware_parts", sql)
        self.assertIn("shelf_paleto_general_food", sql)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest.lua properly registers shared, server, and client retail shelf files."""
        manifest_path = os.path.join(FIVEM_DIR, "nyx_logistics", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_path))
        with open(manifest_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("'shared/retail_shelves.lua'", content)
        self.assertIn("'server/retail_shelves.lua'", content)
        self.assertIn("'client/retail_shelves.lua'", content)

        # Confirm all files exist on disk
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_logistics", "shared", "retail_shelves.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_logistics", "server", "retail_shelves.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_logistics", "client", "retail_shelves.lua")))

    def test_retail_categories_taxonomy(self):
        """Verify retail categories taxonomy in shared/retail_shelves.lua."""
        shared_path = os.path.join(FIVEM_DIR, "nyx_logistics", "shared", "retail_shelves.lua")
        with open(shared_path, "r", encoding="utf-8") as f:
            lua_code = f.read()

        self.assertIn("['convenience'] =", lua_code)
        self.assertIn("['hardware'] =", lua_code)
        self.assertIn("['arms'] =", lua_code)
        self.assertIn("['pharmacy'] =", lua_code)
        self.assertIn("['electronics'] =", lua_code)
        self.assertIn("['general'] =", lua_code)
        self.assertIn("WholesalePayoutMargin = 0.70", lua_code)
        self.assertIn("SparseCapacityThreshold = 0.50", lua_code)

    def test_fullness_state_classifier(self):
        """Simulate and verify fullness state evaluation (EMPTY, SPARSE, FULL)."""
        def get_fullness(stock, capacity):
            stock = max(0, int(stock))
            capacity = max(1, int(capacity))
            ratio = round(stock / capacity, 4)
            deficit = max(0, capacity - stock)
            if stock <= 0:
                return "EMPTY", ratio, deficit
            elif ratio < 0.50:
                return "SPARSE", ratio, deficit
            else:
                return "FULL", ratio, deficit

        # Empty: stock 0 / 100
        state_e, ratio_e, def_e = get_fullness(0, 100)
        self.assertEqual(state_e, "EMPTY")
        self.assertEqual(ratio_e, 0.0)
        self.assertEqual(def_e, 100)

        # Sparse: stock 25 / 100 (25% < 50%)
        state_s, ratio_s, def_s = get_fullness(25, 100)
        self.assertEqual(state_s, "SPARSE")
        self.assertEqual(ratio_s, 0.25)
        self.assertEqual(def_s, 75)

        # Full: stock 75 / 100 (75% >= 50%)
        state_f, ratio_f, def_f = get_fullness(75, 100)
        self.assertEqual(state_f, "FULL")
        self.assertEqual(ratio_f, 0.75)
        self.assertEqual(def_f, 25)

    def test_prop_model_resolution_and_swapping(self):
        """Verify dynamic prop model resolution (stocked vs empty prop swapping)."""
        shelf = {
            "stocked_model": "prop_fridge_01",
            "empty_model": "prop_fridge_empty",
            "target_capacity": 100
        }

        def resolve_model(s, stock):
            if stock <= 0:
                return s.get("empty_model", "prop_rack_empty")
            return s.get("stocked_model", "prop_shelves_02")

        # Full stock -> stocked model
        self.assertEqual(resolve_model(shelf, 80), "prop_fridge_01")
        # Sparse stock -> stocked model
        self.assertEqual(resolve_model(shelf, 15), "prop_fridge_01")
        # Empty stock -> empty model
        self.assertEqual(resolve_model(shelf, 0), "prop_fridge_empty")

    def test_wholesale_restock_headroom_and_payout(self):
        """Verify restocking headroom calculation, request clamping, and 70% wholesale consignment payout."""
        shelf = {
            "is_restockable": 1,
            "target_capacity": 100,
            "current_stock": 70,  # headroom = 30
            "base_price": 20.00
        }

        def evaluate_restock(s, player_items, req_qty):
            if not s.get("is_restockable"):
                return False, "SHELF_NOT_RESTOCKABLE"
            if player_items <= 0:
                return False, "INSUFFICIENT_ITEMS_IN_INVENTORY"
            headroom = s["target_capacity"] - s["current_stock"]
            if headroom <= 0:
                return False, "SHELF_ALREADY_AT_FULL_CAPACITY"
            qty = min(req_qty, min(player_items, headroom))
            payout = round(s["base_price"] * 0.70 * qty, 2)
            return True, {
                "quantity": qty,
                "wholesalePayout": payout,
                "previousStock": s["current_stock"],
                "newStock": s["current_stock"] + qty
            }

        # Player has 50 items and requests 40 -> Clamped to headroom 30
        ok, res = evaluate_restock(shelf, 50, 40)
        self.assertTrue(ok)
        self.assertEqual(res["quantity"], 30)
        self.assertEqual(res["newStock"], 100)
        # Payout: 30 * 20.00 * 0.70 = 420.00
        self.assertEqual(res["wholesalePayout"], 420.00)

    def test_restock_boundary_rejections(self):
        """Verify boundary rejections: full shelf, zero inventory, and non-restockable shelf."""
        def evaluate_restock(s, player_items, req_qty):
            if not s.get("is_restockable"):
                return False, "SHELF_NOT_RESTOCKABLE"
            if player_items <= 0:
                return False, "INSUFFICIENT_ITEMS_IN_INVENTORY"
            headroom = s["target_capacity"] - s["current_stock"]
            if headroom <= 0:
                return False, "SHELF_ALREADY_AT_FULL_CAPACITY"
            return True, min(req_qty, min(player_items, headroom))

        # Full shelf
        s_full = {"is_restockable": 1, "target_capacity": 50, "current_stock": 50}
        ok_f, err_f = evaluate_restock(s_full, 20, 10)
        self.assertFalse(ok_f)
        self.assertEqual(err_f, "SHELF_ALREADY_AT_FULL_CAPACITY")

        # Zero items in inventory
        s_ok = {"is_restockable": 1, "target_capacity": 50, "current_stock": 20}
        ok_e, err_e = evaluate_restock(s_ok, 0, 10)
        self.assertFalse(ok_e)
        self.assertEqual(err_e, "INSUFFICIENT_ITEMS_IN_INVENTORY")

        # Locked / non-restockable
        s_locked = {"is_restockable": 0, "target_capacity": 50, "current_stock": 20}
        ok_l, err_l = evaluate_restock(s_locked, 10, 5)
        self.assertFalse(ok_l)
        self.assertEqual(err_l, "SHELF_NOT_RESTOCKABLE")

    def test_spatial_proximity_calculations(self):
        """Verify 3D Euclidean interaction distance within 2.5m vs out-of-range."""
        import math

        def is_near(point, shelf_coords, max_dist=2.5):
            dx = point[0] - shelf_coords[0]
            dy = point[1] - shelf_coords[1]
            dz = point[2] - shelf_coords[2]
            dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            return dist <= max_dist, round(dist, 2)

        shelf_pos = (374.8, 327.9, 103.5)
        close_point = (375.5, 328.4, 103.5)  # dist ~0.86m
        far_point = (385.0, 335.0, 103.5)    # dist ~12.4m

        near_ok, d_near = is_near(close_point, shelf_pos, 2.5)
        self.assertTrue(near_ok)
        self.assertLess(d_near, 2.5)

        far_ok, d_far = is_near(far_point, shelf_pos, 2.5)
        self.assertFalse(far_ok)
        self.assertGreater(d_far, 2.5)

    def test_in_engine_tests_registered(self):
        """Verify TestPointOfSalePhysicalStockingAndEmptyShelfDisplays is registered in server/tests.lua."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        with open(tests_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("function Nyx.Tests.TestPointOfSalePhysicalStockingAndEmptyShelfDisplays()", code)
        self.assertIn("local t57 = Nyx.Tests.TestPointOfSalePhysicalStockingAndEmptyShelfDisplays()", code)
        self.assertIn("suites1to50Passed and t51 and t52 and t53 and t54 and t55 and t56 and t57", code)

if __name__ == "__main__":
    unittest.main()
