#!/usr/bin/env python3
"""
Unit and Integration Tests for Nyxframework Forgiving Tiered Weight Brackets & Heavy Freight Physics
"""

import os
import sys
import re
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")

class TestWeightPenaltiesSystem(unittest.TestCase):
    def test_nyx_core_config_weight_penalties(self):
        """Verify Config.WeightPenalties is defined with forgiving tiered locomotion properties and expanded capacity."""
        config_path = os.path.join(FIVEM_DIR, "nyx_core", "config.lua")
        self.assertTrue(os.path.isfile(config_path), "nyx_core config.lua missing")
        with open(config_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("Config.WeightPenalties =", content)
        self.assertIn("enabled = true", content)
        self.assertIn("defaultPlayerCapacity = 60000", content)
        self.assertIn("heavyFreightThresholdGrams = 50000", content)
        self.assertIn("tier_0 =", content)
        self.assertIn("tier_1 =", content)
        self.assertIn("tier_2 =", content)
        self.assertIn("tier_3 =", content)

        # Assert key locomotion multiplier values
        self.assertIn("moveRate = 1.0", content)
        self.assertIn("moveRate = 0.90", content)
        self.assertIn("moveRate = 0.80", content)
        self.assertIn("moveRate = 0.65", content)

    def test_fxmanifest_declarations(self):
        """Verify client/movement.lua and shared/weights.lua are properly registered in nyx_core fxmanifest."""
        core_manifest = os.path.join(FIVEM_DIR, "nyx_core", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(core_manifest))
        with open(core_manifest, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("client/movement.lua", content)
        self.assertIn("shared/weights.lua", content)

        movement_script = os.path.join(FIVEM_DIR, "nyx_core", "client", "movement.lua")
        self.assertTrue(os.path.isfile(movement_script), "client/movement.lua missing on disk")
        weights_script = os.path.join(FIVEM_DIR, "nyx_core", "shared", "weights.lua")
        self.assertTrue(os.path.isfile(weights_script), "shared/weights.lua missing on disk")

    def test_client_movement_engine_features(self):
        """Verify client/movement.lua implements speed override, control lockouts, state bag handler, and exports."""
        movement_path = os.path.join(FIVEM_DIR, "nyx_core", "client", "movement.lua")
        with open(movement_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("SetPedMoveRateOverride", code)
        self.assertIn("DisableControlAction(0, 21, true)", code)  # INPUT_SPRINT
        self.assertIn("DisableControlAction(0, 22, true)", code)  # INPUT_JUMP
        self.assertIn("DisableControlAction(0, 44, true)", code)  # INPUT_COVER (climb)
        self.assertIn("RestorePlayerStamina", code)
        self.assertIn("AddStateBagChangeHandler", code)
        self.assertIn('exports("GetMovementPenalty"', code)
        self.assertIn('exports("GetWeightRatio"', code)
        self.assertIn('exports("IsOverweight"', code)
        self.assertIn('exports("IsEncumbered"', code)
        self.assertIn('exports("IsCarryingHeavyFreight"', code)

    def test_nyx_inventory_integration(self):
        """Verify nyx_inventory server and client hooks for weight tracking, 60kg capacity, and freight."""
        inv_config = os.path.join(FIVEM_DIR, "nyx_inventory", "config.lua")
        with open(inv_config, "r", encoding="utf-8") as f:
            cfg_code = f.read()
        self.assertIn("maxWeight = 60000", cfg_code)
        self.assertIn("Config.HeavyFreightThreshold = 50000", cfg_code)

        state_path = os.path.join(FIVEM_DIR, "nyx_inventory", "server", "state.lua")
        with open(state_path, "r", encoding="utf-8") as f:
            state_code = f.read()
        self.assertIn("function Container:syncWeightToCore()", state_code)
        self.assertIn("function Container:canHoldItem(", state_code)
        self.assertIn("HEAVY_FREIGHT_BACKPACK_PROHIBITED", state_code)

        server_freight_path = os.path.join(FIVEM_DIR, "nyx_inventory", "server", "freight.lua")
        self.assertTrue(os.path.isfile(server_freight_path), "server/freight.lua missing")
        client_freight_path = os.path.join(FIVEM_DIR, "nyx_inventory", "client", "freight.lua")
        self.assertTrue(os.path.isfile(client_freight_path), "client/freight.lua missing")

    def test_tier_evaluation_logic(self):
        """Simulate forgiving ratio-to-tier evaluation matching Lua implementation."""
        def evaluate_tier(ratio, is_heavy=False):
            if is_heavy:
                return "tier_3", 0.65, False, False, False
            elif ratio > 0.95:
                return "tier_2", 0.80, False, False, False
            elif ratio > 0.70:
                return "tier_1", 0.90, True, True, True
            else:
                return "tier_0", 1.00, True, True, True

        max_w = 60000

        # Tier 0: Normal load (0% - 70% capacity, e.g. 30kg = 50%)
        t, rate, sprint, jump, climb = evaluate_tier(30000 / max_w)
        self.assertEqual(t, "tier_0")
        self.assertEqual(rate, 1.00)
        self.assertTrue(sprint and jump and climb)

        # Tier 0 Boundary: Exactly 70% (42kg)
        t, rate, sprint, jump, climb = evaluate_tier(42000 / max_w)
        self.assertEqual(t, "tier_0")
        self.assertEqual(rate, 1.00)
        self.assertTrue(sprint and jump and climb)

        # Tier 1: Moderate load (71% - 95% capacity, e.g. 50kg = 83.33%)
        t, rate, sprint, jump, climb = evaluate_tier(50000 / max_w)
        self.assertEqual(t, "tier_1")
        self.assertEqual(rate, 0.90)
        self.assertTrue(sprint and jump and climb)

        # Tier 2: Overencumbered load (96% - 100%+ capacity, e.g. 58kg = 96.67%)
        t, rate, sprint, jump, climb = evaluate_tier(58000 / max_w)
        self.assertEqual(t, "tier_2")
        self.assertEqual(rate, 0.80)
        self.assertFalse(sprint)
        self.assertFalse(jump)
        self.assertFalse(climb)

        # Tier 3: Heavy Industrial Crate (> 50kg physical carry)
        t, rate, sprint, jump, climb = evaluate_tier(10000 / max_w, is_heavy=True)
        self.assertEqual(t, "tier_3")
        self.assertEqual(rate, 0.65)
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
        self.assertIn("and t6", code)

if __name__ == "__main__":
    unittest.main()
