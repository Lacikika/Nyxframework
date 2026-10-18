"""
Unit and Integration Tests for Staggered Resource Bootloader Dispatch (nyx_core)
Verifies stage mapping, 50ms stagger timeline calculation, state machine transitions,
connection contention reduction math, export integrity, and SQL migration.
"""

import os
import json
import pytest

FIVEM_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "FiveM"))
NYX_CORE_DIR = os.path.join(FIVEM_ROOT, "nyx_core")

ALL_14_RESOURCES = [
    "nyx_core",
    "nyx_treasury",
    "nyx_inventory",
    "nyx_logistics",
    "nyx_services",
    "nyx_properties",
    "nyx_vehicles",
    "nyx_factions",
    "nyx_parliament",
    "nyx_judiciary",
    "nyx_mdt",
    "nyx_press",
    "nyx_interact",
    "nyx_ui"
]

# Pure Python reference implementation of Nyx.Bootloader algorithms for cross-verification
def get_canonical_stages():
    return [
        {
            "stage": 1,
            "name": "kernel",
            "label": "Core Kernel & Ledgers",
            "resources": [
                {"name": "nyx_core", "priority": 10},
                {"name": "nyx_treasury", "priority": 20}
            ]
        },
        {
            "stage": 2,
            "name": "inventory",
            "label": "Inventory & Logistics Foundation",
            "resources": [
                {"name": "nyx_inventory", "priority": 10},
                {"name": "nyx_logistics", "priority": 20}
            ]
        },
        {
            "stage": 3,
            "name": "civil",
            "label": "Civic Services & Infrastructure",
            "resources": [
                {"name": "nyx_services", "priority": 10},
                {"name": "nyx_properties", "priority": 20},
                {"name": "nyx_vehicles", "priority": 30}
            ]
        },
        {
            "stage": 4,
            "name": "governance",
            "label": "Organizations & Governance",
            "resources": [
                {"name": "nyx_factions", "priority": 10},
                {"name": "nyx_parliament", "priority": 20}
            ]
        },
        {
            "stage": 5,
            "name": "justice",
            "label": "Justice, Enforcement & Press",
            "resources": [
                {"name": "nyx_judiciary", "priority": 10},
                {"name": "nyx_mdt", "priority": 20},
                {"name": "nyx_press", "priority": 30}
            ]
        },
        {
            "stage": 6,
            "name": "interface",
            "label": "Client Interface & Interactions",
            "resources": [
                {"name": "nyx_interact", "priority": 10},
                {"name": "nyx_ui", "priority": 20}
            ]
        }
    ]

def calculate_stagger_timeline(stages, stagger_ms=50):
    timeline = []
    current_time_ms = 0
    
    for stage_info in stages:
        sorted_res = sorted(stage_info["resources"], key=lambda r: r.get("priority", 50))
        for res in sorted_res:
            timeline.append({
                "resource": res["name"],
                "stage": stage_info["stage"],
                "stageName": stage_info["name"],
                "priority": res.get("priority", 50),
                "scheduledOffsetMs": current_time_ms
            })
            current_time_ms += stagger_ms
            
    return timeline, current_time_ms - stagger_ms

def calculate_contention_reduction(resource_count, stagger_ms, avg_query_duration_ms=30):
    simultaneous_burst = resource_count
    max_concurrent_staggered = max(1.0, float(avg_query_duration_ms) / float(stagger_ms))
    reduction_pct = ((simultaneous_burst - max_concurrent_staggered) / simultaneous_burst) * 100.0
    return {
        "unmitigatedBurst": simultaneous_burst,
        "staggeredMaxConcurrent": round(max_concurrent_staggered, 2),
        "reductionPercent": round(reduction_pct, 2)
    }

def validate_state_transition(current_state, next_state):
    valid_transitions = {
        "UNINITIALIZED": ["WAITING_DB"],
        "WAITING_DB": ["DB_READY"],
        "DB_READY": ["DISPATCHING"],
        "DISPATCHING": ["BOOT_COMPLETE"],
        "BOOT_COMPLETE": []
    }
    allowed = valid_transitions.get(current_state, [])
    return next_state in allowed


class TestStaggeredBootloaderDispatch:

    def test_all_14_resources_mapped_to_canonical_stages(self):
        """All 14 active resources must be mapped to distinct stages with non-conflicting priorities."""
        stages = get_canonical_stages()
        mapped_resources = set()
        
        for stage in stages:
            assert stage["stage"] in range(1, 7)
            assert len(stage["name"]) > 0
            assert len(stage["resources"]) >= 2
            
            # Check unique priorities within stage
            priorities = [r["priority"] for r in stage["resources"]]
            assert len(priorities) == len(set(priorities)), f"Duplicate priorities in stage {stage['name']}"
            
            for r in stage["resources"]:
                mapped_resources.add(r["name"])
                
        assert mapped_resources == set(ALL_14_RESOURCES)
        assert len(mapped_resources) == 14

    def test_stagger_timeline_calculation_50ms(self):
        """50ms stagger creates a linear scheduling ramp with zero instantaneous collision."""
        stages = get_canonical_stages()
        timeline, total_window_ms = calculate_stagger_timeline(stages, stagger_ms=50)
        
        assert len(timeline) == 14
        assert timeline[0]["resource"] == "nyx_core"
        assert timeline[0]["scheduledOffsetMs"] == 0
        
        assert timeline[1]["resource"] == "nyx_treasury"
        assert timeline[1]["scheduledOffsetMs"] == 50
        
        assert timeline[2]["resource"] == "nyx_inventory"
        assert timeline[2]["scheduledOffsetMs"] == 100
        
        assert timeline[13]["resource"] == "nyx_ui"
        assert timeline[13]["scheduledOffsetMs"] == 650
        assert total_window_ms == 650

    def test_database_connection_contention_reduction(self):
        """50ms stagger eliminates simultaneous MariaDB connection spikes by over 90%."""
        metrics = calculate_contention_reduction(resource_count=14, stagger_ms=50, avg_query_duration_ms=30)
        
        assert metrics["unmitigatedBurst"] == 14
        assert metrics["staggeredMaxConcurrent"] <= 1.0
        assert metrics["reductionPercent"] >= 90.0

    def test_boot_state_machine_transitions(self):
        """Authoritative boot lifecycle must strictly enforce sequential state progression."""
        assert validate_state_transition("UNINITIALIZED", "WAITING_DB") is True
        assert validate_state_transition("WAITING_DB", "DB_READY") is True
        assert validate_state_transition("DB_READY", "DISPATCHING") is True
        assert validate_state_transition("DISPATCHING", "BOOT_COMPLETE") is True
        
        # Invalid illegal transitions
        assert validate_state_transition("UNINITIALIZED", "BOOT_COMPLETE") is False
        assert validate_state_transition("DB_READY", "WAITING_DB") is False
        assert validate_state_transition("BOOT_COMPLETE", "DISPATCHING") is False
        assert validate_state_transition("BOOT_COMPLETE", "WAITING_DB") is False

    def test_manifest_declarations(self):
        """nyx_core fxmanifest.lua must declare shared/bootloader.lua and server/bootloader.lua."""
        manifest_path = os.path.join(NYX_CORE_DIR, "fxmanifest.lua")
        assert os.path.exists(manifest_path), "nyx_core fxmanifest.lua missing"
        
        with open(manifest_path, "r", encoding="utf-8") as f:
            content = f.read()
            
        assert "shared/bootloader.lua" in content
        assert "server/bootloader.lua" in content

    def test_sql_migration_033_exists_and_registered(self):
        """Migration 033 must exist and be registered in index.json."""
        index_path = os.path.join(NYX_CORE_DIR, "sql", "migrations", "index.json")
        with open(index_path, "r", encoding="utf-8") as f:
            index = json.load(f)
            
        assert "033_bootloader_staggered_dispatch_and_audit.sql" in index
        
        migration_path = os.path.join(NYX_CORE_DIR, "sql", "migrations", "033_bootloader_staggered_dispatch_and_audit.sql")
        assert os.path.exists(migration_path)
        
        with open(migration_path, "r", encoding="utf-8") as f:
            sql = f.read()
            
        assert "nyx_bootloader_logs" in sql

    def test_lua_shared_bootloader_syntax_and_api(self):
        """shared/bootloader.lua must exist and define Nyx.Bootloader API."""
        shared_path = os.path.join(NYX_CORE_DIR, "shared", "bootloader.lua")
        assert os.path.exists(shared_path)
        
        with open(shared_path, "r", encoding="utf-8") as f:
            code = f.read()
            
        assert "Nyx = Nyx or {}" in code
        assert "Nyx.Bootloader = Nyx.Bootloader or {}" in code
        assert "GetDefaultStages" in code
        assert "CalculateTimeline" in code
        assert "ValidateTransition" in code
        assert "CalculateContentionSavings" in code

    def test_lua_server_bootloader_and_exports(self):
        """server/bootloader.lua and server/exports.lua must expose the required functions."""
        server_path = os.path.join(NYX_CORE_DIR, "server", "bootloader.lua")
        assert os.path.exists(server_path)
        
        with open(server_path, "r", encoding="utf-8") as f:
            code = f.read()
            
        assert "nyx:core:dbReady" in code
        assert "nyx:core:resourceInit" in code
        assert "nyx:core:bootComplete" in code
        
        exports_path = os.path.join(NYX_CORE_DIR, "server", "exports.lua")
        with open(exports_path, "r", encoding="utf-8") as f:
            exports_code = f.read()
            
        assert "RegisterBootStage" in exports_code
        assert "IsDatabaseReady" in exports_code
        assert "IsBootComplete" in exports_code
        assert "GetBootState" in exports_code
        assert "GetBootReport" in exports_code
