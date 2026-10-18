#!/usr/bin/env python3
"""
Unit and Integration Tests for Nyxframework Dynamic Inventory Weight Penalties System
"""

import os
import sys
import re
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")

class TestWeightPenaltiesSystem(unittest.TestCase):
    def test_nyx_core_config_weight_penalties(self):
        """Verify Config.WeightPenalties is defined with correct tiered locomotion properties."""
        config_path = os.path.join(FIVEM_DIR, "nyx_core", "config.lua")
        self.assertTrue(os.path.isfile(config_path), "nyx_core config.lua missing")
        with open(config_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("Config.WeightPenalties =", content)
        self.assertIn("enabled = true", content)
        self.assertIn("normal =", content)
        self.assertIn("encumbered =", content)
        self.assertIn("heavy =", content)
        self.assertIn("overburdened =", content)
        self.assertIn("critical =", content)

        # Assert key locomotion multiplier values
        self.assertIn("moveRate = 1.0", content)
        self.assertIn("moveRate = 0.90", content)
        self.assertIn("moveRate = 0.78", content)
        self.assertIn("moveRate = 0.60", content)
        self.assertIn("moveRate = 0.40", content)

    def test_fxmanifest_declarations(self):
        """Verify client/movement.lua is properly registered in nyx_core fxmanifest."""
        core_manifest = os.path.join(FIVEM_DIR, "nyx_core", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(core_manifest))
        with open(core_manifest, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("client/movement.lua", content)

        movement_script = os.path.join(FIVEM_DIR, "nyx_core", "client", "movement.lua")
        self.assertTrue(os.path.isfile(movement_script), "client/movement.lua missing on disk")

    def test_client_movement_engine_features(self):
        """Verify client/movement.lua implements speed override, control lockouts, and exports."""
        movement_path = os.path.join(FIVEM_DIR, "nyx_core", "client", "movement.lua")
        with open(movement_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("SetPedMoveRateOverride", code)
        self.assertIn("DisableControlAction(0, 21, true)", code)  # INPUT_SPRINT
        self.assertIn("DisableControlAction(0, 22, true)", code)  # INPUT_JUMP
        self.assertIn("DisableControlAction(0, 44, true)", code)  # INPUT_COVER (climb)
        self.assertIn("RestorePlayerStamina", code)
        self.assertIn('exports("GetMovementPenalty"', code)
        self.assertIn('exports("GetWeightRatio"', code)
        self.assertIn('exports("IsOverweight"', code)
        self.assertIn('exports("IsEncumbered"', code)

    def test_nyx_inventory_integration(self):
        """Verify nyx_inventory server and client hooks for weight tracking and sync."""
        state_path = os.path.join(FIVEM_DIR, "nyx_inventory", "server", "state.lua")
        with open(state_path, "r", encoding="utf-8") as f:
            state_code = f.read()
        self.assertIn("function Container:syncWeightToCore()", state_code)
        self.assertIn("exports['nyx_core']:UpdatePlayerWeight", state_code)

        server_exports_path = os.path.join(FIVEM_DIR, "nyx_inventory", "server", "exports.lua")
        with open(server_exports_path, "r", encoding="utf-8") as f:
            srv_exp = f.read()
        self.assertIn('exports("GetPlayerWeight"', srv_exp)
        self.assertIn('exports("SyncPlayerWeight"', srv_exp)

        client_exports_path = os.path.join(FIVEM_DIR, "nyx_inventory", "client", "exports.lua")
        with open(client_exports_path, "r", encoding="utf-8") as f:
            cli_exp = f.read()
        self.assertIn('exports("GetPlayerWeight"', cli_exp)

    def test_tier_evaluation_logic(self):
        """Simulate ratio-to-tier evaluation matching Lua implementation."""
        def evaluate_tier(ratio):
            if ratio >= 1.20:
                return "critical", 0.40, False, False, False
            elif ratio >= 1.00:
                return "overburdened", 0.60, False, False, True
            elif ratio >= 0.85:
                return "heavy", 0.78, True, True, True
            elif ratio >= 0.70:
                return "encumbered", 0.90, True, True, True
            else:
                return "normal", 1.00, True, True, True

        max_w = 30000

        # Normal load (10kg)
        t, rate, sprint, jump, climb = evaluate_tier(10000 / max_w)
        self.assertEqual(t, "normal")
        self.assertEqual(rate, 1.00)
        self.assertTrue(sprint and jump and climb)

        # Encumbered load (23kg = 76.67%)
        t, rate, sprint, jump, climb = evaluate_tier(23000 / max_w)
        self.assertEqual(t, "encumbered")
        self.assertEqual(rate, 0.90)
        self.assertTrue(sprint and jump and climb)

        # Heavy load (27kg = 90%)
        t, rate, sprint, jump, climb = evaluate_tier(27000 / max_w)
        self.assertEqual(t, "heavy")
        self.assertEqual(rate, 0.78)
        self.assertTrue(sprint and jump and climb)

        # Overburdened load (32kg = 106.67%)
        t, rate, sprint, jump, climb = evaluate_tier(32000 / max_w)
        self.assertEqual(t, "overburdened")
        self.assertEqual(rate, 0.60)
        self.assertFalse(sprint)
        self.assertFalse(jump)
        self.assertTrue(climb)

        # Critical load (40kg = 133.33%)
        t, rate, sprint, jump, climb = evaluate_tier(40000 / max_w)
        self.assertEqual(t, "critical")
        self.assertEqual(rate, 0.40)
        self.assertFalse(sprint)
        self.assertFalse(jump)
        self.assertFalse(climb)

    def test_in_engine_tests_registered(self):
        """Verify in-engine TestWeightPenalties is present and run in tests.lua."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        with open(tests_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("function Nyx.Tests.TestWeightPenalties()", code)
        self.assertIn("local t6 = Nyx.Tests.TestWeightPenalties()", code)
        self.assertIn("if t1 and t2 and t3 and t4 and t5 and t6 then", code)

if __name__ == "__main__":
    unittest.main()
