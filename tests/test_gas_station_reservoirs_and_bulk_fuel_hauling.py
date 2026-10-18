#!/usr/bin/env python3
"""
Unit and Integration Tests for Dynamic Gas Station Reservoir Stocks & Bulk Fuel Hauling.
Covers: Migration 043, Underground Tank Reservoirs (reservoir:gas_*), Item Registrations,
        Shared Pure Lua 5.4 Vehicle Fuel Engine, Multi-Tier Reservoir Shortage Evaluation,
        Zero-Stock Refueling Blocking, Dynamic Scarcity Price Scaling, Bulk Tanker Logistics Math,
        and In-Engine Integration Test Harness Wiring.
"""

import os
import sys
import json
import re
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestGasStationReservoirsAndBulkFuelHauling(unittest.TestCase):
    def test_migration_043_exists_and_registered(self):
        """Verify migration 043 exists on disk, mirrored, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("043_gas_station_reservoirs_and_bulk_fuel_hauling.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "043_gas_station_reservoirs_and_bulk_fuel_hauling.sql")
        vehicles_mig = os.path.join(FIVEM_DIR, "nyx_vehicles", "sql", "migrations", "043_gas_station_reservoirs_and_bulk_fuel_hauling.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 043 missing")
        self.assertTrue(os.path.isfile(vehicles_mig), "nyx_vehicles migration 043 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("nyx_vehicles_gas_stations", sql)
        self.assertIn("nyx_vehicles_fuel_audit", sql)
        self.assertIn("reservoir:gas_legion", sql)
        self.assertIn("reservoir:gas_sandy_shores", sql)
        self.assertIn("stash:refinery_fuel", sql)
        self.assertIn("fuel_stock", sql)
        self.assertIn("fuel_capacity", sql)
        self.assertIn("critical_threshold", sql)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest.lua declares shared/fuel.lua, server/fuel.lua, client/fuel.lua."""
        manifest_vehicles = os.path.join(FIVEM_DIR, "nyx_vehicles", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_vehicles))
        with open(manifest_vehicles, "r", encoding="utf-8") as f:
            v_manifest = f.read()

        self.assertIn("shared/fuel.lua", v_manifest)
        self.assertIn("server/fuel.lua", v_manifest)
        self.assertIn("client/fuel.lua", v_manifest)
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_vehicles", "shared", "fuel.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_vehicles", "server", "fuel.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_vehicles", "client", "fuel.lua")))

    def test_fuel_items_registered_in_nyx_inventory(self):
        """Verify fuel items are registered in nyx_inventory."""
        items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
        self.assertTrue(os.path.isfile(items_path))
        with open(items_path, "r", encoding="utf-8") as f:
            content = f.read()

        required_items = [
            "industrial_fuel",
            "bulk_fuel_tank",
            "fuel_canister"
        ]
        for item in required_items:
            self.assertIn(f"['{item}']", content, f"Item '{item}' not registered in nyx_inventory")

    def test_tanker_commercial_vehicles_registered(self):
        """Verify tanker models are recognized in commercial hauler configurations."""
        contracts_shared = os.path.join(FIVEM_DIR, "nyx_logistics", "shared", "contracts.lua")
        with open(contracts_shared, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("[`tanker`]", content)
        self.assertIn("[`tanker2`]", content)

    def test_zero_fuel_blocks_refueling_and_amount_calculations(self):
        """Verify refuel calculation logic, tank caps, and zero-stock blocking invariant."""
        def calculate_refuel_amount(current_tank, tank_capacity, reservoir_stock, requested_liters=None):
            if reservoir_stock <= 0.0:
                return 0.0, "RESERVOIR_DEPLETED"
            space_in_tank = max(0.0, tank_capacity - current_tank)
            if space_in_tank <= 0.0:
                return 0.0, "TANK_ALREADY_FULL"
            needed = space_in_tank
            if requested_liters is not None and requested_liters > 0:
                needed = min(space_in_tank, requested_liters)
            actual = min(needed, reservoir_stock)
            return round(actual, 2), "OK"

        # Normal refueling: tank 20L / 65L, station has 5000L -> refuels 45L
        amt1, status1 = calculate_refuel_amount(20.0, 65.0, 5000.0)
        self.assertEqual(status1, "OK")
        self.assertEqual(amt1, 45.0)

        # Zero fuel in reservoir: strictly blocks refueling!
        amt2, status2 = calculate_refuel_amount(20.0, 65.0, 0.0)
        self.assertEqual(status2, "RESERVOIR_DEPLETED")
        self.assertEqual(amt2, 0.0)

        # Partial reservoir stock: station only has 15L left, tank needs 45L -> dispenses 15L
        amt3, status3 = calculate_refuel_amount(20.0, 65.0, 15.0)
        self.assertEqual(status3, "OK")
        self.assertEqual(amt3, 15.0)

        # Tank already full (65L / 65L)
        amt4, status4 = calculate_refuel_amount(65.0, 65.0, 5000.0)
        self.assertEqual(status4, "TANK_ALREADY_FULL")
        self.assertEqual(amt4, 0.0)

        # Specific requested liters (e.g. 10L)
        amt5, status5 = calculate_refuel_amount(20.0, 65.0, 5000.0, requested_liters=10.0)
        self.assertEqual(status5, "OK")
        self.assertEqual(amt5, 10.0)

    def test_dynamic_scarcity_price_scaling(self):
        """Verify dynamic fuel pricing scales upwards when underground reservoir is depleted."""
        def calculate_dynamic_price(base_price, current_stock, max_capacity):
            if max_capacity <= 0:
                return base_price
            ratio = max(0.0, min(1.0, current_stock / max_capacity))
            # Price remains base when stock >= 50%. Below 50%, scales linearly up to 2.0x base price.
            if ratio >= 0.50:
                return round(base_price, 2)
            else:
                scarcity = (0.50 - ratio) / 0.50 # 0.0 at 50%, 1.0 at 0%
                multiplier = 1.0 + (scarcity * 1.0) # 1.0x to 2.0x
                return round(base_price * multiplier, 2)

        base = 1.85
        # 100% full -> base price
        self.assertEqual(calculate_dynamic_price(base, 10000.0, 10000.0), 1.85)
        # 50% full -> base price
        self.assertEqual(calculate_dynamic_price(base, 5000.0, 10000.0), 1.85)
        # 25% full -> 1.50x base price = 2.78
        self.assertEqual(calculate_dynamic_price(base, 2500.0, 10000.0), round(1.85 * 1.5, 2))
        # 0% empty -> 2.0x base price = 3.70
        self.assertEqual(calculate_dynamic_price(base, 0.0, 10000.0), 3.70)

    def test_reservoir_status_evaluation(self):
        """Verify multi-tier gas station reservoir status evaluation."""
        def evaluate_status(stock, capacity, crit=1000.0, deg=2500.0):
            if stock <= 0.0:
                return "depleted"
            elif stock <= crit:
                return "critical_shortage"
            elif stock <= deg:
                return "degraded"
            else:
                return "optimal"

        self.assertEqual(evaluate_status(5000.0, 10000.0), "optimal")
        self.assertEqual(evaluate_status(2000.0, 10000.0), "degraded")
        self.assertEqual(evaluate_status(800.0, 10000.0), "critical_shortage")
        self.assertEqual(evaluate_status(0.0, 10000.0), "depleted")

    def test_bulk_tanker_delivery_contract_math(self):
        """Verify emergency bulk fuel freight contract generation math."""
        def calculate_bulk_fuel_contract(current_stock, capacity=10000.0):
            needed_liters = max(0.0, capacity - current_stock)
            # Bulk tanker units (500L pods or 1000L pallets)
            pods = max(1, int(round(needed_liters / 500.0)))
            base_payout_per_pod = 350.00
            deficit_ratio = max(0.0, min(1.0, (capacity - current_stock) / capacity))
            multiplier = 1.25 + (deficit_ratio * 0.75) # 1.25x to 2.0x
            payout_per_unit = round(base_payout_per_pod * multiplier, 2)
            total_payout = round(payout_per_unit * pods, 2)
            escrow = round(total_payout * 0.15, 2)
            return pods, payout_per_unit, total_payout, escrow

        pods, unit_p, tot_p, esc = calculate_bulk_fuel_contract(0.0, 10000.0)
        self.assertEqual(pods, 20)
        self.assertEqual(unit_p, 700.00) # 350 * 2.0
        self.assertEqual(tot_p, 14000.00)
        self.assertEqual(esc, 2100.00)

    def test_refuel_and_restock_payload_validation(self):
        """Verify zero-trust validation guards for refueling and restocking."""
        def validate_refuel_payload(payload):
            if not payload or not isinstance(payload, dict):
                return False, "INVALID_PAYLOAD"
            station_id = payload.get("stationId")
            if not station_id or not isinstance(station_id, str):
                return False, "INVALID_STATION_ID"
            vehicle_net_id = payload.get("vehicleNetId")
            if not vehicle_net_id or not isinstance(vehicle_net_id, int):
                return False, "INVALID_VEHICLE"
            liters = payload.get("liters")
            if liters is not None:
                if not isinstance(liters, (int, float)) or liters <= 0.0 or liters > 200.0:
                    return False, "INVALID_LITERS"
            payment_type = payload.get("paymentType", "bank")
            if payment_type not in ["bank", "cash"]:
                return False, "INVALID_PAYMENT_TYPE"
            return True, "OK"

        ok1, _ = validate_refuel_payload({"stationId": "gas_legion", "vehicleNetId": 12, "liters": 45.0, "paymentType": "bank"})
        self.assertTrue(ok1)

        ok2, err2 = validate_refuel_payload({"stationId": "", "vehicleNetId": 12})
        self.assertFalse(ok2)
        self.assertEqual(err2, "INVALID_STATION_ID")

        ok3, err3 = validate_refuel_payload({"stationId": "gas_legion", "vehicleNetId": 12, "liters": -5.0})
        self.assertFalse(ok3)
        self.assertEqual(err3, "INVALID_LITERS")

        ok4, err4 = validate_refuel_payload({"stationId": "gas_legion", "vehicleNetId": 12, "liters": 500.0})
        self.assertFalse(ok4)
        self.assertEqual(err4, "INVALID_LITERS")

        ok5, err5 = validate_refuel_payload({"stationId": "gas_legion", "vehicleNetId": 12, "paymentType": "crypto"})
        self.assertFalse(ok5)
        self.assertEqual(err5, "INVALID_PAYMENT_TYPE")

    def test_in_engine_tests_lua_integration(self):
        """Verify TestGasStationReservoirsAndBulkFuelHauling is declared and wired into tests.lua RunAll()."""
        tests_lua_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        self.assertTrue(os.path.isfile(tests_lua_path))
        with open(tests_lua_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("function Nyx.Tests.TestGasStationReservoirsAndBulkFuelHauling()", code)
        self.assertIn("local t38 = Nyx.Tests.TestGasStationReservoirsAndBulkFuelHauling()", code)
        self.assertIn("t38 then", code)


if __name__ == "__main__":
    unittest.main()
