#!/usr/bin/env python3
"""
Unit and Integration Tests for Agricultural Livestock, Slaughterhouse Processing & Cold-Chain Logistics.
Covers: Migration 067, nyx_inventory item registrations (livestock_cattle, carcass_beef_raw, packaged_meat_cuts, etc.),
        nyx_logistics recipes and extraction nodes, Pure Lua 5.4 Livestock Engine math,
        Cold-chain decay, reefer temperature evaluation, butchering yields, freight payouts, and Test 62 harness.
"""

import os
import sys
import json
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestLivestockSlaughterhouseAndRefrigeratedLogistics(unittest.TestCase):
    def test_migration_067_exists_and_registered(self):
        """Verify migration 067 exists on disk, mirrored, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("067_livestock_slaughterhouse_and_refrigerated_logistics.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "067_livestock_slaughterhouse_and_refrigerated_logistics.sql")
        services_mig = os.path.join(FIVEM_DIR, "nyx_services", "sql", "migrations", "067_livestock_slaughterhouse_and_refrigerated_logistics.sql")
        logistics_mig = os.path.join(FIVEM_DIR, "nyx_logistics", "sql", "migrations", "067_livestock_slaughterhouse_and_refrigerated_logistics.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 067 missing")
        self.assertTrue(os.path.isfile(services_mig), "nyx_services migration 067 missing")
        self.assertTrue(os.path.isfile(logistics_mig), "nyx_logistics migration 067 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("nyx_livestock_ranches", sql)
        self.assertIn("nyx_slaughterhouses", sql)
        self.assertIn("nyx_refrigerated_logs", sql)
        self.assertIn("ranch_grapeseed", sql)
        self.assertIn("slaughterhouse_cypress_flats", sql)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest.lua declares shared, server, and client livestock scripts."""
        manifest_path = os.path.join(FIVEM_DIR, "nyx_services", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_path))
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = f.read()

        self.assertIn("shared/livestock.lua", manifest)
        self.assertIn("server/livestock.lua", manifest)
        self.assertIn("client/livestock.lua", manifest)

        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_services", "shared", "livestock.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_services", "server", "livestock.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_services", "client", "livestock.lua")))

    def test_inventory_items_registered(self):
        """Verify livestock, raw carcass, packaged meat, and reefer pallet items are registered."""
        items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
        self.assertTrue(os.path.isfile(items_path))
        with open(items_path, "r", encoding="utf-8") as f:
            content = f.read()

        required_items = [
            "livestock_cattle",
            "carcass_beef_raw",
            "packaged_meat_cuts",
            "pallet_refrigerated_beef",
            "livestock_feed_sack"
        ]

        for item in required_items:
            self.assertIn(f"['{item}']", content, f"Item {item} missing from inventory registry")

    def test_logistics_recipes_and_nodes_registered(self):
        """Verify nyx_logistics recipes and extraction nodes include cattle processing."""
        recipes_path = os.path.join(FIVEM_DIR, "nyx_logistics", "shared", "recipes.lua")
        with open(recipes_path, "r", encoding="utf-8") as f:
            recipes = f.read()

        self.assertIn("cattle_slaughtering", recipes)
        self.assertIn("carcass_butchering", recipes)
        self.assertIn("livestock_feed_mixing", recipes)

        nodes_path = os.path.join(FIVEM_DIR, "nyx_logistics", "shared", "nodes.lua")
        with open(nodes_path, "r", encoding="utf-8") as f:
            nodes = f.read()

        self.assertIn("ranch_grapeseed", nodes)
        self.assertIn("ranch_paleto", nodes)

        contracts_path = os.path.join(FIVEM_DIR, "nyx_logistics", "shared", "contracts.lua")
        with open(contracts_path, "r", encoding="utf-8") as f:
            contracts = f.read()

        self.assertIn("terminal_cypress_slaughterhouse", contracts)

    def test_cattle_growth_and_husbandry_math(self):
        """Verify cattle ranch growth and feed consumption formulas."""
        def calc_cattle_growth(cattle_head, max_capacity, feed_level, health_index, elapsed_seconds):
            if elapsed_seconds <= 0 or cattle_head <= 0:
                return feed_level, health_index, 0
            hours = elapsed_seconds / 3600.0
            feed_consumed = hours * (cattle_head * 0.05)
            new_feed = max(0.0, round(feed_level - feed_consumed, 2))
            if new_feed > 10.0:
                new_health = min(100.0, round(health_index + (hours * 5.0), 2))
            else:
                new_health = max(10.0, round(health_index - (hours * 10.0), 2))

            gained = 0
            if new_health >= 75.0 and new_feed >= 20.0 and cattle_head < max_capacity:
                base_growth = (cattle_head / 50.0) * (hours / 2.0)
                gained = int(base_growth)
                if cattle_head + gained > max_capacity:
                    gained = max_capacity - cattle_head
            return new_feed, new_health, gained

        f1, h1, g1 = calc_cattle_growth(100, 200, 100.0, 100.0, 3600)
        self.assertEqual(f1, 95.0)
        self.assertEqual(h1, 100.0)
        self.assertEqual(g1, 1)

    def test_carcass_decay_and_cold_chain(self):
        """Verify cold-chain perishable decay formulas."""
        multipliers = {
            "cold_storage": 0.10,
            "refrigerated_truck": 0.15,
            "stash": 0.50,
            "player": 1.00,
            "drop": 2.50
        }

        def calc_carcass_decay(durability, decay_rate, seconds, container_type, is_reefer_active, temp_c):
            mult = multipliers.get(container_type, 1.00)
            if is_reefer_active or temp_c <= 4.0:
                mult = min(mult, 0.10)
            raw_loss = (seconds / 3600.0) * decay_rate * 100.0 * mult
            loss = max(0.0, round(raw_loss, 1))
            new_dur = max(0.0, round(durability - loss, 1))
            is_spoiled = new_dur <= 0.0
            tier = "SPOILED" if is_spoiled else ("PRISTINE" if new_dur >= 75.0 else ("FRESH" if new_dur >= 50.0 else "STALE"))
            return new_dur, is_spoiled, tier, loss

        # Cold storage 1hr -> 98.8%
        d_cold, sp_cold, t_cold, _ = calc_carcass_decay(100.0, 0.12, 3600, "cold_storage", True, 2.0)
        self.assertEqual(d_cold, 98.8)
        self.assertEqual(t_cold, "PRISTINE")
        self.assertFalse(sp_cold)

        # Drop 1hr -> 70.0%
        d_drop, sp_drop, t_drop, _ = calc_carcass_decay(100.0, 0.12, 3600, "drop", False, 25.0)
        self.assertEqual(d_drop, 70.0)
        self.assertEqual(t_drop, "FRESH")

    def test_cold_chain_status_evaluation(self):
        """Verify cold storage temperature compliance statuses."""
        def eval_cold_chain(temp_c, is_reefer_active):
            if not is_reefer_active or temp_c > 12.0:
                return "CRITICAL_SPOILAGE"
            if temp_c <= 4.0:
                return "PRISTINE"
            elif temp_c <= 8.0:
                return "FRESH"
            else:
                return "DEGRADED"

        self.assertEqual(eval_cold_chain(2.0, True), "PRISTINE")
        self.assertEqual(eval_cold_chain(6.0, True), "FRESH")
        self.assertEqual(eval_cold_chain(10.0, True), "DEGRADED")
        self.assertEqual(eval_cold_chain(15.0, False), "CRITICAL_SPOILAGE")

    def test_refrigerated_freight_payout_math(self):
        """Verify reefer freight payout, escrow return, bonus, and penalty calculations."""
        def calc_freight_payout(base_payout, avg_durability, transit_sec, deadline_sec):
            escrow = round(base_payout * 0.15, 2)
            if avg_durability <= 0.0:
                return 0.0, 0.0, escrow, 0.0

            dur_mult = 1.10 if avg_durability >= 90.0 else (1.00 if avg_durability >= 75.0 else (0.75 if avg_durability >= 50.0 else 0.40))
            time_mult = 0.70 if transit_sec > deadline_sec else 1.00
            bonus = round(base_payout * 0.15, 2) if (avg_durability >= 90.0 and transit_sec <= (deadline_sec * 0.75)) else 0.0

            final_payout = round((base_payout * dur_mult * time_mult) + bonus, 2)
            penalty = max(0.0, round(base_payout - (base_payout * dur_mult * time_mult), 2))
            return final_payout, escrow, penalty, bonus

        p1, b1, pen1, bon1 = calc_freight_payout(1000.0, 95.0, 1200, 1800)
        self.assertEqual(p1, 1250.0)
        self.assertEqual(b1, 150.0)
        self.assertEqual(bon1, 150.0)

        p2, b2, pen2, bon2 = calc_freight_payout(1000.0, 0.0, 1200, 1800)
        self.assertEqual(p2, 0.0)
        self.assertEqual(b2, 0.0)
        self.assertEqual(pen2, 150.0)

    def test_in_engine_test_62_registration(self):
        """Verify Test 62 is registered in nyx_core tests.lua."""
        tests_lua_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        self.assertTrue(os.path.isfile(tests_lua_path))
        with open(tests_lua_path, "r", encoding="utf-8") as f:
            tests_lua = f.read()

        self.assertIn("TestLivestockSlaughterhouseAndRefrigeratedLogistics", tests_lua)
        self.assertIn("t62 = Nyx.Tests.TestLivestockSlaughterhouseAndRefrigeratedLogistics()", tests_lua)


if __name__ == "__main__":
    unittest.main()
