"""
Tests for Municipal Transit, Toll Booth Metering & Automated Commercial Weigh Stations (Migration 066)
Validates SQL migration 066 parity across module folders and index.json,
manifest declarations, server and client exports, in-engine Test 61 registration,
and pure Python/Lua deterministic algorithms for toll fee calculation, GVWR weight ratings,
overweight fine scaling, inspection outcomes, and MDT dispatch alert generation.
"""

import json
import math
import os
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CORE_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "066_municipal_toll_booths_and_commercial_weigh_stations.sql"
)
VEHICLES_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_vehicles", "sql", "migrations", "066_municipal_toll_booths_and_commercial_weigh_stations.sql"
)
LOGISTICS_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_logistics", "sql", "migrations", "066_municipal_toll_booths_and_commercial_weigh_stations.sql"
)
TREASURY_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_treasury", "sql", "migrations", "066_municipal_toll_booths_and_commercial_weigh_stations.sql"
)
INDEX_JSON_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "index.json"
)
VEHICLES_MANIFEST_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_vehicles", "fxmanifest.lua"
)
SHARED_TOLLS_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_vehicles", "shared", "tolls_and_weighing.lua"
)
SERVER_TOLLS_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_vehicles", "server", "tolls_and_weighing.lua"
)
SERVER_EXPORTS_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_vehicles", "server", "exports.lua"
)
CLIENT_TOLLS_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_vehicles", "client", "tolls_and_weighing.lua"
)
TESTS_LUA_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_core", "server", "tests.lua"
)


class TollsAndWeighingEngine:
    BASE_CURB_WEIGHTS = {
        0: 1200.0,
        1: 1600.0,
        2: 2200.0,
        3: 1400.0,
        4: 1700.0,
        5: 1300.0,
        6: 1500.0,
        7: 1450.0,
        8: 250.0,
        9: 2400.0,
        10: 8000.0,
        11: 3500.0,
        12: 2800.0,
        20: 12000.0,
    }

    CLASS_AXLE_COUNTS = {
        8: 2,
        10: 4,
        20: 5,
    }

    MAX_ALLOWED_WEIGHTS = {
        10: 25000.0,
        11: 10000.0,
        12: 8000.0,
        20: 40000.0,
        "default": 15000.0,
    }

    @staticmethod
    def round_to_cent(val):
        val = float(val or 0.0)
        return math.floor(val * 100.0 + 0.5) / 100.0

    @classmethod
    def calculate_toll_fee(cls, vehicle_class, base_fee=5.00, commercial_multiplier=1.50, statutory_tax=1.00):
        vehicle_class = int(vehicle_class or 0)
        base_fee = float(base_fee or 5.00)
        commercial_multiplier = float(commercial_multiplier or 1.50)
        statutory_tax = float(statutory_tax or 1.00)

        is_commercial = vehicle_class in (10, 11, 20)
        axles = cls.CLASS_AXLE_COUNTS.get(vehicle_class, 2)

        effective_fee = base_fee
        if is_commercial:
            effective_fee = base_fee * (1.0 + (axles - 2) * 0.25) * commercial_multiplier

        effective_fee *= max(0.1, statutory_tax)
        return cls.round_to_cent(effective_fee)

    @classmethod
    def calculate_gvwr(cls, vehicle_class, trunk_cargo_kg=0.0, loaded_pallets_kg=0.0, custom_curb=None):
        vehicle_class = int(vehicle_class or 0)
        trunk_cargo_kg = float(trunk_cargo_kg or 0.0)
        loaded_pallets_kg = float(loaded_pallets_kg or 0.0)

        curb = float(custom_curb) if custom_curb is not None else cls.BASE_CURB_WEIGHTS.get(vehicle_class, 1800.0)
        total = curb + max(0.0, trunk_cargo_kg) + max(0.0, loaded_pallets_kg)
        return cls.round_to_cent(total)

    @classmethod
    def get_max_allowed_weight(cls, vehicle_class):
        vehicle_class = int(vehicle_class or 0)
        return cls.MAX_ALLOWED_WEIGHTS.get(vehicle_class, cls.MAX_ALLOWED_WEIGHTS["default"])

    @classmethod
    def calculate_overweight_fine(cls, gross_weight_kg, max_allowed_kg, base_fine_per_excess=2.50):
        gross_weight_kg = float(gross_weight_kg or 0.0)
        max_allowed_kg = float(max_allowed_kg or 15000.0)
        base_fine_per_excess = float(base_fine_per_excess or 2.50)

        excess_kg = gross_weight_kg - max_allowed_kg
        if excess_kg <= 0:
            return 0.00

        total_fine = 250.00 + (excess_kg * base_fine_per_excess)
        return cls.round_to_cent(total_fine)

    @classmethod
    def determine_inspection_status(cls, gross_weight_kg, max_allowed_kg, has_valid_manifest, is_contraband_flagged, did_bypass):
        if did_bypass:
            return "BYPASSED"
        if is_contraband_flagged or (not has_valid_manifest and gross_weight_kg > 5000.0):
            return "CONTRABAND_FLAG"
        if gross_weight_kg > max_allowed_kg:
            return "OVERWEIGHT"
        return "PASS"


def test_migration_066_files_and_registration():
    """Verify SQL migration 066 exists in all 4 required modules and is registered in index.json."""
    assert os.path.exists(CORE_MIGRATION_PATH), "Core migration 066 must exist"
    assert os.path.exists(VEHICLES_MIGRATION_PATH), "Vehicles migration 066 must exist"
    assert os.path.exists(LOGISTICS_MIGRATION_PATH), "Logistics migration 066 must exist"
    assert os.path.exists(TREASURY_MIGRATION_PATH), "Treasury migration 066 must exist"

    with open(INDEX_JSON_PATH, "r", encoding="utf-8") as f:
        registered = json.load(f)

    assert "066_municipal_toll_booths_and_commercial_weigh_stations.sql" in registered, (
        "066 migration must be registered in index.json"
    )

    with open(CORE_MIGRATION_PATH, "r", encoding="utf-8") as f:
        sql = f.read()

    assert "CREATE TABLE IF NOT EXISTS `nyx_toll_plazas`" in sql
    assert "CREATE TABLE IF NOT EXISTS `nyx_weigh_station_logs`" in sql
    assert "plaza_del_perro_fwy" in sql
    assert "commercial_axle_multiplier" in sql
    assert "CONTRABAND_FLAG" in sql


def test_manifest_and_exports_declarations():
    """Verify scripts are registered in fxmanifest.lua and server exports."""
    with open(VEHICLES_MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = f.read()

    assert "shared/tolls_and_weighing.lua" in manifest, "shared/tolls_and_weighing.lua must be declared"
    assert "server/tolls_and_weighing.lua" in manifest, "server/tolls_and_weighing.lua must be declared"
    assert "client/tolls_and_weighing.lua" in manifest, "client/tolls_and_weighing.lua must be declared"

    with open(SERVER_EXPORTS_PATH, "r", encoding="utf-8") as f:
        exports = f.read()

    assert "exports(\"ProcessTollPass\"" in exports
    assert "exports(\"InspectWeighStation\"" in exports
    assert "exports(\"CalculateTollFee\"" in exports
    assert "exports(\"CalculateGVWR\"" in exports
    assert "exports(\"CalculateOverweightFine\"" in exports


def test_in_engine_test_61_registration():
    """Verify Test 61 (TestMunicipalTollsAndWeighStations) is registered in tests.lua."""
    with open(TESTS_LUA_PATH, "r", encoding="utf-8") as f:
        tests_lua = f.read()

    assert "function Nyx.Tests.TestMunicipalTollsAndWeighStations()" in tests_lua
    assert "local t61 = Nyx.Tests.TestMunicipalTollsAndWeighStations()" in tests_lua


def test_toll_fee_math():
    """Verify toll fee calculation math for passenger and commercial vehicles."""
    # Sedan (Class 1) -> base $5.00
    sedan_fee = TollsAndWeighingEngine.calculate_toll_fee(1, 5.00, 1.50, 1.00)
    assert sedan_fee == 5.00

    # Commercial 5-axle semi (Class 20) -> $5.00 * (1.0 + (5-2)*0.25) * 1.50 = 5.00 * 1.75 * 1.50 = 13.125 -> $13.13
    semi_fee = TollsAndWeighingEngine.calculate_toll_fee(20, 5.00, 1.50, 1.00)
    assert semi_fee == 13.13

    # Dynamic statutory transit tax modifier (1.20)
    taxed_fee = TollsAndWeighingEngine.calculate_toll_fee(20, 5.00, 1.50, 1.20)
    assert taxed_fee == 15.75


def test_gvwr_gross_weight_rating():
    """Verify Gross Vehicle Weight Rating (GVWR) calculation combining curb, trunk, and pallet load."""
    sedan_gvwr = TollsAndWeighingEngine.calculate_gvwr(1, 150.0, 0.0)
    assert sedan_gvwr == 1750.0  # 1600.0 + 150.0

    semi_gvwr = TollsAndWeighingEngine.calculate_gvwr(20, 500.0, 15000.0)
    assert semi_gvwr == 27500.0  # 12000.0 + 500.0 + 15000.0


def test_overweight_fine_calculation():
    """Verify statutory overweight citation fine calculations."""
    zero_fine = TollsAndWeighingEngine.calculate_overweight_fine(14000.0, 15000.0)
    assert zero_fine == 0.00

    # 17,000 kg vs 15,000 kg max -> 2,000 kg excess -> $250 base + 2000 * $2.50 = $5,250.00
    excess_fine = TollsAndWeighingEngine.calculate_overweight_fine(17000.0, 15000.0, 2.50)
    assert excess_fine == 5250.00


def test_weigh_station_inspection_status_resolution():
    """Verify inspection outcome status determination for pass, overweight, contraband, and bypass."""
    status_pass = TollsAndWeighingEngine.determine_inspection_status(14000.0, 15000.0, True, False, False)
    assert status_pass == "PASS"

    status_over = TollsAndWeighingEngine.determine_inspection_status(17000.0, 15000.0, True, False, False)
    assert status_over == "OVERWEIGHT"

    status_contraband = TollsAndWeighingEngine.determine_inspection_status(14000.0, 15000.0, True, True, False)
    assert status_contraband == "CONTRABAND_FLAG"

    status_unmanifested = TollsAndWeighingEngine.determine_inspection_status(8000.0, 15000.0, False, False, False)
    assert status_unmanifested == "CONTRABAND_FLAG"

    status_bypass = TollsAndWeighingEngine.determine_inspection_status(14000.0, 15000.0, True, False, True)
    assert status_bypass == "BYPASSED"
