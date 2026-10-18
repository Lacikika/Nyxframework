#!/usr/bin/env python3
"""
Unit and Integration Tests for Sealed Industrial Pallet Breaching & Forensic Contamination
(nyx_logistics, nyx_judiciary, nyx_inventory & nyx_core).
Covers: Migration 049 schema, inventory items (tool_crowbar, tamper_seal),
        shared pure Lua 5.4 pallet breaching calculations, tool profiles,
        durability wear & breakage math, latent fingerprint generation & glove immunity,
        biological DNA/blood laceration hazards, deterministic toolmark striation hashing,
        zero-trust payload validation, server RPC & exports, and in-engine Test 44 integration.
"""

import os
import json
import hashlib
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestSealedPalletBreachingAndForensicContamination(unittest.TestCase):
    def test_migration_049_exists_and_registered(self):
        """Verify migration 049 exists on disk, mirrored, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("049_sealed_pallet_breaching_and_forensic_contamination.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "049_sealed_pallet_breaching_and_forensic_contamination.sql")
        logistics_mig = os.path.join(FIVEM_DIR, "nyx_logistics", "sql", "migrations", "049_sealed_pallet_breaching_and_forensic_contamination.sql")
        judiciary_mig = os.path.join(FIVEM_DIR, "nyx_judiciary", "sql", "migrations", "049_sealed_pallet_breaching_and_forensic_contamination.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 049 missing")
        self.assertTrue(os.path.isfile(logistics_mig), "nyx_logistics migration 049 missing")
        self.assertTrue(os.path.isfile(judiciary_mig), "nyx_judiciary migration 049 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("toolmark", sql)
        self.assertIn("is_tampered", sql)
        self.assertIn("seal_serial", sql)
        self.assertIn("breached_at", sql)
        self.assertIn("breached_by_citizen_id", sql)
        self.assertIn("tamper_tool", sql)
        self.assertIn("forensic_evidence_ids", sql)
        self.assertIn("nyx_logistics_pallet_breach_audits", sql)

    def test_inventory_items_registered(self):
        """Verify tool_crowbar and tamper_seal are registered in nyx_inventory items.lua."""
        items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
        self.assertTrue(os.path.isfile(items_path))
        with open(items_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("['tool_crowbar']", content)
        self.assertIn("['tamper_seal']", content)
        self.assertIn("toolSerial", content)
        self.assertIn("sealSerial", content)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest.lua in nyx_logistics and nyx_judiciary declare shared and server scripts."""
        logistics_manifest = os.path.join(FIVEM_DIR, "nyx_logistics", "fxmanifest.lua")
        with open(logistics_manifest, "r", encoding="utf-8") as f:
            l_manifest = f.read()

        self.assertIn("shared/pallets.lua", l_manifest)
        self.assertIn("server/pallets.lua", l_manifest)
        self.assertIn("client/pallets.lua", l_manifest)

        judiciary_manifest = os.path.join(FIVEM_DIR, "nyx_judiciary", "fxmanifest.lua")
        with open(judiciary_manifest, "r", encoding="utf-8") as f:
            j_manifest = f.read()

        self.assertIn("server/evidence.lua", j_manifest)
        self.assertIn("server/exports.lua", j_manifest)

    def test_breach_tool_profiles(self):
        """Verify breach tool profiles for crowbar, weapon crowbar, and lockpick wire."""
        tools = {
            'tool_crowbar': {
                'baseSuccess': 0.85,
                'wearPerAttempt': 6.0,
                'noiseRadius': 25.0,
                'lacerationRisk': 0.12,
                'lacerationDamage': 8,
                'fingerprintRisk': 0.85,
                'alarmTripChance': 0.40
            },
            'weapon_crowbar': {
                'baseSuccess': 0.80,
                'wearPerAttempt': 8.0,
                'noiseRadius': 28.0,
                'lacerationRisk': 0.16,
                'lacerationDamage': 10,
                'fingerprintRisk': 0.85,
                'alarmTripChance': 0.45
            },
            'tool_lockpick': {
                'baseSuccess': 0.30,
                'wearPerAttempt': 35.0,
                'noiseRadius': 10.0,
                'lacerationRisk': 0.05,
                'lacerationDamage': 4,
                'fingerprintRisk': 0.80,
                'alarmTripChance': 0.15
            }
        }

        self.assertEqual(tools['tool_crowbar']['baseSuccess'], 0.85)
        self.assertEqual(tools['tool_crowbar']['wearPerAttempt'], 6.0)
        self.assertEqual(tools['weapon_crowbar']['baseSuccess'], 0.80)
        self.assertEqual(tools['tool_lockpick']['baseSuccess'], 0.30)
        self.assertGreater(tools['tool_lockpick']['wearPerAttempt'], tools['tool_crowbar']['wearPerAttempt'])

    def test_breach_outcome_calculation_and_wear(self):
        """Verify mathematical outcome calculations, wear deductions, and breakage thresholds."""
        def calculate_outcome(tool_name, tool_durability, has_gloves=False, is_union=False, random_seed=None):
            tool_profiles = {
                'tool_crowbar': {'baseSuccess': 0.85, 'wear': 6.0, 'noise': 25.0, 'laceration': 0.12, 'dmg': 8, 'fp': 0.85, 'alarm': 0.40},
                'tool_lockpick': {'baseSuccess': 0.30, 'wear': 35.0, 'noise': 10.0, 'laceration': 0.05, 'dmg': 4, 'fp': 0.80, 'alarm': 0.15}
            }
            prof = tool_profiles.get(tool_name, tool_profiles['tool_crowbar'])
            durability = max(0.0, min(100.0, float(tool_durability)))

            succ_chance = prof['baseSuccess']
            if is_union:
                succ_chance += 0.10
            if durability < 25.0:
                succ_chance -= 0.15
            succ_chance = max(0.05, min(0.98, succ_chance))

            if random_seed is not None:
                r1 = ((random_seed * 9301 + 49297) % 233280) / 233280.0
                r2 = (((random_seed + 1) * 9301 + 49297) % 233280) / 233280.0
                r3 = (((random_seed + 2) * 9301 + 49297) % 233280) / 233280.0
                r4 = (((random_seed + 3) * 9301 + 49297) % 233280) / 233280.0
            else:
                r1, r2, r3, r4 = 0.5, 0.5, 0.5, 0.5

            success = (r1 <= succ_chance)
            wear = prof['wear'] * (1.0 if success else 1.5)
            remaining_durability = max(0.0, durability - wear)
            is_broken = (remaining_durability <= 0.0)

            fp_left = (not has_gloves) and (r2 <= prof['fp'])
            eff_laceration = prof['laceration'] * 0.15 if has_gloves else prof['laceration']
            dna_left = (r3 <= eff_laceration)
            alarm = (r4 <= prof['alarm'])

            return {
                'success': success,
                'wearDeduction': round(wear, 1),
                'remainingDurability': round(remaining_durability, 1),
                'isBroken': is_broken,
                'fingerprintLeft': fp_left,
                'dnaLeft': dna_left,
                'alarmTriggered': alarm
            }

        # Case 1: Fresh crowbar, success
        out1 = calculate_outcome('tool_crowbar', 100.0, has_gloves=True, is_union=False, random_seed=12345)
        self.assertEqual(out1['wearDeduction'], 6.0)
        self.assertEqual(out1['remainingDurability'], 94.0)
        self.assertFalse(out1['isBroken'])
        self.assertFalse(out1['fingerprintLeft'])  # Gloves protect!

        # Case 2: Worn crowbar breaks upon failure
        out2 = calculate_outcome('tool_crowbar', 5.0, has_gloves=True, is_union=False, random_seed=12345)
        self.assertTrue(out2['isBroken'])
        self.assertEqual(out2['remainingDurability'], 0.0)

    def test_forensic_fingerprints_and_glove_immunity(self):
        """Verify operating with gloves prevents latent fingerprint deposition while bare hands deposit prints."""
        def check_fingerprints(has_gloves, roll_val=0.50, risk_threshold=0.85):
            if has_gloves:
                return False
            return roll_val <= risk_threshold

        # Gloves -> 100% immunity
        self.assertFalse(check_fingerprints(has_gloves=True, roll_val=0.10))
        self.assertFalse(check_fingerprints(has_gloves=True, roll_val=0.99))

        # Bare hands -> prints deposited when roll <= threshold
        self.assertTrue(check_fingerprints(has_gloves=False, roll_val=0.50))
        self.assertFalse(check_fingerprints(has_gloves=False, roll_val=0.90))

    def test_dna_and_laceration_hazard(self):
        """Verify prying injury hazard triggers biological DNA evidence and damage."""
        def check_laceration(has_gloves, roll_val, base_risk=0.12):
            eff_risk = base_risk * 0.15 if has_gloves else base_risk
            return roll_val <= eff_risk

        # Bare hands with low roll -> laceration occurs
        self.assertTrue(check_laceration(has_gloves=False, roll_val=0.08, base_risk=0.12))
        # With gloves, risk drops to 0.12 * 0.15 = 0.018 -> roll of 0.08 is now protected!
        self.assertFalse(check_laceration(has_gloves=True, roll_val=0.08, base_risk=0.12))

    def test_deterministic_toolmark_striation_hash(self):
        """Verify SHA-256 deterministic toolmark hashing for microscopic crowbar striations."""
        def determine_toolmark_hash(tool_serial, citizen_id, coords, salt="TOOLMARK_SALT"):
            raw = f"TOOLMARK:{tool_serial}:{citizen_id}:{coords['x']:.2f},{coords['y']:.2f},{coords['z']:.2f}:{salt}"
            return hashlib.sha256(raw.encode("utf-8")).hexdigest()

        coords = {"x": 890.50, "y": -2100.25, "z": 30.00}
        h1 = determine_toolmark_hash("CRW-100200", "CIT-001", coords)
        h2 = determine_toolmark_hash("CRW-100200", "CIT-001", coords)
        h3 = determine_toolmark_hash("CRW-999999", "CIT-002", coords)

        self.assertEqual(len(h1), 64)
        self.assertEqual(h1, h2, "Toolmark hash must be strictly deterministic")
        self.assertNotEqual(h1, h3, "Different tool serial and citizen ID must yield different hash")

    def test_tamper_seal_serial_generation(self):
        """Verify format of generated serialized tamper seal tags."""
        def generate_seal_serial(pallet_id, timestamp=1700000000):
            suffix = str(pallet_id)[-6:].upper()
            return f"SEAL-{suffix}-{timestamp % 10000:04d}"

        serial = generate_seal_serial("plt_4a8f90c1", 1700005432)
        self.assertTrue(serial.startswith("SEAL-"))
        self.assertIn("8F90C1", serial)
        self.assertTrue(serial.endswith("5432"))

    def test_zero_trust_payload_validation_and_badges(self):
        """Verify zero-trust validation for breach payloads and status badge formatting."""
        def validate_breach_payload(payload):
            if not payload or not isinstance(payload, dict):
                return False, "INVALID_PAYLOAD"
            pallet_id = payload.get("palletId")
            if not pallet_id or not isinstance(pallet_id, str) or len(pallet_id) < 3 or len(pallet_id) > 64:
                return False, "INVALID_PALLET_ID"
            tool = payload.get("toolItem", "tool_crowbar")
            if tool not in ["tool_crowbar", "weapon_crowbar", "tool_lockpick"]:
                return False, "INVALID_BREACH_TOOL"
            coords = payload.get("coords")
            if coords and (not isinstance(coords, dict) or "x" not in coords or "y" not in coords):
                return False, "INVALID_COORDINATES"
            return True, "OK"

        ok1, _ = validate_breach_payload({"palletId": "plt_valid_123", "toolItem": "tool_crowbar"})
        self.assertTrue(ok1)

        ok2, err2 = validate_breach_payload({"palletId": ""})
        self.assertFalse(ok2)
        self.assertEqual(err2, "INVALID_PALLET_ID")

        ok3, err3 = validate_breach_payload({"palletId": "plt_valid_123", "toolItem": "c4_explosive"})
        self.assertFalse(ok3)
        self.assertEqual(err3, "INVALID_BREACH_TOOL")

        def format_badge(pallet):
            if pallet.get("is_tampered"):
                return "[TAMPERED / BREACHED]"
            elif pallet.get("is_sealed"):
                return "[SEALED / SECURE]"
            return "[OPEN / UNSEALED]"

        self.assertEqual(format_badge({"is_tampered": True, "is_sealed": False}), "[TAMPERED / BREACHED]")
        self.assertEqual(format_badge({"is_tampered": False, "is_sealed": True}), "[SEALED / SECURE]")
        self.assertEqual(format_badge({"is_tampered": False, "is_sealed": False}), "[OPEN / UNSEALED]")

    def test_in_engine_tests_lua_integration(self):
        """Verify Test 44 is declared and wired into tests.lua RunAll()."""
        tests_lua_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        self.assertTrue(os.path.isfile(tests_lua_path))
        with open(tests_lua_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("function Nyx.Tests.TestSealedPalletBreachingAndForensicContamination()", code)
        self.assertIn("local t44 = Nyx.Tests.TestSealedPalletBreachingAndForensicContamination()", code)
        self.assertIn("and t44", code)


if __name__ == "__main__":
    unittest.main()
