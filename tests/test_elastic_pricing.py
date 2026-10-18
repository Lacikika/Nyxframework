#!/usr/bin/env python3
"""
Unit and Integration Tests for Nyxframework Localized Elastic Item Pricing & Zone Demand System
"""

import os
import sys
import json
import math
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")

class TestElasticPricingSystem(unittest.TestCase):
    def test_logistics_config_delivery_zones(self):
        """Verify Config.DeliveryZones is defined in nyx_logistics/config.lua."""
        config_path = os.path.join(FIVEM_DIR, "nyx_logistics", "config.lua")
        self.assertTrue(os.path.isfile(config_path), "nyx_logistics config.lua missing")
        with open(config_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("Config.DeliveryZones =", content)
        self.assertIn("DefaultZoneId = \"zone_ls_metro\"", content)
        self.assertIn("VelocityHalfLifeSeconds = 1800", content)
        self.assertIn("VelocityImpactFactor =", content)
        self.assertIn("ShortageBountyScaling = true", content)

    def test_fxmanifest_declarations(self):
        """Verify zones scripts are properly registered in nyx_logistics fxmanifest.lua."""
        manifest_path = os.path.join(FIVEM_DIR, "nyx_logistics", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_path))
        with open(manifest_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("'shared/zones.lua'", content)
        self.assertIn("'server/zones.lua'", content)
        self.assertIn("'client/zones.lua'", content)

        # Confirm files exist on disk
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_logistics", "shared", "zones.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_logistics", "server", "zones.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_logistics", "client", "zones.lua")))

    def test_migration_014_registered(self):
        """Verify migration 014 exists on disk and is registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        with open(index_path, "r", encoding="utf-8") as f:
            index_data = json.load(f)

        self.assertIn("014_logistics_elastic_pricing_zones.sql", index_data)

        mig_core = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "014_logistics_elastic_pricing_zones.sql")
        mig_log = os.path.join(FIVEM_DIR, "nyx_logistics", "sql", "migrations", "014_logistics_elastic_pricing_zones.sql")
        self.assertTrue(os.path.isfile(mig_core))
        self.assertTrue(os.path.isfile(mig_log))

        with open(mig_core, "r", encoding="utf-8") as f:
            sql = f.read()
        self.assertIn("CREATE TABLE IF NOT EXISTS `nyx_logistics_zones`", sql)
        self.assertIn("ALTER TABLE `nyx_logistics_shelves`", sql)
        self.assertIn("CREATE TABLE IF NOT EXISTS `nyx_logistics_price_history`", sql)

    def test_elastic_pricing_zone_demand_math(self):
        """Simulate localized stock-to-demand ratio and elastic price calculation."""
        base_price = 100.00
        target_capacity = 100
        alpha = 1.25

        def calculate_price(stock, demand_mult=1.00, vel_ratio=0.0):
            effective_demand = target_capacity * demand_mult * (1.0 + vel_ratio)
            raw = 1.0 + (alpha * ((effective_demand - stock) / effective_demand))
            bounded = max(0.50, min(2.25, raw))
            price = math.floor((base_price * bounded) * 100) / 100
            s_to_d = round(stock / effective_demand, 4)
            return price, effective_demand, s_to_d

        # Test Metro (1.35x multiplier): high demand creates higher price at equilibrium stock (100)
        p_metro, eff_metro, r_metro = calculate_price(100, 1.35, 0.0)
        self.assertEqual(eff_metro, 135.0)
        self.assertEqual(p_metro, 132.40)
        self.assertAlmostEqual(r_metro, 100 / 135.0, places=4)

        # Test Paleto (0.75x multiplier): low demand creates surplus discount at equilibrium stock (100)
        p_paleto, eff_paleto, r_paleto = calculate_price(100, 0.75, 0.0)
        self.assertEqual(eff_paleto, 75.0)
        self.assertEqual(p_paleto, 58.33)
        self.assertAlmostEqual(r_paleto, 100 / 75.0, places=4)

        # Test Shortage Ceiling clamp (0 stock)
        p_empty, _, _ = calculate_price(0, 1.35, 0.0)
        self.assertEqual(p_empty, 225.00)

        # Test Surplus Floor clamp (500 stock)
        p_surplus, _, _ = calculate_price(500, 0.75, 0.0)
        self.assertEqual(p_surplus, 50.00)

    def test_velocity_exponential_decay_math(self):
        """Simulate rolling demand velocity half-life decay."""
        def decay_velocity(v0, dt_seconds, half_life=1800):
            return math.floor((v0 * (0.5 ** (dt_seconds / half_life))) * 100) / 100

        v_initial = 20.0
        # Exactly 1 half life (1800s) -> 10.0
        self.assertEqual(decay_velocity(v_initial, 1800), 10.0)
        # Exactly 2 half lives (3600s) -> 5.0
        self.assertEqual(decay_velocity(v_initial, 3600), 5.0)
        # 0 seconds elapsed -> 20.0
        self.assertEqual(decay_velocity(v_initial, 0), 20.0)

    def test_treasury_zone_tax_split(self):
        """Verify treasury localized sales tax split logic."""
        def calc_tax(gross, base_rate, surcharge):
            eff_rate = min(0.15, base_rate + surcharge)
            tax = math.floor((gross * eff_rate) * 100) / 100
            net = gross - tax
            return net, tax, eff_rate

        gross = 1000.00
        base_tax = 0.08

        # Metro: 8% + 1.5% = 9.5%
        net_m, tax_m, rate_m = calc_tax(gross, base_tax, 0.0150)
        self.assertEqual(rate_m, 0.095)
        self.assertEqual(tax_m, 95.00)
        self.assertEqual(net_m, 905.00)

        # Rural: 8% + 0.0% = 8.0%
        net_r, tax_r, rate_r = calc_tax(gross, base_tax, 0.0000)
        self.assertEqual(rate_r, 0.080)
        self.assertEqual(tax_r, 80.00)
        self.assertEqual(net_r, 920.00)

    def test_dynamic_shortage_bounty_scaling(self):
        """Verify freight contract payout scales proportionally with zone stock deficit."""
        base_price = 100.00
        base_bounty_mult = 0.35

        def calculate_bounty(deficit_ratio, zone_mult):
            scale_bonus = min(1.50, deficit_ratio * zone_mult)
            mult = min(2.25, base_bounty_mult * (1.0 + scale_bonus))
            return math.floor((base_price * mult) * 100) / 100, mult

        # 10% deficit in standard zone
        payout_normal, mult_norm = calculate_bounty(0.10, 1.00)
        # 95% deficit in high-demand metro
        payout_crit, mult_crit = calculate_bounty(0.95, 1.35)

        self.assertGreater(payout_crit, payout_normal)
        self.assertGreater(mult_crit, mult_norm)

    def test_in_engine_tests_registered(self):
        """Verify TestElasticItemPricingAndZoneDemand is registered in server/tests.lua."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        with open(tests_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("function Nyx.Tests.TestElasticItemPricingAndZoneDemand()", code)
        self.assertIn("local t7 = Nyx.Tests.TestElasticItemPricingAndZoneDemand()", code)
        self.assertIn("if t1 and t2 and t3 and t4 and t5 and t6 and t7 then", code)

if __name__ == "__main__":
    unittest.main()
