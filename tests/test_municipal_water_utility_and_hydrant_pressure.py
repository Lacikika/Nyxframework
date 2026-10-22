import os
import json
import pytest

MIGRATION_FILE = "FiveM/nyx_core/sql/migrations/067_municipal_water_utility_and_hydrant_pressure.sql"
INDEX_FILE = "FiveM/nyx_core/sql/migrations/index.json"
SHARED_WATER_FILE = "FiveM/nyx_services/shared/water_utility.lua"
SERVER_WATER_FILE = "FiveM/nyx_services/server/water_utility.lua"

def test_migration_file_exists_and_registered():
    assert os.path.exists(MIGRATION_FILE)
    with open(INDEX_FILE, "r") as f:
        data = json.load(f)
        assert "067_municipal_water_utility_and_hydrant_pressure.sql" in data

def test_sql_schema_content():
    with open(MIGRATION_FILE, "r") as f:
        sql = f.read()
    assert "CREATE TABLE IF NOT EXISTS `nyx_water_reservoirs`" in sql
    assert "CREATE TABLE IF NOT EXISTS `nyx_water_pump_stations`" in sql
    assert "CREATE TABLE IF NOT EXISTS `nyx_fire_hydrants`" in sql
    assert "CREATE TABLE IF NOT EXISTS `nyx_water_contamination_events`" in sql
    assert "res_vinewood_lake" in sql
    assert "pump_vinewood_01" in sql
    assert "hydrant_vinewood_01" in sql

def test_shared_lua_formulas():
    with open(SHARED_WATER_FILE, "r") as f:
        lua = f.read()
    assert "function Nyx.WaterUtility.CalculateHydrantPressure" in lua
    assert "function Nyx.WaterUtility.CalculateContaminationDiffusion" in lua
    assert "function Nyx.WaterUtility.CalculatePurificationTreatment" in lua
    assert "function Nyx.WaterUtility.CalculateWaterConsumption" in lua

def test_server_water_utility_logic():
    with open(SERVER_WATER_FILE, "r") as f:
        lua = f.read()
    assert "Nyx.Services.ContaminateReservoir" in lua
    assert "Nyx.Services.PurifyReservoir" in lua
    assert "Nyx.Services.DraftFromHydrant" in lua
    assert "OFFLINE_POWER" in lua
    assert "services:draftHydrant" in lua
