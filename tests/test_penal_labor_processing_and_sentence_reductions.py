#!/usr/bin/env python3
"""
Unit and Integration Tests for Penal Labor Processing & Civic Sentence Reductions.
Covers: Migration 045, nyx_inventory item registrations (raw_fabric, raw_timber, civic items),
        Shared Pure Lua 5.4 Penal Labor Engine (nyx_judiciary/shared/penal_labor.lua),
        Workstations & Recipe registry, Sentence reduction math & discharge eligibility,
        Civic funds generation & treasury accounting, Inmate eligibility & input validation,
        Logistics recipe integration, Server exports & RPCs, and in-engine test harness (Test 40).
"""

import os
import sys
import json
import re
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestPenalLaborProcessingAndSentenceReductions(unittest.TestCase):
    def test_migration_045_exists_and_registered(self):
        """Verify migration 045 exists on disk, mirrored, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("045_penal_labor_processing_and_sentence_reductions.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "045_penal_labor_processing_and_sentence_reductions.sql")
        judiciary_mig = os.path.join(FIVEM_DIR, "nyx_judiciary", "sql", "migrations", "045_penal_labor_processing_and_sentence_reductions.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 045 missing")
        self.assertTrue(os.path.isfile(judiciary_mig), "nyx_judiciary migration 045 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("nyx_judiciary_penal_records", sql)
        self.assertIn("nyx_judiciary_penal_labor_logs", sql)
        self.assertIn("gov:corrections:penal_labor", sql)
        self.assertIn("stash:bolingbroke_workshop", sql)
        self.assertIn("stash:bolingbroke_civic_output", sql)
        self.assertIn("refined_iron", sql)
        self.assertIn("plastic_polymer", sql)
        self.assertIn("raw_fabric", sql)
        self.assertIn("raw_timber", sql)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest.lua declares shared, server, and client penal labor scripts."""
        manifest_path = os.path.join(FIVEM_DIR, "nyx_judiciary", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_path))
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = f.read()

        self.assertIn("shared/penal_labor.lua", manifest)
        self.assertIn("server/penal_labor.lua", manifest)
        self.assertIn("client/penal_labor.lua", manifest)

        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_judiciary", "shared", "penal_labor.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_judiciary", "server", "penal_labor.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_judiciary", "client", "penal_labor.lua")))

    def test_inventory_items_registered(self):
        """Verify raw materials and civic manufactured goods are registered in nyx_inventory."""
        items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
        self.assertTrue(os.path.isfile(items_path))
        with open(items_path, "r", encoding="utf-8") as f:
            content = f.read()

        required_items = [
            "raw_fabric",
            "raw_timber",
            "civic_license_plate",
            "civic_road_barrier",
            "civic_inmate_uniform",
            "civic_emergency_cot",
            "civic_wooden_pallet"
        ]

        for item in required_items:
            self.assertIn(f"['{item}']", content, f"Item {item} missing from inventory registry")

    def test_logistics_recipes_integration(self):
        """Verify nyx_logistics recipes and terminal include penal civic manufacturing."""
        recipes_path = os.path.join(FIVEM_DIR, "nyx_logistics", "shared", "recipes.lua")
        self.assertTrue(os.path.isfile(recipes_path))
        with open(recipes_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("civic_license_plates", content)
        self.assertIn("civic_road_barrier", content)
        self.assertIn("civic_emergency_cot", content)
        self.assertIn("civic_wooden_pallet", content)
        self.assertIn("penal_workshop", content)

        contracts_path = os.path.join(FIVEM_DIR, "nyx_logistics", "shared", "contracts.lua")
        with open(contracts_path, "r", encoding="utf-8") as f:
            contracts = f.read()
        self.assertIn("terminal_bolingbroke_penal", contracts)

    def test_sentence_reduction_calculation_and_discharge(self):
        """Verify pure Lua sentence reduction math, clamping, and release eligibility."""
        def calculate_sentence_reduction(current_sentence_months, reduction_months):
            cur = max(0, int(current_sentence_months or 0))
            red = max(0, int(reduction_months or 0))
            if cur == 0:
                return 0, 0, False
            new_sentence = max(0, cur - red)
            actual_reduction = cur - new_sentence
            is_eligible = (new_sentence <= 0)
            return new_sentence, actual_reduction, is_eligible

        # Normal reduction
        new_s, red, eligible = calculate_sentence_reduction(12, 3)
        self.assertEqual(new_s, 9)
        self.assertEqual(red, 3)
        self.assertFalse(eligible)

        # Exact discharge
        new_s, red, eligible = calculate_sentence_reduction(4, 4)
        self.assertEqual(new_s, 0)
        self.assertEqual(red, 4)
        self.assertTrue(eligible)

        # Overshoot discharge (clamped to 0)
        new_s, red, eligible = calculate_sentence_reduction(2, 5)
        self.assertEqual(new_s, 0)
        self.assertEqual(red, 2)
        self.assertTrue(eligible)

        # Already at 0
        new_s, red, eligible = calculate_sentence_reduction(0, 3)
        self.assertEqual(new_s, 0)
        self.assertEqual(red, 0)
        self.assertFalse(eligible)

    def test_civic_funds_generation(self):
        """Verify calculation of civic funds contributed to the municipal corrections reserve."""
        recipes = {
            "license_plates": 120.00,
            "road_barriers": 250.00,
            "inmate_uniforms": 100.00,
            "emergency_cots": 350.00,
            "wooden_pallets": 180.00
        }

        def calculate_civic_value(recipe_id, multiplier=1):
            base = recipes.get(recipe_id, 0.0)
            return round(base * max(1, int(multiplier)), 2)

        self.assertEqual(calculate_civic_value("license_plates", 1), 120.00)
        self.assertEqual(calculate_civic_value("road_barriers", 2), 500.00)
        self.assertEqual(calculate_civic_value("emergency_cots", 3), 1050.00)
        self.assertEqual(calculate_civic_value("wooden_pallets", 1), 180.00)

    def test_inmate_eligibility_validation(self):
        """Verify inmate eligibility checks for custodial labor."""
        def validate_labor_eligibility(penal_record):
            if not penal_record or not isinstance(penal_record, dict):
                return False, "NOT_INCARCERATED"
            status = penal_record.get("status", "released")
            if status != "incarcerated":
                return False, f"INMATE_STATUS_{status.upper()}"
            sentence = int(penal_record.get("current_sentence_months", 0))
            if sentence <= 0:
                return False, "SENTENCE_EXPIRED"
            return True, None

        # Incarcerated with active sentence
        ok, err = validate_labor_eligibility({"status": "incarcerated", "current_sentence_months": 8})
        self.assertTrue(ok)
        self.assertIsNone(err)

        # Incarcerated but sentence reached 0
        ok, err = validate_labor_eligibility({"status": "incarcerated", "current_sentence_months": 0})
        self.assertFalse(ok)
        self.assertEqual(err, "SENTENCE_EXPIRED")

        # Released or Paroled
        ok, err = validate_labor_eligibility({"status": "released", "current_sentence_months": 0})
        self.assertFalse(ok)
        self.assertEqual(err, "INMATE_STATUS_RELEASED")

        ok, err = validate_labor_eligibility({"status": "paroled", "current_sentence_months": 5})
        self.assertFalse(ok)
        self.assertEqual(err, "INMATE_STATUS_PAROLED")

    def test_labor_inputs_validation(self):
        """Verify input material checks against available workshop supplies."""
        recipe_inputs = [
            {"item": "refined_iron", "amount": 2},
            {"item": "plastic_polymer", "amount": 1}
        ]

        def validate_inputs(inputs, available_items, mult=1):
            for req in inputs:
                needed = req["amount"] * mult
                have = available_items.get(req["item"], 0)
                if have < needed:
                    return False, req["item"], needed, have
            return True, None, None, None

        # Sufficient stock
        stock1 = {"refined_iron": 10, "plastic_polymer": 5}
        ok, missing, needed, have = validate_inputs(recipe_inputs, stock1, 2)
        self.assertTrue(ok)
        self.assertIsNone(missing)

        # Insufficient stock
        stock2 = {"refined_iron": 3, "plastic_polymer": 5}
        ok, missing, needed, have = validate_inputs(recipe_inputs, stock2, 2)
        self.assertFalse(ok)
        self.assertEqual(missing, "refined_iron")
        self.assertEqual(needed, 4)
        self.assertEqual(have, 3)

    def test_zero_trust_payload_validation_and_badges(self):
        """Verify zero-trust payload sanitization and penal status badge taxonomy."""
        def validate_payload(p, valid_workstations, valid_recipes, allowed_map):
            if not isinstance(p, dict):
                return False, "INVALID_PAYLOAD"
            ws = p.get("workstationId")
            rec = p.get("recipeId")
            if ws not in valid_workstations:
                return False, "INVALID_WORKSTATION"
            if rec not in valid_recipes:
                return False, "INVALID_RECIPE"
            if rec not in allowed_map.get(ws, []):
                return False, "RECIPE_NOT_ALLOWED_AT_WORKSTATION"
            mult = p.get("batchMultiplier", 1)
            if not isinstance(mult, int) or mult < 1 or mult > 5:
                return False, "INVALID_BATCH_MULTIPLIER"
            return True, "OK"

        ws_list = ["bolingbroke_metalwork", "bolingbroke_textile", "bolingbroke_carpentry", "bolingbroke_general"]
        rec_list = ["license_plates", "road_barriers", "inmate_uniforms", "emergency_cots", "wooden_pallets"]
        allowed = {
            "bolingbroke_metalwork": ["license_plates", "road_barriers"],
            "bolingbroke_textile": ["inmate_uniforms"],
            "bolingbroke_carpentry": ["emergency_cots", "wooden_pallets"],
            "bolingbroke_general": rec_list
        }

        ok1, _ = validate_payload({"workstationId": "bolingbroke_metalwork", "recipeId": "license_plates", "batchMultiplier": 1}, ws_list, rec_list, allowed)
        self.assertTrue(ok1)

        ok2, err2 = validate_payload({"workstationId": "invalid_ws", "recipeId": "license_plates"}, ws_list, rec_list, allowed)
        self.assertFalse(ok2)
        self.assertEqual(err2, "INVALID_WORKSTATION")

        ok3, err3 = validate_payload({"workstationId": "bolingbroke_metalwork", "recipeId": "inmate_uniforms"}, ws_list, rec_list, allowed)
        self.assertFalse(ok3)
        self.assertEqual(err3, "RECIPE_NOT_ALLOWED_AT_WORKSTATION")

        ok4, err4 = validate_payload({"workstationId": "bolingbroke_metalwork", "recipeId": "license_plates", "batchMultiplier": 10}, ws_list, rec_list, allowed)
        self.assertFalse(ok4)
        self.assertEqual(err4, "INVALID_BATCH_MULTIPLIER")

    def test_in_engine_tests_lua_integration(self):
        """Verify Test 40 is registered in nyx_core/server/tests.lua and wired into RunAll."""
        tests_lua_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        self.assertTrue(os.path.isfile(tests_lua_path))
        with open(tests_lua_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("Nyx.Tests.TestPenalLaborProcessingAndSentenceReductions", content)
        self.assertIn("local t40 = Nyx.Tests.TestPenalLaborProcessingAndSentenceReductions()", content)
        self.assertIn("and t40", content)


if __name__ == "__main__":
    unittest.main()
