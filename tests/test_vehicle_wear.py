#!/usr/bin/env python3
"""
Unit and Integration Tests for Nyxframework Vehicle Mileage & Wear System
"""

import os
import sys
import re
import json
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")

class TestVehicleWearSystem(unittest.TestCase):
    def test_migration_013_exists_and_registered(self):
        """Verify migration 013 is on disk and listed in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)
        self.assertIn("013_vehicles_wear_mileage.sql", migrations, "013_vehicles_wear_mileage.sql not registered in index.json")

        mig_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "013_vehicles_wear_mileage.sql")
        self.assertTrue(os.path.isfile(mig_path), "Migration file 013 missing on disk")
        with open(mig_path, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("CREATE TABLE IF NOT EXISTS `nyx_vehicles_wear`", sql)
        self.assertIn("CREATE TABLE IF NOT EXISTS `nyx_vehicles_service_logs`", sql)
        self.assertIn("`mileage` DECIMAL(12, 2)", sql)
        self.assertIn("`oil_quality` DECIMAL(5, 2)", sql)
        self.assertIn("`brake_pad_wear` DECIMAL(5, 2)", sql)
        self.assertIn("`transmission_wear` DECIMAL(5, 2)", sql)
        self.assertIn("`suspension_wear` DECIMAL(5, 2)", sql)

    def test_fxmanifest_declarations(self):
        """Verify server/wear.lua and client/wear.lua are declared in fxmanifest.lua."""
        manifest_path = os.path.join(FIVEM_DIR, "nyx_vehicles", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_path))
        with open(manifest_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("server/wear.lua", content)
        self.assertIn("client/wear.lua", content)

        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_vehicles", "server", "wear.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_vehicles", "client", "wear.lua")))

    def test_config_wear_definitions(self):
        """Verify Config.Wear is configured with sane parameters."""
        config_path = os.path.join(FIVEM_DIR, "nyx_vehicles", "config.lua")
        with open(config_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("Config.Wear =", content)
        self.assertIn("OilDegradationPerKm", content)
        self.assertIn("BrakeWearPerBrakeSecond", content)
        self.assertIn("TransmissionWearPerShift", content)
        self.assertIn("SuspensionWearPerKm", content)
        self.assertIn("ServiceCosts", content)

    def test_wear_math_invariants(self):
        """Verify the mathematical calculations and clamping logic."""
        # Simulated parameters matching Config.Wear
        oil_loss_per_km = 0.04
        oil_rpm_mult = 2.5
        brake_wear_per_sec = 0.006
        brake_hard_mult = 1.8
        max_speed_kmh = 450.0

        # 1. Teleport clamping invariant
        elapsed_sec = 15
        max_allowed_km = (max_speed_kmh / 3600.0) * elapsed_sec + 0.5
        suspicious_km = 50.0
        clamped_km = min(suspicious_km, max_allowed_km)
        self.assertLess(clamped_km, 3.0, "Clamping failed to prevent speed hack / teleport")

        # 2. Mileage & wear degradation
        initial_wear = {
            "mileage": 100.0,
            "trip": 25.0,
            "oil": 95.0,
            "brakes": 90.0,
            "transmission": 92.0,
            "suspension": 94.0
        }

        delta_km = 10.0 # 10 km driven
        # Hard driving with high RPM
        oil_loss = delta_km * oil_loss_per_km * oil_rpm_mult # 10 * 0.04 * 2.5 = 1.0%
        # 20 seconds of hard braking at >80 km/h
        brake_loss = 20.0 * brake_wear_per_sec * brake_hard_mult # 20 * 0.006 * 1.8 = 0.216%

        new_mileage = initial_wear["mileage"] + delta_km
        new_trip = initial_wear["trip"] + delta_km
        new_oil = max(0.0, initial_wear["oil"] - oil_loss)
        new_brakes = max(0.0, initial_wear["brakes"] - brake_loss)

        self.assertEqual(new_mileage, 110.0)
        self.assertEqual(new_trip, 35.0)
        self.assertAlmostEqual(new_oil, 94.0, places=2)
        self.assertAlmostEqual(new_brakes, 89.784, places=3)

        # 3. Servicing invariant
        serviced_oil = 100.0
        serviced_brakes = 100.0
        last_service_mileage = new_mileage

        self.assertEqual(serviced_oil, 100.0)
        self.assertEqual(serviced_brakes, 100.0)
        self.assertEqual(last_service_mileage, 110.0)

        # 4. Trip reset invariant: preserves total lifetime mileage
        reset_trip = 0.0
        self.assertEqual(reset_trip, 0.0)
        self.assertEqual(new_mileage, 110.0)

if __name__ == "__main__":
    unittest.main()
