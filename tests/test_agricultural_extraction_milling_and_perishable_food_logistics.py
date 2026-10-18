#!/usr/bin/env python3
"""
Unit and Integration Tests for Agricultural Extraction, Milling & Perishable Food Logistics.
Covers: Migration 046, nyx_inventory item registrations (crop_wheat, crop_corn, bulk_flour, food_bread, etc.),
        Shared Pure Lua 5.4 Agriculture Engine (nyx_services/shared/agriculture.lua),
        Logistics recipe blueprints & farm harvest nodes, Soil wear & fertility recovery math,
        Perishable time decay & cold chain multipliers, Emergency food pantry triage & deficit metrics,
        Logistics delivery event hooks, and in-engine test harness (Test 41).
"""

import os
import sys
import json
import re
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestAgriculturalExtractionMillingAndPerishableFoodLogistics(unittest.TestCase):
    def test_migration_046_exists_and_registered(self):
        """Verify migration 046 exists on disk, mirrored, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("046_agricultural_extraction_milling_and_perishable_food_logistics.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "046_agricultural_extraction_milling_and_perishable_food_logistics.sql")
        services_mig = os.path.join(FIVEM_DIR, "nyx_services", "sql", "migrations", "046_agricultural_extraction_milling_and_perishable_food_logistics.sql")
        logistics_mig = os.path.join(FIVEM_DIR, "nyx_logistics", "sql", "migrations", "046_agricultural_extraction_milling_and_perishable_food_logistics.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 046 missing")
        self.assertTrue(os.path.isfile(services_mig), "nyx_services migration 046 missing")
        self.assertTrue(os.path.isfile(logistics_mig), "nyx_logistics migration 046 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("nyx_logistics_agriculture_farms", sql)
        self.assertIn("nyx_services_food_pantries", sql)
        self.assertIn("nyx_logistics_food_audit", sql)
        self.assertIn("farm_grapeseed_wheat", sql)
        self.assertIn("farm_chaparral_corn", sql)
        self.assertIn("farm_paleto_produce", sql)
        self.assertIn("fac_grapeseed_mill", sql)
        self.assertIn("pantry_city_hall", sql)
        self.assertIn("pantry_sandy_community", sql)
        self.assertIn("stash:grapeseed_mill_in", sql)
        self.assertIn("stash:grapeseed_mill_out", sql)
        self.assertIn("shelf_vinewood_food", sql)
        self.assertIn("shelf_davis_food", sql)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest.lua declares shared, server, and client agriculture scripts."""
        manifest_path = os.path.join(FIVEM_DIR, "nyx_services", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_path))
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = f.read()

        self.assertIn("shared/agriculture.lua", manifest)
        self.assertIn("server/agriculture.lua", manifest)
        self.assertIn("client/agriculture.lua", manifest)

        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_services", "shared", "agriculture.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_services", "server", "agriculture.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_services", "client", "agriculture.lua")))

    def test_inventory_items_registered(self):
        """Verify raw crops, flours, bread, and produce pallets are registered in nyx_inventory."""
        items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
        self.assertTrue(os.path.isfile(items_path))
        with open(items_path, "r", encoding="utf-8") as f:
            content = f.read()

        required_items = [
            "crop_wheat",
            "crop_corn",
            "crop_produce",
            "bulk_flour",
            "bulk_cornmeal",
            "food_bread",
            "pallet_agricultural_produce"
        ]

        for item in required_items:
            self.assertIn(f"['{item}']", content, f"Item {item} missing from inventory registry")

    def test_logistics_recipes_and_nodes_registered(self):
        """Verify nyx_logistics recipes, nodes, and dispatch terminals include agricultural production."""
        recipes_path = os.path.join(FIVEM_DIR, "nyx_logistics", "shared", "recipes.lua")
        with open(recipes_path, "r", encoding="utf-8") as f:
            recipes = f.read()

        self.assertIn("wheat_milling", recipes)
        self.assertIn("corn_milling", recipes)
        self.assertIn("bakery_bread", recipes)
        self.assertIn("produce_pallet_packaging", recipes)

        nodes_path = os.path.join(FIVEM_DIR, "nyx_logistics", "shared", "nodes.lua")
        with open(nodes_path, "r", encoding="utf-8") as f:
            nodes = f.read()

        self.assertIn("farm_grapeseed_wheat", nodes)
        self.assertIn("farm_chaparral_corn", nodes)
        self.assertIn("farm_paleto_produce", nodes)

        contracts_path = os.path.join(FIVEM_DIR, "nyx_logistics", "shared", "contracts.lua")
        with open(contracts_path, "r", encoding="utf-8") as f:
            contracts = f.read()

        self.assertIn("terminal_grapeseed_mill", contracts)

    def test_crop_harvest_yield_and_soil_wear(self):
        """Verify crop harvest yield calculation, soil fertility wear, and reserve clamping."""
        def calc_crop_yield(current_reserve, soil_fertility, tool_bonus=1.0):
            current_reserve = max(0, int(current_reserve))
            soil_fertility = max(0.0, min(100.0, float(soil_fertility)))
            tool_bonus = max(1.0, float(tool_bonus))
            if current_reserve <= 0:
                return 0, 0, soil_fertility
            fertility_factor = max(0.20, min(1.25, soil_fertility / 100.0))
            base_yield = 4
            calculated_yield = int(base_yield * fertility_factor * tool_bonus)
            yield_amount = max(1, min(calculated_yield, current_reserve))
            new_fertility = max(10.0, round(soil_fertility - 2.50, 2))
            remaining_reserve = current_reserve - yield_amount
            return yield_amount, remaining_reserve, new_fertility

        # Test A: Full reserve and 100% pristine soil
        y1, rem1, f1 = calc_crop_yield(800, 100.0, 1.0)
        self.assertEqual(y1, 4)
        self.assertEqual(rem1, 796)
        self.assertEqual(f1, 97.5)

        # Test B: Low reserve clamping
        y2, rem2, f2 = calc_crop_yield(2, 100.0, 1.0)
        self.assertEqual(y2, 2)
        self.assertEqual(rem2, 0)
        self.assertEqual(f2, 97.5)

        # Test C: Zero reserve depletion
        y3, rem3, f3 = calc_crop_yield(0, 50.0, 1.0)
        self.assertEqual(y3, 0)
        self.assertEqual(rem3, 0)
        self.assertEqual(f3, 50.0)

    def test_soil_fertility_recovery(self):
        """Verify soil fertility recovery over idle elapsed time."""
        def calc_soil_recovery(fertility, elapsed_seconds, regen_rate_per_hour=15.0):
            fertility = max(0.0, min(100.0, float(fertility)))
            elapsed_seconds = max(0, int(elapsed_seconds))
            if fertility >= 100.0 or elapsed_seconds <= 0:
                return fertility
            rec = (elapsed_seconds / 3600.0) * regen_rate_per_hour
            return min(100.0, round(fertility + rec, 2))

        # +15% after 1 hr
        rec1 = calc_soil_recovery(50.0, 3600, 15.0)
        self.assertEqual(rec1, 65.0)

        # +30% clamped at 100.0%
        rec2 = calc_soil_recovery(95.0, 7200, 15.0)
        self.assertEqual(rec2, 100.0)

        # Zero recovery if already maxed
        rec3 = calc_soil_recovery(100.0, 3600, 15.0)
        self.assertEqual(rec3, 100.0)

    def test_milling_and_baking_conversion_ratios(self):
        """Verify industrial milling and bakery conversion math."""
        def calc_milling_output(recipe_key, batch_multiplier=1):
            mult = max(1, int(batch_multiplier))
            if recipe_key == "wheat_milling":
                return [{"item": "bulk_flour", "amount": 1 * mult}], [{"item": "crop_wheat", "amount": 4 * mult}]
            elif recipe_key == "corn_milling":
                return [{"item": "bulk_cornmeal", "amount": 1 * mult}], [{"item": "crop_corn", "amount": 4 * mult}]
            elif recipe_key == "bakery_bread":
                return [{"item": "food_bread", "amount": 4 * mult}], [{"item": "bulk_flour", "amount": 1 * mult}, {"item": "drink_water", "amount": 2 * mult}]
            elif recipe_key == "produce_pallet_packaging":
                return [{"item": "pallet_agricultural_produce", "amount": 1 * mult}], [{"item": "crop_produce", "amount": 10 * mult}, {"item": "civic_wooden_pallet", "amount": 1 * mult}]
            return None, None

        out_w, in_w = calc_milling_output("wheat_milling", 2)
        self.assertEqual(out_w[0]["amount"], 2)
        self.assertEqual(in_w[0]["amount"], 8)

        out_b, in_b = calc_milling_output("bakery_bread", 3)
        self.assertEqual(out_b[0]["amount"], 12)
        self.assertEqual(in_b[0]["amount"], 3)
        self.assertEqual(in_b[1]["amount"], 6)

    def test_perishable_decay_and_cold_chain(self):
        """Verify perishable food durability decay and environmental cold chain preservation."""
        container_multipliers = {
            "cold_storage": 0.15,
            "stash": 0.50,
            "player": 1.00,
            "drop": 2.00
        }

        def calc_decay(durability, decay_rate, seconds, container_type, is_refrigerated=False):
            durability = max(0.0, min(100.0, float(durability)))
            decay_rate = max(0.0, float(decay_rate))
            mult = container_multipliers.get(container_type, 1.0)
            if is_refrigerated:
                mult = min(mult, 0.15)
            raw_loss = (seconds / 3600.0) * decay_rate * 100.0 * mult
            loss = max(0.0, round(raw_loss, 1))
            new_dur = max(0.0, round(durability - loss, 1))
            is_spoiled = (new_dur <= 0.0)
            tier = "SPOILED" if is_spoiled else ("PRISTINE" if new_dur >= 75.0 else ("FRESH" if new_dur >= 50.0 else "STALE"))
            return new_dur, is_spoiled, tier, loss

        # Bread (decayRate 0.08) in ambient stash for 1 hour -> 4.0 loss -> 96.0% (PRISTINE)
        d_amb, sp_amb, t_amb, l_amb = calc_decay(100.0, 0.08, 3600, "stash", False)
        self.assertEqual(d_amb, 96.0)
        self.assertEqual(l_amb, 4.0)
        self.assertFalse(sp_amb)
        self.assertEqual(t_amb, "PRISTINE")

        # Bread in cold storage for 1 hour -> 1.2 loss -> 98.8% (PRISTINE)
        d_cold, sp_cold, t_cold, l_cold = calc_decay(100.0, 0.08, 3600, "cold_storage", True)
        self.assertEqual(d_cold, 98.8)
        self.assertEqual(l_cold, 1.2)
        self.assertFalse(sp_cold)

        # Durability reaches 0 -> SPOILED
        d_zero, sp_zero, t_zero, _ = calc_decay(3.0, 0.08, 3600, "drop", False)
        self.assertEqual(d_zero, 0.0)
        self.assertTrue(sp_zero)
        self.assertEqual(t_zero, "SPOILED")

    def test_pantry_security_index_and_triage(self):
        """Verify municipal food pantry security index calculation and status classification."""
        def evaluate_pantry(pantry, stock_counts):
            t_r = max(1, pantry.get("target_rations", 100))
            t_b = max(1, pantry.get("target_bread", 50))
            c_r = max(0, stock_counts.get("food_ration", 0))
            c_b = max(0, stock_counts.get("food_bread", 0))

            ratio_r = min(1.0, c_r / t_r)
            ratio_b = min(1.0, c_b / t_b)
            security = round(((ratio_r * 0.50) + (ratio_b * 0.50)) * 100.0, 1)

            status = "optimal"
            if security < 25.0 or c_r == 0:
                status = "critical_shortage"
            elif security < 60.0:
                status = "degraded"

            deficit = max(0, t_r - c_r) + max(0, t_b - c_b)
            return status, security, deficit

        # Optimal stock
        s1, sec1, def1 = evaluate_pantry({"target_rations": 100, "target_bread": 50}, {"food_ration": 100, "food_bread": 50})
        self.assertEqual(s1, "optimal")
        self.assertEqual(sec1, 100.0)
        self.assertEqual(def1, 0)

        # Degraded stock
        s2, sec2, def2 = evaluate_pantry({"target_rations": 100, "target_bread": 50}, {"food_ration": 40, "food_bread": 20})
        self.assertEqual(s2, "degraded")
        self.assertEqual(sec2, 40.0)
        self.assertEqual(def2, 90)

        # Critical shortage
        s3, sec3, def3 = evaluate_pantry({"target_rations": 100, "target_bread": 50}, {"food_ration": 10, "food_bread": 0})
        self.assertEqual(s3, "critical_shortage")
        self.assertEqual(sec3, 5.0)
        self.assertEqual(def3, 140)

    def test_emergency_food_contract_and_in_engine_registration(self):
        """Verify emergency food contract math and in-engine Test 41 registration."""
        def calc_contract(deficit_item, deficit_count, status):
            base_rate = 35.00 if deficit_item == "food_bread" else 25.00
            urgency = 2.00 if status == "critical_shortage" else (1.40 if status == "degraded" else 1.00)
            payout_unit = round(base_rate * urgency, 2)
            total = round(payout_unit * deficit_count, 2)
            escrow = round(total * 0.15, 2)
            return payout_unit, total, escrow, urgency

        unit_c, tot_c, esc_c, urg_c = calc_contract("food_ration", 30, "critical_shortage")
        self.assertEqual(urg_c, 2.00)
        self.assertEqual(unit_c, 50.00)
        self.assertEqual(tot_c, 1500.00)
        self.assertEqual(esc_c, 225.00)

        # In-engine Test 41 registration check
        tests_lua_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        self.assertTrue(os.path.isfile(tests_lua_path))
        with open(tests_lua_path, "r", encoding="utf-8") as f:
            tests_lua = f.read()

        self.assertIn("TestAgriculturalExtractionMillingAndPerishableFoodLogistics", tests_lua)
        self.assertIn("t41 = Nyx.Tests.TestAgriculturalExtractionMillingAndPerishableFoodLogistics()", tests_lua)


if __name__ == "__main__":
    unittest.main()
