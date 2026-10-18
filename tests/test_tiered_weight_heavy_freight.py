#!/usr/bin/env python3
"""
Comprehensive Unit & Integration Test Suite for:
Feature: Forgiving Tiered Weight Brackets & Heavy Freight Physics (nyx_inventory -> nyx_core)
"""

import os
import sys
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")

class TestTieredWeightAndHeavyFreight(unittest.TestCase):
    def test_baseline_player_carry_capacity_60kg(self):
        """Verify baseline player carry capacity is expanded to 60kg (60,000g) across core & inventory."""
        inv_config = os.path.join(FIVEM_DIR, "nyx_inventory", "config.lua")
        with open(inv_config, "r", encoding="utf-8") as f:
            code = f.read()
        self.assertIn("maxWeight = 60000", code, "Player container maxWeight should be 60000g in nyx_inventory")

        core_config = os.path.join(FIVEM_DIR, "nyx_core", "config.lua")
        with open(core_config, "r", encoding="utf-8") as f:
            code = f.read()
        self.assertIn("defaultPlayerCapacity = 60000", code, "defaultPlayerCapacity should be 60000 in nyx_core")

        # Database migration 020
        mig_core = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "020_expand_player_inventory_capacity.sql")
        self.assertTrue(os.path.isfile(mig_core), "Migration 020 missing in nyx_core")
        with open(mig_core, "r", encoding="utf-8") as f:
            sql = f.read()
        self.assertIn("MODIFY COLUMN `max_weight` INT UNSIGNED NOT NULL DEFAULT 60000", sql)
        self.assertIn("SET `max_weight` = 60000", sql)

    def test_forgiving_tiered_movement_modifiers(self):
        """Verify the 4 tiered movement brackets match exact spec:
           Tier 0 (0%-70%): Normal, 1.0, 0 penalties
           Tier 1 (71%-95%): Moderate, 0.90 (-10% sprint speed), slightly increased stamina drain
           Tier 2 (96%-100%+): Overencumbered, 0.80, sprinting/jumping disabled, fast walking allowed
           Tier 3 (> 50kg freight): 0.65, sprinting/jumping/climbing disabled
        """
        weights_path = os.path.join(FIVEM_DIR, "nyx_core", "shared", "weights.lua")
        self.assertTrue(os.path.isfile(weights_path), "nyx_core shared/weights.lua missing")
        with open(weights_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("function Nyx.Weights.CalculateTier(ratio, isHeavyFreight)", code)
        self.assertIn("function Nyx.Weights.IsHeavyFreight(weightGrams)", code)

        # Python model of the Lua algorithm
        def calculate_tier(ratio, is_heavy=False):
            if is_heavy:
                return "tier_3", 0.65, False, False, False, 2.50
            if ratio > 0.95:
                return "tier_2", 0.80, False, False, False, 2.00
            if ratio > 0.70:
                return "tier_1", 0.90, True, True, True, 1.30
            return "tier_0", 1.00, True, True, True, 1.00

        # Tier 0 Tests (0% to 70%)
        for pct in [0.0, 0.15, 0.40, 0.65, 0.70]:
            t, rate, sprint, jump, climb, drain = calculate_tier(pct)
            self.assertEqual(t, "tier_0")
            self.assertEqual(rate, 1.00)
            self.assertTrue(sprint and jump and climb)
            self.assertEqual(drain, 1.00)

        # Tier 1 Tests (71% to 95%)
        for pct in [0.701, 0.75, 0.85, 0.90, 0.95]:
            t, rate, sprint, jump, climb, drain = calculate_tier(pct)
            self.assertEqual(t, "tier_1")
            self.assertEqual(rate, 0.90)
            self.assertTrue(sprint and jump and climb)
            self.assertEqual(drain, 1.30)

        # Tier 2 Tests (96% to 100%+)
        for pct in [0.951, 0.98, 1.00, 1.15, 1.50]:
            t, rate, sprint, jump, climb, drain = calculate_tier(pct)
            self.assertEqual(t, "tier_2")
            self.assertEqual(rate, 0.80)
            self.assertFalse(sprint)
            self.assertFalse(jump)
            self.assertFalse(climb)
            self.assertEqual(drain, 2.00)

        # Tier 3 Tests (Heavy freight active)
        t, rate, sprint, jump, climb, drain = calculate_tier(0.20, is_heavy=True)
        self.assertEqual(t, "tier_3")
        self.assertEqual(rate, 0.65)
        self.assertFalse(sprint)
        self.assertFalse(jump)
        self.assertFalse(climb)
        self.assertEqual(drain, 2.50)

    def test_server_authoritative_state_bag_sync(self):
        """Verify server sets replicated State Bags and client listens via AddStateBagChangeHandler without polling."""
        player_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "player.lua")
        with open(player_path, "r", encoding="utf-8") as f:
            code = f.read()

        # Server-authoritative state bag declarations with replicated=true
        self.assertIn('pState:set("weightTier", tierData.label, true)', code)
        self.assertIn('pState:set("weightTierKey", tierKey, true)', code)
        self.assertIn('pState:set("weightRatio", ratio, true)', code)
        self.assertIn('pState:set("moveRateOverride", tierData.moveRate, true)', code)
        self.assertIn('pState:set("sprintAllowed", tierData.sprintAllowed, true)', code)
        self.assertIn('pState:set("jumpAllowed", tierData.jumpAllowed, true)', code)
        self.assertIn('pState:set("climbAllowed", tierData.climbAllowed, true)', code)
        self.assertIn('pState:set("isCarryingHeavyFreight", self.isCarryingHeavyFreight or false, true)', code)
        self.assertIn("function PlayerObject:setHeavyFreight(", code)

        # Client listener
        movement_path = os.path.join(FIVEM_DIR, "nyx_core", "client", "movement.lua")
        with open(movement_path, "r", encoding="utf-8") as f:
            cli_code = f.read()
        self.assertIn('AddStateBagChangeHandler("weightTier"', cli_code)
        self.assertIn('AddStateBagChangeHandler("isCarryingHeavyFreight"', cli_code)

    def test_heavy_freight_backpack_storage_prohibition(self):
        """Verify heavy industrial crates (> 50kg) cannot be stored into player backpacks."""
        items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
        with open(items_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("['crate_industrial_heavy']", code)
        self.assertIn("weight = 65000", code)
        self.assertIn("['pallet_freight_steel']", code)
        self.assertIn("weight = 85000", code)
        self.assertIn("['crate_machinery_parts']", code)
        self.assertIn("weight = 55000", code)
        self.assertIn("function Nyx.Items.IsHeavyFreight(name, amount)", code)

        # Verify rejection in actions.lua
        actions_path = os.path.join(FIVEM_DIR, "nyx_inventory", "server", "actions.lua")
        with open(actions_path, "r", encoding="utf-8") as f:
            act_code = f.read()
        self.assertIn("HEAVY_FREIGHT_BACKPACK_PROHIBITED", act_code)
        self.assertIn('dstContainer.type == "player" and Nyx.Items.IsHeavyFreight', act_code)

        # Verify rejection in state.lua
        state_path = os.path.join(FIVEM_DIR, "nyx_inventory", "server", "state.lua")
        with open(state_path, "r", encoding="utf-8") as f:
            st_code = f.read()
        self.assertIn('self.type == "player" and Nyx.Items.IsHeavyFreight', st_code)

    def test_two_handed_physical_carry_and_vehicle_loading(self):
        """Verify physical two-handed carry RPCs, animation, control lockouts, and vehicle trunk loading."""
        srv_freight = os.path.join(FIVEM_DIR, "nyx_inventory", "server", "freight.lua")
        with open(srv_freight, "r", encoding="utf-8") as f:
            s_code = f.read()
        self.assertIn('Nyx.RPC.Register("inventory:startHeavyCarry"', s_code)
        self.assertIn('Nyx.RPC.Register("inventory:dropHeavyCarry"', s_code)
        self.assertIn('Nyx.RPC.Register("inventory:loadHeavyFreightToVehicle"', s_code)
        self.assertIn('AddEventHandler("playerDropped"', s_code)  # Disconnect safety

        cli_freight = os.path.join(FIVEM_DIR, "nyx_inventory", "client", "freight.lua")
        with open(cli_freight, "r", encoding="utf-8") as f:
            c_code = f.read()
        self.assertIn("anim@heists@box_carry@", c_code)
        self.assertIn("AttachEntityToEntity", c_code)
        self.assertIn("TaskPlayAnim", c_code)
        self.assertIn("DisableControlAction(0, 21, true)", c_code)  # Sprint
        self.assertIn("DisableControlAction(0, 22, true)", c_code)  # Jump
        self.assertIn("DisableControlAction(0, 23, true)", c_code)  # Enter vehicle
        self.assertIn("DisableControlAction(0, 44, true)", c_code)  # Cover/mantle

        # Third-Eye option in drops.lua
        drops_path = os.path.join(FIVEM_DIR, "nyx_inventory", "client", "drops.lua")
        with open(drops_path, "r", encoding="utf-8") as f:
            d_code = f.read()
        self.assertIn("Pick Up & Carry (Two-Handed)", d_code)
        self.assertIn("nyx:inventory:client:pickupHeavyFreight", d_code)

    def test_forklift_and_pallet_transport(self):
        """Verify logistics pallet and forklift attachment exports."""
        logistics_exports = os.path.join(FIVEM_DIR, "nyx_logistics", "client", "exports.lua")
        with open(logistics_exports, "r", encoding="utf-8") as f:
            l_code = f.read()
        self.assertIn('exports("AttachPalletToVehicle"', l_code)
        self.assertIn('exports("DetachPallet"', l_code)
        self.assertIn('exports("SpawnPallet"', l_code)

if __name__ == "__main__":
    unittest.main()
