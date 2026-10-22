"""
Tests for Highway Road Degradation, Heavy Freight Transit Wear & Infrastructure Repairs (Migration 067)
Validates SQL migration 067 parity across core, vehicles, services, and treasury folders, index.json registration,
fxmanifest declarations, server exports, in-engine Test 62 registration, and pure Python/Lua deterministic algorithms
for axle damage factor calculation, road quality decay, handling penalties, and repair material requirements.
"""

import json
import math
import os
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CORE_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "067_highway_degradation_and_transit_repair.sql"
)
VEHICLES_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_vehicles", "sql", "migrations", "067_highway_degradation_and_transit_repair.sql"
)
SERVICES_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_services", "sql", "migrations", "067_highway_degradation_and_transit_repair.sql"
)
TREASURY_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_treasury", "sql", "migrations", "067_highway_degradation_and_transit_repair.sql"
)
INDEX_JSON_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "index.json"
)
VEHICLES_MANIFEST_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_vehicles", "fxmanifest.lua"
)
SERVER_EXPORTS_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_vehicles", "server", "exports.lua"
)
TESTS_LUA_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_core", "server", "tests.lua"
)


class RoadDegradationEngine:
    @staticmethod
    def round_to_cent(val):
        val = float(val or 0.0)
        return math.floor(val * 100.0 + 0.5) / 100.0

    @classmethod
    def calculate_axle_damage_factor(cls, gross_weight_kg, axle_count=2):
        gross_weight_kg = max(100.0, float(gross_weight_kg or 1500.0))
        axle_count = max(1, int(axle_count or 2))

        weight_per_axle = gross_weight_kg / axle_count
        baseline_axle_weight = 2000.0

        ratio = weight_per_axle / baseline_axle_weight
        factor = (ratio ** 4.0) * (axle_count / 2.0)
        return cls.round_to_cent(factor)

    @classmethod
    def calculate_road_quality_decay(cls, heavy_passages, baseline_quality=100.0, time_elapsed_hours=0.0):
        heavy_passages = max(0, int(heavy_passages or 0))
        baseline_quality = min(100.0, max(0.0, float(baseline_quality or 100.0)))
        time_elapsed_hours = max(0.0, float(time_elapsed_hours or 0.0))

        passage_loss = heavy_passages * 0.15
        time_loss = time_elapsed_hours * 0.05

        remaining = baseline_quality - passage_loss - time_loss
        remaining = min(100.0, max(0.0, remaining))
        return cls.round_to_cent(remaining)

    @classmethod
    def calculate_handling_penalty(cls, road_quality_pct):
        road_quality_pct = min(100.0, max(0.0, float(road_quality_pct or 100.0)))

        grip_multiplier = 1.00
        suspension_wear_multiplier = 1.00
        status = "OPTIMAL"

        if road_quality_pct < 30.0:
            status = "CRITICAL"
            grip_multiplier = 0.65
            suspension_wear_multiplier = 2.50
        elif road_quality_pct < 60.0:
            status = "DEGRADED"
            grip_multiplier = 0.80
            suspension_wear_multiplier = 1.75
        elif road_quality_pct < 85.0:
            status = "WEAR_WARNING"
            grip_multiplier = 0.92
            suspension_wear_multiplier = 1.25

        return {
            "grip_multiplier": cls.round_to_cent(grip_multiplier),
            "suspension_wear_multiplier": cls.round_to_cent(suspension_wear_multiplier),
            "status": status,
        }

    @classmethod
    def calculate_repair_cost_and_materials(cls, segment_length_meters, quality_loss_pct):
        segment_length_meters = max(10.0, float(segment_length_meters or 1000.0))
        quality_loss_pct = min(100.0, max(0.0, float(quality_loss_pct or 0.0)))

        required_asphalt_kg = (segment_length_meters * 10.0) * (quality_loss_pct / 100.0)
        treasury_payout = required_asphalt_kg * 2.50

        return {
            "required_asphalt_kg": cls.round_to_cent(required_asphalt_kg),
            "treasury_payout": cls.round_to_cent(treasury_payout),
        }


def test_migration_067_files_and_registration():
    """Verify SQL migration 067 exists in core, vehicles, services, treasury and is registered in index.json."""
    assert os.path.exists(CORE_MIGRATION_PATH), "Core migration 067 must exist"
    assert os.path.exists(VEHICLES_MIGRATION_PATH), "Vehicles migration 067 must exist"
    assert os.path.exists(SERVICES_MIGRATION_PATH), "Services migration 067 must exist"
    assert os.path.exists(TREASURY_MIGRATION_PATH), "Treasury migration 067 must exist"

    with open(INDEX_JSON_PATH, "r", encoding="utf-8") as f:
        registered = json.load(f)

    assert "067_highway_degradation_and_transit_repair.sql" in registered, (
        "067 migration must be registered in index.json"
    )

    with open(CORE_MIGRATION_PATH, "r", encoding="utf-8") as f:
        sql = f.read()

    assert "CREATE TABLE IF NOT EXISTS `nyx_highway_segments`" in sql
    assert "CREATE TABLE IF NOT EXISTS `nyx_road_repair_contracts`" in sql
    assert "seg_del_perro_fwy_1" in sql
    assert "total_heavy_axle_passages" in sql


def test_manifest_and_exports_declarations():
    """Verify scripts are registered in fxmanifest.lua and server exports."""
    with open(VEHICLES_MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = f.read()

    assert "shared/road_degradation.lua" in manifest
    assert "server/road_degradation.lua" in manifest
    assert "client/road_degradation.lua" in manifest

    with open(SERVER_EXPORTS_PATH, "r", encoding="utf-8") as f:
        exports = f.read()

    assert 'exports("RecordHighwayTransitPass"' in exports
    assert 'exports("GetHighwaySegmentCondition"' in exports
    assert 'exports("SubmitRoadRepairBatch"' in exports
    assert 'exports("CalculateAxleDamageFactor"' in exports


def test_in_engine_test_62_registration():
    """Verify Test 62 (TestHighwayDegradationAndTransitRepair) is registered in tests.lua."""
    with open(TESTS_LUA_PATH, "r", encoding="utf-8") as f:
        tests_lua = f.read()

    assert "function Nyx.Tests.TestHighwayDegradationAndTransitRepair()" in tests_lua
    assert "local t62 = Nyx.Tests.TestHighwayDegradationAndTransitRepair()" in tests_lua


def test_axle_damage_factor_fourth_power_law():
    """Verify 4th-power law pavement stress calculation."""
    # 2,000 kg 2-axle passenger car -> 1,000 kg per axle vs 2,000 kg baseline -> ratio 0.5^4 * (2/2) = 0.0625 -> 0.06
    car_factor = RoadDegradationEngine.calculate_axle_damage_factor(2000.0, 2)
    assert car_factor == 0.06

    # 20,000 kg 5-axle semi -> 4,000 kg per axle vs 2,000 kg baseline -> ratio 2.0^4 * (5/2) = 16 * 2.5 = 40.0
    semi_factor = RoadDegradationEngine.calculate_axle_damage_factor(20000.0, 5)
    assert semi_factor == 40.0


def test_road_quality_decay():
    """Verify quality degradation from heavy axle passages and time elapsed."""
    q_init = RoadDegradationEngine.calculate_road_quality_decay(0, 100.0, 0.0)
    assert q_init == 100.0

    # 100 heavy passages (15.0% loss) + 20 hours (1.0% loss) -> 84.0%
    q_decay = RoadDegradationEngine.calculate_road_quality_decay(100, 100.0, 20.0)
    assert q_decay == 84.0


def test_handling_penalty_modifiers():
    """Verify traction and suspension modifiers across road quality tiers."""
    opt = RoadDegradationEngine.calculate_handling_penalty(90.0)
    assert opt["status"] == "OPTIMAL"
    assert opt["grip_multiplier"] == 1.00

    warn = RoadDegradationEngine.calculate_handling_penalty(75.0)
    assert warn["status"] == "WEAR_WARNING"
    assert warn["grip_multiplier"] == 0.92

    deg = RoadDegradationEngine.calculate_handling_penalty(50.0)
    assert deg["status"] == "DEGRADED"
    assert deg["grip_multiplier"] == 0.80

    crit = RoadDegradationEngine.calculate_handling_penalty(20.0)
    assert crit["status"] == "CRITICAL"
    assert crit["grip_multiplier"] == 0.65


def test_repair_cost_and_materials():
    """Verify asphalt requirements and treasury payout calculation."""
    # 1,000m segment with 20% quality loss -> 1,000 * 10 * 0.20 = 2,000 kg asphalt -> $5,000 payout
    repair = RoadDegradationEngine.calculate_repair_costAnd_materials = RoadDegradationEngine.calculate_repair_cost_and_materials(1000.0, 20.0)
    assert repair["required_asphalt_kg"] == 2000.0
    assert repair["treasury_payout"] == 5000.0
