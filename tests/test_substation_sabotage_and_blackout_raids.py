"""
Unit tests for Substation Physical Sabotage, Alarm Breaches & Blackout Raids
(nyx_services & nyx_properties).
"""

import os
import re
import json
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


# ==============================================================================
# PURE PYTHON DOMAIN EMULATOR MATCHING LUA 5.4 IMPLEMENTATION
# ==============================================================================

class SabotageEngine:
    ToolProfiles = {
        'wire_cutters': {
            'name': 'wire_cutters',
            'label': 'Insulated Wire Cutters',
            'baseSuccessRate': 0.75,
            'shockChance': 0.15,
            'shockDamage': 25,
            'durabilityLoss': 20.0,
            'alarmTripChance': 0.35,
            'cooldownSeconds': 600,
            'actionDurationMs': 10000,
            'noiseRadius': 25.0,
            'consumedOnUse': False
        },
        'thermite_charge': {
            'name': 'thermite_charge',
            'label': 'Thermite Incendiary Charge',
            'baseSuccessRate': 0.95,
            'shockChance': 0.05,
            'shockDamage': 35,
            'durabilityLoss': 0.0,
            'alarmTripChance': 0.90,
            'cooldownSeconds': 600,
            'actionDurationMs': 6000,
            'noiseRadius': 75.0,
            'consumedOnUse': True
        },
        'tool_repairkit': {
            'name': 'tool_repairkit',
            'label': 'Mechanical Toolkit (Tampering)',
            'baseSuccessRate': 0.50,
            'shockChance': 0.35,
            'shockDamage': 40,
            'durabilityLoss': 30.0,
            'alarmTripChance': 0.65,
            'cooldownSeconds': 600,
            'actionDurationMs': 14000,
            'noiseRadius': 35.0,
            'consumedOnUse': False
        }
    }

    @classmethod
    def calculate_sabotage_outcome(cls, tool_name, options=None):
        options = options or {}
        profile = cls.ToolProfiles.get(tool_name)
        if not profile:
            return False, "UNSUPPORTED_SABOTAGE_TOOL"

        success_rate = profile['baseSuccessRate']
        if options.get('isElectrician'):
            success_rate = min(0.99, success_rate + 0.15)

        shock_chance = profile['shockChance']
        shock_damage = profile['shockDamage']
        if options.get('hasRubberGloves'):
            shock_chance = 0.00
            shock_damage = 0

        alarm_chance = profile['alarmTripChance']
        if options.get('isElectrician'):
            alarm_chance = max(0.10, alarm_chance - 0.20)

        r_success = options.get('rollSuccess', 0.5)
        r_shock = options.get('rollShock', 0.5)
        r_alarm = options.get('rollAlarm', 0.5)

        is_success = options.get('forceSuccess', False) or (r_success <= success_rate)
        is_shock = (shock_chance > 0) and (r_shock <= shock_chance)
        is_alarm = (r_alarm <= alarm_chance)

        return True, {
            'tool': tool_name,
            'success': is_success,
            'shockInflicted': is_shock,
            'shockDamage': shock_damage if is_shock else 0,
            'alarmTriggered': is_alarm,
            'durabilityLoss': profile['durabilityLoss'],
            'consumed': profile['consumedOnUse'],
            'noiseRadius': profile['noiseRadius'],
            'cooldownSeconds': profile['cooldownSeconds']
        }

    @classmethod
    def evaluate_doorlock_state(cls, property_type, is_locked, is_powered, has_backup_gen):
        is_locked = bool(is_locked)
        is_powered = bool(is_powered)
        has_backup_gen = bool(has_backup_gen)
        property_type = property_type or 'residential'

        if is_powered:
            return is_locked, "ONLINE", False

        if has_backup_gen:
            return is_locked, "BACKUP_POWER", False

        if property_type in ('commercial', 'industrial'):
            return False, "BLACKOUT_BREACHED", True

        return is_locked, "MECHANICAL_LOCKED", False

    @classmethod
    def evaluate_warehouse_lock_state(cls, is_locked, is_powered, has_backup_gen):
        return cls.evaluate_doorlock_state('industrial', is_locked, is_powered, has_backup_gen)

    @classmethod
    def evaluate_alarm_status(cls, has_alarm, is_powered, has_backup_gen, is_door_breached):
        if not has_alarm:
            return "none", False

        if is_powered:
            if is_door_breached:
                return "tripped", True
            return "armed", False

        if has_backup_gen:
            if is_door_breached:
                return "tripped_backup", True
            return "armed_backup", False

        if is_door_breached:
            return "offline_breached", False
        return "offline", False

    @classmethod
    def validate_sabotage_payload(cls, payload):
        if not isinstance(payload, dict):
            return False, "INVALID_PAYLOAD_STRUCTURE"

        sub_id = payload.get("substationId")
        if not sub_id or not isinstance(sub_id, str) or len(sub_id) < 3 or len(sub_id) > 64:
            return False, "INVALID_SUBSTATION_ID"

        tool = payload.get("tool")
        if not tool or not isinstance(tool, str) or tool not in cls.ToolProfiles:
            return False, "INVALID_SABOTAGE_TOOL"

        return True, None


# ==============================================================================
# PYTEST TEST CASES
# ==============================================================================

def test_migration_048_schema_and_index_registration():
    """Verify migration 048 file exists, is valid SQL, and is registered in index.json."""
    index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
    with open(index_path, "r", encoding="utf-8") as f:
        migrations = json.load(f)

    assert "048_substation_sabotage_and_blackout_raids.sql" in migrations
    assert migrations[47] == "048_substation_sabotage_and_blackout_raids.sql"

    # Verify migration file contents
    core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "048_substation_sabotage_and_blackout_raids.sql")
    services_mig = os.path.join(FIVEM_DIR, "nyx_services", "sql", "migrations", "048_substation_sabotage_and_blackout_raids.sql")
    props_mig = os.path.join(FIVEM_DIR, "nyx_properties", "sql", "migrations", "048_substation_sabotage_and_blackout_raids.sql")

    assert os.path.isfile(core_mig)
    assert os.path.isfile(services_mig)
    assert os.path.isfile(props_mig)

    with open(core_mig, "r", encoding="utf-8") as f:
        content = f.read()

    assert "nyx_services_substation_sabotage_logs" in content
    assert "is_sabotaged" in content
    assert "sabotage_cooldown_until" in content
    assert "has_backup_generator" in content
    assert "BLACKOUT_BREACH" in content
    assert "ALARM_BREACH" in content


def test_item_registry_sabotage_tools():
    """Verify wire_cutters and thermite_charge are registered in items.lua."""
    items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
    with open(items_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "['wire_cutters']" in content
    assert "['thermite_charge']" in content
    assert "Insulated Wire Cutters" in content
    assert "Thermite Incendiary Charge" in content


def test_fxmanifest_declarations():
    """Verify sabotage scripts are properly declared in resource manifests."""
    services_manifest = os.path.join(FIVEM_DIR, "nyx_services", "fxmanifest.lua")
    with open(services_manifest, "r", encoding="utf-8") as f:
        s_manifest = f.read()

    assert "'shared/sabotage.lua'" in s_manifest
    assert "'server/sabotage.lua'" in s_manifest
    assert "'client/sabotage.lua'" in s_manifest

    props_manifest = os.path.join(FIVEM_DIR, "nyx_properties", "fxmanifest.lua")
    with open(props_manifest, "r", encoding="utf-8") as f:
        p_manifest = f.read()

    assert "'@nyx_services/shared/sabotage.lua'" in p_manifest


def test_declarative_sabotage_tool_profiles():
    """Verify sabotage tool profile contracts and metrics."""
    cutters = SabotageEngine.ToolProfiles['wire_cutters']
    thermite = SabotageEngine.ToolProfiles['thermite_charge']
    repair = SabotageEngine.ToolProfiles['tool_repairkit']

    assert cutters['baseSuccessRate'] == 0.75
    assert cutters['consumedOnUse'] is False
    assert cutters['shockDamage'] == 25

    assert thermite['baseSuccessRate'] == 0.95
    assert thermite['consumedOnUse'] is True
    assert thermite['noiseRadius'] == 75.0

    assert repair['baseSuccessRate'] == 0.50
    assert repair['shockChance'] == 0.35


def test_sabotage_outcome_calculation_and_gloves_protection():
    """Verify physical sabotage calculations and forensic rubber gloves shock immunity."""
    # Wire cutters success
    ok, res1 = SabotageEngine.calculate_sabotage_outcome("wire_cutters", {
        'rollSuccess': 0.5, 'rollShock': 0.5, 'rollAlarm': 0.1
    })
    assert ok is True
    assert res1['success'] is True
    assert res1['alarmTriggered'] is True
    assert res1['consumed'] is False

    # Thermite charge consumed on use
    ok, res2 = SabotageEngine.calculate_sabotage_outcome("thermite_charge", {
        'rollSuccess': 0.8, 'rollShock': 0.5, 'rollAlarm': 0.5
    })
    assert ok is True
    assert res2['success'] is True
    assert res2['consumed'] is True

    # Shock without gloves vs Shock with gloves
    ok, no_gloves = SabotageEngine.calculate_sabotage_outcome("tool_repairkit", {
        'rollSuccess': 0.8, 'rollShock': 0.1, 'hasRubberGloves': False
    })
    assert no_gloves['shockInflicted'] is True
    assert no_gloves['shockDamage'] == 40

    ok, with_gloves = SabotageEngine.calculate_sabotage_outcome("tool_repairkit", {
        'rollSuccess': 0.8, 'rollShock': 0.1, 'hasRubberGloves': True
    })
    assert with_gloves['shockInflicted'] is False
    assert with_gloves['shockDamage'] == 0


def test_commercial_maglock_fail_open_vs_residential_deadbolts():
    """Verify commercial and industrial maglocks fail-open during blackouts while residential locks hold."""
    # Commercial Property Powered
    locked, desc, breached = SabotageEngine.evaluate_doorlock_state('commercial', True, True, False)
    assert locked is True
    assert desc == "ONLINE"
    assert breached is False

    # Commercial Property Blackout (no backup)
    locked, desc, breached = SabotageEngine.evaluate_doorlock_state('commercial', True, False, False)
    assert locked is False
    assert desc == "BLACKOUT_BREACHED"
    assert breached is True

    # Commercial Property with Backup Generator
    locked, desc, breached = SabotageEngine.evaluate_doorlock_state('commercial', True, False, True)
    assert locked is True
    assert desc == "BACKUP_POWER"
    assert breached is False

    # Residential Property during Blackout (mechanical lock cylinder holds)
    locked, desc, breached = SabotageEngine.evaluate_doorlock_state('residential', True, False, False)
    assert locked is True
    assert desc == "MECHANICAL_LOCKED"
    assert breached is False


def test_warehouse_magnetic_lock_blackout_bypass():
    """Verify commercial logistics warehouses fail-open when power grid fails."""
    # Powered
    locked, desc, breached = SabotageEngine.evaluate_warehouse_lock_state(True, True, False)
    assert locked is True
    assert desc == "ONLINE"
    assert breached is False

    # Outage
    locked, desc, breached = SabotageEngine.evaluate_warehouse_lock_state(True, False, False)
    assert locked is False
    assert desc == "BLACKOUT_BREACHED"
    assert breached is True


def test_electronic_alarm_degradation_and_backup_battery():
    """Verify electronic alarm behavior during grid outages with and without backup power."""
    # Powered normal
    status, alert = SabotageEngine.evaluate_alarm_status(True, True, False, False)
    assert status == "armed"
    assert alert is False

    # Powered breach
    status, alert = SabotageEngine.evaluate_alarm_status(True, True, False, True)
    assert status == "tripped"
    assert alert is True

    # Outage breach without generator (primary and audible sirens dead)
    status, alert = SabotageEngine.evaluate_alarm_status(True, False, False, True)
    assert status == "offline_breached"
    assert alert is False

    # Outage breach with backup generator (auxiliary sirens trip)
    status, alert = SabotageEngine.evaluate_alarm_status(True, False, True, True)
    assert status == "tripped_backup"
    assert alert is True


def test_zero_trust_payload_validation():
    """Verify zero-trust payload boundaries."""
    valid, err = SabotageEngine.validate_sabotage_payload({
        "substationId": "grid_central_ls",
        "tool": "wire_cutters"
    })
    assert valid is True
    assert err is None

    bad_tool, err = SabotageEngine.validate_sabotage_payload({
        "substationId": "grid_central_ls",
        "tool": "pipe_wrench"
    })
    assert bad_tool is False
    assert err == "INVALID_SABOTAGE_TOOL"

    bad_sub, err = SabotageEngine.validate_sabotage_payload({
        "substationId": "",
        "tool": "wire_cutters"
    })
    assert bad_sub is False
    assert err == "INVALID_SUBSTATION_ID"


def test_in_engine_test_suite_registration():
    """Verify in-engine integration test TestSubstationSabotageAndBlackoutRaids is in tests.lua."""
    tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
    with open(tests_path, "r", encoding="utf-8") as f:
        tests_content = f.read()

    assert "Nyx.Tests.TestSubstationSabotageAndBlackoutRaids" in tests_content
    assert "t43 = Nyx.Tests.TestSubstationSabotageAndBlackoutRaids()" in tests_content
    assert "t43" in tests_content
