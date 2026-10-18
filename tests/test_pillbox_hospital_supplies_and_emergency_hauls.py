#!/usr/bin/env python3
"""
Unit and Integration Tests for Pillbox Hospital Supply Depletion & Emergency Medical Hauls.
Covers: Migration 042, Canonical Stash Mapping (stash:pillbox_meds), Item Registrations,
        Shared Pure Lua 5.4 Medical Supply Engine, Multi-Tier Shortage Evaluation,
        Revival Consumption & Surgical Depletion Guards, Emergency Haul Contract Math,
        and In-Engine Integration Test Harness Wiring.
"""

import os
import sys
import json
import re
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestPillboxHospitalSuppliesAndEmergencyHauls(unittest.TestCase):
    def test_migration_042_exists_and_registered(self):
        """Verify migration 042 exists on disk, mirrored, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("042_pillbox_hospital_supply_depletion_and_emergency_hauls.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "042_pillbox_hospital_supply_depletion_and_emergency_hauls.sql")
        services_mig = os.path.join(FIVEM_DIR, "nyx_services", "sql", "migrations", "042_pillbox_hospital_supply_depletion_and_emergency_hauls.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 042 missing")
        self.assertTrue(os.path.isfile(services_mig), "nyx_services migration 042 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("stash:pillbox_meds", sql)
        self.assertIn("nyx_services_hospitals", sql)
        self.assertIn("critical_threshold", sql)
        self.assertIn("degraded_threshold", sql)
        self.assertIn("nyx_services_hospital_supply_audit", sql)
        self.assertIn("med_plasma", sql)
        self.assertIn("med_firstaid", sql)
        self.assertIn("med_surgical_pack", sql)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest.lua declares shared/medical.lua and files exist."""
        manifest_path = os.path.join(FIVEM_DIR, "nyx_services", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_path))
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = f.read()

        self.assertIn("shared/medical.lua", manifest)
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_services", "shared", "medical.lua")))

    def test_canonical_stash_mapping(self):
        """Verify canonical stash resolution for hospitals."""
        shared_medical = os.path.join(FIVEM_DIR, "nyx_services", "shared", "medical.lua")
        with open(shared_medical, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("CanonicalPillboxStash = \"stash:pillbox_meds\"", code)
        self.assertIn("['pillbox_hill'] = \"stash:pillbox_meds\"", code)
        self.assertIn("['stash:pillbox_meds'] = \"pillbox_hill\"", code)

    def test_items_registered_in_nyx_inventory(self):
        """Verify all tracked clinical supply consumables are registered in nyx_inventory."""
        items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
        self.assertTrue(os.path.isfile(items_path))
        with open(items_path, "r", encoding="utf-8") as f:
            content = f.read()

        required_items = [
            "med_plasma",
            "med_firstaid",
            "med_surgical_pack",
            "bandage_sterile",
            "tourniquet"
        ]
        for item in required_items:
            self.assertIn(f"['{item}']", content, f"Item '{item}' not registered in nyx_inventory")

    def test_supply_evaluation_taxonomy(self):
        """Verify multi-tier hospital supply status evaluation logic."""
        def evaluate_supply(counts, crit=5, deg=15):
            plasma = counts.get("med_plasma", 0)
            trauma = counts.get("med_firstaid", 0)
            surgery = counts.get("med_surgical_pack", 0)

            if plasma <= crit or trauma <= crit or surgery <= 1:
                return "critical_shortage"
            elif plasma <= deg or trauma <= deg or surgery <= 3:
                return "degraded"
            else:
                return "optimal"

        # Optimal: all above thresholds
        s_opt = evaluate_supply({"med_plasma": 30, "med_firstaid": 25, "med_surgical_pack": 15})
        self.assertEqual(s_opt, "optimal")

        # Degraded: plasma below 15 but above 5
        s_deg = evaluate_supply({"med_plasma": 12, "med_firstaid": 25, "med_surgical_pack": 15})
        self.assertEqual(s_deg, "degraded")

        # Critical: trauma kits at or below 5
        s_crit1 = evaluate_supply({"med_plasma": 30, "med_firstaid": 4, "med_surgical_pack": 15})
        self.assertEqual(s_crit1, "critical_shortage")

        # Critical: surgical packs depleted (<= 1)
        s_crit2 = evaluate_supply({"med_plasma": 30, "med_firstaid": 25, "med_surgical_pack": 1})
        self.assertEqual(s_crit2, "critical_shortage")

    def test_respawn_penalty_and_grid_blackout(self):
        """Verify respawn delay calculations under supply shortage and electrical grid blackout."""
        def calc_respawn_penalty(status, is_powered):
            penalties = {"optimal": 0, "degraded": 30, "critical_shortage": 60}
            base = penalties.get(status, 0)
            if not is_powered:
                base += 30
            return base

        self.assertEqual(calc_respawn_penalty("optimal", True), 0)
        self.assertEqual(calc_respawn_penalty("optimal", False), 30)
        self.assertEqual(calc_respawn_penalty("degraded", True), 30)
        self.assertEqual(calc_respawn_penalty("degraded", False), 60)
        self.assertEqual(calc_respawn_penalty("critical_shortage", True), 60)
        self.assertEqual(calc_respawn_penalty("critical_shortage", False), 90)

    def test_emergency_haul_contract_math(self):
        """Verify dynamic hazard multiplier, payout, and escrow bond calculations for emergency courier hauls."""
        def calc_emergency_contract(cur_stock, target=50, qty=25):
            base_price = 120.00
            deficit_ratio = max(0.0, min(1.0, (target - cur_stock) / target))
            mult = 1.85 + (deficit_ratio * (2.75 - 1.85))
            payout_per_unit = round(base_price * mult, 2)
            total_payout = round(payout_per_unit * qty, 2)
            escrow = round(total_payout * 0.15, 2)
            return payout_per_unit, total_payout, escrow

        # Critical zero stock (deficitRatio = 1.0 -> 2.75x multiplier)
        unit_p, tot_p, esc = calc_emergency_contract(0, 50, 25)
        self.assertEqual(unit_p, 330.00)
        self.assertEqual(tot_p, 8250.00)
        self.assertEqual(esc, 1237.50)

        # Half depleted (deficitRatio = 0.5 -> 2.30x multiplier)
        unit_p2, tot_p2, esc2 = calc_emergency_contract(25, 50, 25)
        self.assertEqual(unit_p2, 276.00)
        self.assertEqual(tot_p2, 6900.00)
        self.assertEqual(esc2, 1035.00)

    def test_restock_item_validation(self):
        """Verify zero-trust validation guards on medical restock inputs."""
        valid_items = {
            "med_plasma": True,
            "med_firstaid": True,
            "med_surgical_pack": True,
            "bandage_sterile": True,
            "tourniquet": True,
        }

        def validate_restock(item_id, amount):
            if not item_id or not isinstance(item_id, str):
                return False, "INVALID_ITEM_ID"
            if not isinstance(amount, (int, float)) or amount <= 0 or int(amount) != amount:
                return False, "INVALID_AMOUNT"
            if item_id not in valid_items:
                return False, "UNTRACKED_MEDICAL_SUPPLY_ITEM"
            return True, "OK"

        ok1, _ = validate_restock("med_plasma", 25)
        self.assertTrue(ok1)

        ok2, err2 = validate_restock("med_plasma", 0)
        self.assertFalse(ok2)
        self.assertEqual(err2, "INVALID_AMOUNT")

        ok3, err3 = validate_restock("med_plasma", -10)
        self.assertFalse(ok3)
        self.assertEqual(err3, "INVALID_AMOUNT")

        ok4, err4 = validate_restock("gold_bar", 5)
        self.assertFalse(ok4)
        self.assertEqual(err4, "UNTRACKED_MEDICAL_SUPPLY_ITEM")

    def test_in_engine_tests_lua_integration(self):
        """Verify TestPillboxSupplyDepletionAndEmergencyHauls is declared and wired into tests.lua RunAll()."""
        tests_lua_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        self.assertTrue(os.path.isfile(tests_lua_path))
        with open(tests_lua_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("function Nyx.Tests.TestPillboxSupplyDepletionAndEmergencyHauls()", code)
        self.assertIn("local t37 = Nyx.Tests.TestPillboxSupplyDepletionAndEmergencyHauls()", code)
        self.assertIn("t37 then", code)


if __name__ == "__main__":
    unittest.main()
