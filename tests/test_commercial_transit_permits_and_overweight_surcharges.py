"""
Tests for Commercial Heavy Transit Permits & Overweight Surcharges (Migration 068)
Validates SQL migration 068 parity across module folders and index.json,
manifest declarations, server exports, in-engine Test 63 registration,
and pure Python/Lua deterministic algorithms for permit fee calculations,
surcharges, validity evaluations, and MDT violation classification.
"""

import json
import math
import os
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CORE_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "068_commercial_transit_permits_and_overweight_surcharges.sql"
)
VEHICLES_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_vehicles", "sql", "migrations", "068_commercial_transit_permits_and_overweight_surcharges.sql"
)
LOGISTICS_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_logistics", "sql", "migrations", "068_commercial_transit_permits_and_overweight_surcharges.sql"
)
TREASURY_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_treasury", "sql", "migrations", "068_commercial_transit_permits_and_overweight_surcharges.sql"
)
SERVICES_MIGRATION_PATH = os.path.join(
    ROOT_DIR, "FiveM", "nyx_services", "sql", "migrations", "068_commercial_transit_permits_and_overweight_surcharges.sql"
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


class TransitPermitsEngine:
    BASE_PERMIT_FEES = {
        "SINGLE_TRIP": 150.00,
        "DAILY_PASS": 450.00,
        "ANNUAL_HEAVY_HAUL": 2500.00,
    }

    PERMIT_CAPACITIES = {
        "SINGLE_TRIP": 25000.0,
        "DAILY_PASS": 35000.0,
        "ANNUAL_HEAVY_HAUL": 60000.0,
    }

    @staticmethod
    def round_to_cent(val):
        val = float(val or 0.0)
        return math.floor(val * 100.0 + 0.5) / 100.0

    @classmethod
    def calculate_permit_fee(cls, permit_type="SINGLE_TRIP", requested_max_weight_kg=25000.0, statutory_tax_rate=1.00):
        base_fee = cls.BASE_PERMIT_FEES.get(permit_type, 150.00)
        base_cap = cls.PERMIT_CAPACITIES.get(permit_type, 25000.0)

        excess_kg = max(0.0, float(requested_max_weight_kg) - base_cap)
        surcharge = excess_kg * 0.05

        gross = (base_fee + surcharge) * max(0.1, float(statutory_tax_rate))
        return cls.round_to_cent(gross), cls.round_to_cent(surcharge)

    @classmethod
    def evaluate_permit_validity(cls, permit_record, measured_weight_kg, current_timestamp_epoch):
        measured_weight_kg = float(measured_weight_kg or 0.0)
        current_timestamp_epoch = float(current_timestamp_epoch or 0.0)

        if not permit_record or not isinstance(permit_record, dict):
            return False, "NO_PERMIT"

        if permit_record.get("status") != "ACTIVE":
            return False, "EXPIRED"

        expiry_epoch = float(permit_record.get("expires_at_epoch") or 0.0)
        if expiry_epoch > 0 and current_timestamp_epoch >= expiry_epoch:
            return False, "EXPIRED"

        permitted_cap_kg = float(permit_record.get("max_weight_capacity_kg") or 25000.0)
        if measured_weight_kg > permitted_cap_kg:
            return False, "WEIGHT_EXCEEDED"

        return True, "VALID"

    @classmethod
    def classify_violation_and_fine(cls, validity_status, measured_weight_kg, permitted_weight_kg, did_bypass):
        measured_weight_kg = float(measured_weight_kg or 0.0)
        permitted_weight_kg = float(permitted_weight_kg or 15000.0)

        if did_bypass and validity_status != "VALID":
            return "BYPASS_UNLICENSED", 1500.00

        if validity_status == "NO_PERMIT":
            return "NO_PERMIT", 750.00
        elif validity_status == "EXPIRED":
            return "PERMIT_EXPIRED", 500.00
        elif validity_status == "WEIGHT_EXCEEDED":
            excess_kg = max(0.0, measured_weight_kg - permitted_weight_kg)
            fine = 500.00 + (excess_kg * 3.00)
            return "WEIGHT_EXCEEDED", cls.round_to_cent(fine)

        return "NONE", 0.00


def test_migration_068_files_and_registration():
    """Verify SQL migration 068 exists in all 5 required modules and is registered in index.json."""
    assert os.path.exists(CORE_MIGRATION_PATH), "Core migration 068 must exist"
    assert os.path.exists(VEHICLES_MIGRATION_PATH), "Vehicles migration 068 must exist"
    assert os.path.exists(LOGISTICS_MIGRATION_PATH), "Logistics migration 068 must exist"
    assert os.path.exists(TREASURY_MIGRATION_PATH), "Treasury migration 068 must exist"
    assert os.path.exists(SERVICES_MIGRATION_PATH), "Services migration 068 must exist"

    with open(INDEX_JSON_PATH, "r", encoding="utf-8") as f:
        registered = json.load(f)

    assert "068_commercial_transit_permits_and_overweight_surcharges.sql" in registered, (
        "068 migration must be registered in index.json"
    )

    with open(CORE_MIGRATION_PATH, "r", encoding="utf-8") as f:
        sql = f.read()

    assert "CREATE TABLE IF NOT EXISTS `nyx_commercial_transit_permits`" in sql
    assert "CREATE TABLE IF NOT EXISTS `nyx_permit_violation_logs`" in sql
    assert "ANNUAL_HEAVY_HAUL" in sql
    assert "BYPASS_UNLICENSED" in sql


def test_manifest_and_exports_declarations_068():
    """Verify scripts are registered in fxmanifest.lua and server exports."""
    with open(VEHICLES_MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = f.read()

    assert "shared/transit_permits.lua" in manifest
    assert "server/transit_permits.lua" in manifest
    assert "client/transit_permits.lua" in manifest

    with open(SERVER_EXPORTS_PATH, "r", encoding="utf-8") as f:
        exports = f.read()

    assert "exports(\"IssueTransitPermit\"" in exports
    assert "exports(\"GetActiveTransitPermit\"" in exports
    assert "exports(\"LogPermitViolation\"" in exports
    assert "exports(\"CalculatePermitFee\"" in exports
    assert "exports(\"EvaluatePermitValidity\"" in exports


def test_in_engine_test_63_registration():
    """Verify Test 63 (TestCommercialTransitPermitsAndOverweightSurcharges) is registered in tests.lua."""
    with open(TESTS_LUA_PATH, "r", encoding="utf-8") as f:
        tests_lua = f.read()

    assert "function Nyx.Tests.TestCommercialTransitPermitsAndOverweightSurcharges()" in tests_lua
    assert "local t63 = Nyx.Tests.TestCommercialTransitPermitsAndOverweightSurcharges()" in tests_lua


def test_permit_fee_and_surcharge_math():
    """Verify permit fee and heavy-haul surcharge math."""
    base_fee, base_surcharge = TransitPermitsEngine.calculate_permit_fee("SINGLE_TRIP", 25000.0, 1.00)
    assert base_fee == 150.00
    assert base_surcharge == 0.00

    # Requested 35,000 kg for SINGLE_TRIP (base cap 25,000 kg) -> 10,000 kg excess * $0.05 = $500 surcharge -> $150 + $500 = $650.00
    heavy_fee, heavy_surcharge = TransitPermitsEngine.calculate_permit_fee("SINGLE_TRIP", 35000.0, 1.00)
    assert heavy_fee == 650.00
    assert heavy_surcharge == 500.00


def test_permit_validity_evaluation():
    """Verify active permit capacity and expiration evaluation logic."""
    now = 1770000000
    mock_permit = {
        "status": "ACTIVE",
        "max_weight_capacity_kg": 35000.0,
        "expires_at_epoch": now + 86400,
    }

    is_valid, status = TransitPermitsEngine.evaluate_permit_validity(mock_permit, 30000.0, now)
    assert is_valid is True
    assert status == "VALID"

    is_valid_exceeded, status_exceeded = TransitPermitsEngine.evaluate_permit_validity(mock_permit, 40000.0, now)
    assert is_valid_exceeded is False
    assert status_exceeded == "WEIGHT_EXCEEDED"


def test_violation_classification_and_fine():
    """Verify violation classification and statutory fine scaling."""
    v_type_no, fine_no = TransitPermitsEngine.classify_violation_and_fine("NO_PERMIT", 30000.0, 25000.0, False)
    assert v_type_no == "NO_PERMIT"
    assert fine_no == 750.00

    v_type_bypass, fine_bypass = TransitPermitsEngine.classify_violation_and_fine("NO_PERMIT", 30000.0, 25000.0, True)
    assert v_type_bypass == "BYPASS_UNLICENSED"
    assert fine_bypass == 1500.00
