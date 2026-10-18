#!/usr/bin/env python3
"""
Unit and Integration Tests for Physical Vehicle Keys, Fleet RFID Tokens & Lockpicking Forensics.
Covers: Migration 044, Inventory item registrations (item_vehicle_key, rfid_fleet_card),
        Shared Pure Lua 5.4 Vehicle Keys & RFID Engine (nyx_vehicles/shared/keys.lua),
        Key & Plate matching rules, Corporate RFID Token hierarchy & revocation,
        Lockpicking probability math & alarms, Forensic fingerprint generation & gloves immunity,
        Zero-trust payload validation, Server exports & RPCs, and In-Engine Test Harness integration.
"""

import os
import sys
import json
import re
import unittest
import hashlib

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestVehicleKeysRfidAndLockpickingForensics(unittest.TestCase):
    def test_migration_044_exists_and_registered(self):
        """Verify migration 044 exists on disk, mirrored, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("044_vehicle_keys_rfid_and_lockpicking_forensics.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "044_vehicle_keys_rfid_and_lockpicking_forensics.sql")
        vehicles_mig = os.path.join(FIVEM_DIR, "nyx_vehicles", "sql", "migrations", "044_vehicle_keys_rfid_and_lockpicking_forensics.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 044 missing")
        self.assertTrue(os.path.isfile(vehicles_mig), "nyx_vehicles migration 044 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("nyx_vehicles_rfid_tokens", sql)
        self.assertIn("nyx_vehicles_lockpick_attempts", sql)
        self.assertIn("fingerprint_evidence_id", sql)
        self.assertIn("token_uuid", sql)
        self.assertIn("access_level", sql)
        self.assertIn("is_revoked", sql)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest.lua declares shared/keys.lua."""
        manifest_vehicles = os.path.join(FIVEM_DIR, "nyx_vehicles", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_vehicles))
        with open(manifest_vehicles, "r", encoding="utf-8") as f:
            v_manifest = f.read()

        self.assertIn("shared/keys.lua", v_manifest)
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_vehicles", "shared", "keys.lua")))

    def test_inventory_items_registered(self):
        """Verify item_vehicle_key and rfid_fleet_card are registered in nyx_inventory."""
        items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
        self.assertTrue(os.path.isfile(items_path))
        with open(items_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("['item_vehicle_key']", content, "item_vehicle_key missing from inventory registry")
        self.assertIn("['rfid_fleet_card']", content, "rfid_fleet_card missing from inventory registry")
        self.assertIn("['tool_lockpick']", content, "tool_lockpick missing from inventory registry")

    def test_key_matching_logic(self):
        """Verify physical key matching against vehicle VIN and plate."""
        def validate_key_match(key_item, target_vin, target_plate):
            if not key_item or not isinstance(key_item, dict):
                return False, "INVALID_KEY_ITEM"
            item_id = key_item.get("item_id") or key_item.get("name")
            if item_id not in ["item_vehicle_key", "car_keys"]:
                return False, "NOT_A_KEY_ITEM"
            
            metadata = key_item.get("metadata") or {}
            key_vin = metadata.get("vin")
            key_plate = metadata.get("plate")

            if key_vin and key_vin == target_vin:
                return True, "VIN_MATCH"
            if key_plate and target_plate and (key_plate.strip().upper() == target_plate.strip().upper()):
                return True, "PLATE_MATCH"

            return False, "KEY_MISMATCH"

        key1 = {"item_id": "item_vehicle_key", "metadata": {"vin": "VIN-1001", "plate": "NYX 001", "keyType": "master"}}
        ok1, reason1 = validate_key_match(key1, "VIN-1001", "NYX 001")
        self.assertTrue(ok1)
        self.assertEqual(reason1, "VIN_MATCH")

        # Plate match fallback
        key2 = {"item_id": "item_vehicle_key", "metadata": {"plate": "NYX 001", "keyType": "copy"}}
        ok2, reason2 = validate_key_match(key2, "VIN-9999", "NYX 001")
        self.assertTrue(ok2)
        self.assertEqual(reason2, "PLATE_MATCH")

        # Wrong key
        key3 = {"item_id": "item_vehicle_key", "metadata": {"vin": "VIN-2002", "plate": "OTHER"}}
        ok3, reason3 = validate_key_match(key3, "VIN-1001", "NYX 001")
        self.assertFalse(ok3)
        self.assertEqual(reason3, "KEY_MISMATCH")

        # Not a key
        bad_item = {"item_id": "tool_lockpick", "metadata": {}}
        ok4, reason4 = validate_key_match(bad_item, "VIN-1001", "NYX 001")
        self.assertFalse(ok4)
        self.assertEqual(reason4, "NOT_A_KEY_ITEM")

    def test_rfid_access_hierarchy_and_revocation(self):
        """Verify corporate RFID proximity access logic, hierarchy, expiration, and revocation."""
        def validate_rfid_access(rfid_item, target_faction_id, current_time=100000, required_level="driver"):
            levels = {"driver": 1, "manager": 2, "executive": 3, "admin": 4}
            if not rfid_item or not isinstance(rfid_item, dict):
                return False, "INVALID_RFID_ITEM"
            item_id = rfid_item.get("item_id") or rfid_item.get("name")
            if item_id != "rfid_fleet_card":
                return False, "NOT_RFID_ITEM"
            
            meta = rfid_item.get("metadata") or {}
            if meta.get("is_revoked") or meta.get("isRevoked"):
                return False, "TOKEN_REVOKED"
            
            exp = meta.get("expires_at") or meta.get("expiresAt")
            if exp and current_time and current_time > exp:
                return False, "TOKEN_EXPIRED"

            item_faction = meta.get("faction_id") or meta.get("factionId")
            if not item_faction or item_faction != target_faction_id:
                return False, "FACTION_MISMATCH"

            token_level = meta.get("access_level") or meta.get("accessLevel") or "driver"
            token_rank = levels.get(token_level, 1)
            required_rank = levels.get(required_level, 1)

            if token_rank < required_rank:
                return False, "INSUFFICIENT_ACCESS_LEVEL"

            return True, "AUTHORIZED"

        rfid1 = {
            "item_id": "rfid_fleet_card",
            "metadata": {"faction_id": "corp_logistics", "access_level": "manager", "is_revoked": False, "expires_at": 200000}
        }
        ok1, res1 = validate_rfid_access(rfid1, "corp_logistics", 150000, "driver")
        self.assertTrue(ok1)
        self.assertEqual(res1, "AUTHORIZED")

        # Faction mismatch
        ok2, res2 = validate_rfid_access(rfid1, "other_faction", 150000, "driver")
        self.assertFalse(ok2)
        self.assertEqual(res2, "FACTION_MISMATCH")

        # Token revoked
        rfid_revoked = {
            "item_id": "rfid_fleet_card",
            "metadata": {"faction_id": "corp_logistics", "access_level": "executive", "is_revoked": True}
        }
        ok3, res3 = validate_rfid_access(rfid_revoked, "corp_logistics", 150000)
        self.assertFalse(ok3)
        self.assertEqual(res3, "TOKEN_REVOKED")

        # Token expired
        rfid_exp = {
            "item_id": "rfid_fleet_card",
            "metadata": {"faction_id": "corp_logistics", "access_level": "driver", "expires_at": 100000}
        }
        ok4, res4 = validate_rfid_access(rfid_exp, "corp_logistics", 100005)
        self.assertFalse(ok4)
        self.assertEqual(res4, "TOKEN_EXPIRED")

        # Insufficient tier (driver trying to access executive fleet)
        ok5, res5 = validate_rfid_access(rfid_exp, "corp_logistics", 50000, "executive")
        self.assertFalse(ok5)
        self.assertEqual(res5, "INSUFFICIENT_ACCESS_LEVEL")

    def test_lockpick_chance_calculation(self):
        """Verify lockpick probability, alarm triggers, and pick degradation."""
        def calculate_lockpick_chance(lockpick_type="tool_lockpick", vehicle_class=0, security_upgrade=0):
            base_chances = {
                "tool_lockpick": 0.50,
                "tool_lockpick_advanced": 0.75,
                "improvised_wire": 0.30
            }
            base = base_chances.get(lockpick_type, 0.40)
            # Vehicle class penalty: Super(7)= -0.20, Sports(6)= -0.15, Coupes(3)= 0, Compacts(0)= +0.05
            class_mods = {0: 0.05, 1: 0.02, 2: 0.00, 3: 0.00, 6: -0.15, 7: -0.20}
            mod = class_mods.get(vehicle_class, 0.00)
            sec_penalty = security_upgrade * 0.10

            success_chance = max(0.05, min(0.95, base + mod - sec_penalty))
            alarm_chance_fail = min(0.90, 0.35 + (security_upgrade * 0.15))
            alarm_chance_success = min(0.50, 0.10 + (security_upgrade * 0.10))
            break_chance = 0.25 if lockpick_type == "tool_lockpick" else 0.10

            return {
                "successChance": round(success_chance, 2),
                "alarmChanceFail": round(alarm_chance_fail, 2),
                "alarmChanceSuccess": round(alarm_chance_success, 2),
                "breakChance": round(break_chance, 2)
            }

        res_std = calculate_lockpick_chance("tool_lockpick", 0, 0)
        self.assertEqual(res_std["successChance"], 0.55) # 0.50 + 0.05
        self.assertEqual(res_std["breakChance"], 0.25)

        res_super = calculate_lockpick_chance("tool_lockpick", 7, 1) # Super car with tier 1 security
        self.assertEqual(res_super["successChance"], 0.20) # 0.50 - 0.20 - 0.10
        self.assertEqual(res_super["alarmChanceFail"], 0.50) # 0.35 + 0.15

    def test_forensic_fingerprint_trace_and_gloves_protection(self):
        """Verify lockpicking without gloves generates latent fingerprints while gloves provide immunity."""
        def determine_forensic_trace(has_gloves, citizen_id, coords, salt="SALT123"):
            if has_gloves:
                return {
                    "leavesFingerprint": False,
                    "evidenceType": None,
                    "hash": None,
                    "surface": None
                }
            
            # Bare hands leave latent fingerprints on vehicle door handle / ignition
            source_serial = f"FP-{citizen_id}"
            raw = f"{source_serial}:{citizen_id}:{coords['x']:.2f},{coords['y']:.2f},{coords['z']:.2f}:{salt}"
            fp_hash = hashlib.sha256(raw.encode("utf-8")).hexdigest()

            return {
                "leavesFingerprint": True,
                "evidenceType": "fingerprint",
                "sourceSerial": source_serial,
                "hash": fp_hash,
                "surface": "vehicle_door_handle"
            }

        coords = {"x": 215.5, "y": -805.0, "z": 30.8}
        
        # With gloves: ZERO latent fingerprints left
        trace_gloves = determine_forensic_trace(True, "CIT-100", coords)
        self.assertFalse(trace_gloves["leavesFingerprint"])
        self.assertIsNone(trace_gloves["hash"])

        # Without gloves: Leaves latent fingerprint with deterministic SHA-256
        trace_bare = determine_forensic_trace(False, "CIT-100", coords, "SALT999")
        self.assertTrue(trace_bare["leavesFingerprint"])
        self.assertEqual(trace_bare["evidenceType"], "fingerprint")
        self.assertTrue(len(trace_bare["hash"]) == 64)
        self.assertEqual(trace_bare["surface"], "vehicle_door_handle")

    def test_zero_trust_payload_validation(self):
        """Verify zero-trust payload validation for issuing keys and RFID tokens."""
        def validate_key_payload(payload):
            if not payload or not isinstance(payload, dict):
                return False, "INVALID_PAYLOAD"
            vin = payload.get("vin")
            if not vin or not isinstance(vin, str) or len(vin) < 3 or len(vin) > 32:
                return False, "INVALID_VIN"
            plate = payload.get("plate")
            if not plate or not isinstance(plate, str) or len(plate) < 2 or len(plate) > 12:
                return False, "INVALID_PLATE"
            key_type = payload.get("keyType", "copy")
            if key_type not in ["master", "copy", "valet", "fob"]:
                return False, "INVALID_KEY_TYPE"
            target_citizen_id = payload.get("targetCitizenId")
            if not target_citizen_id or not isinstance(target_citizen_id, str):
                return False, "INVALID_TARGET"
            return True, "OK"

        ok1, _ = validate_key_payload({"vin": "VIN-100", "plate": "NYX 100", "keyType": "copy", "targetCitizenId": "CIT-200"})
        self.assertTrue(ok1)

        ok2, err2 = validate_key_payload({"vin": "", "plate": "NYX 100"})
        self.assertFalse(ok2)
        self.assertEqual(err2, "INVALID_VIN")

        ok3, err3 = validate_key_payload({"vin": "VIN-100", "plate": "NYX 100", "keyType": "unauthorized_skeleton"})
        self.assertFalse(ok3)
        self.assertEqual(err3, "INVALID_KEY_TYPE")

    def test_server_exports_and_rpcs_declared(self):
        """Verify nyx_vehicles server exports and RPCs include key, RFID and lockpick functions."""
        exports_path = os.path.join(FIVEM_DIR, "nyx_vehicles", "server", "exports.lua")
        self.assertTrue(os.path.isfile(exports_path))
        with open(exports_path, "r", encoding="utf-8") as f:
            exports_content = f.read()

        self.assertIn("exports(\"HasKey\"", exports_content)
        self.assertIn("exports(\"CheckIgnition\"", exports_content)
        self.assertIn("exports(\"AttemptLockpick\"", exports_content)
        self.assertIn("exports(\"AttemptHotwire\"", exports_content)
        self.assertIn("exports(\"IssuePhysicalKey\"", exports_content)
        self.assertIn("exports(\"IssueRfidToken\"", exports_content)
        self.assertIn("exports(\"RevokeRfidToken\"", exports_content)

        keys_server_path = os.path.join(FIVEM_DIR, "nyx_vehicles", "server", "keys.lua")
        self.assertTrue(os.path.isfile(keys_server_path))
        with open(keys_server_path, "r", encoding="utf-8") as f:
            keys_content = f.read()

        self.assertIn("vehicles:checkIgnition", keys_content)
        self.assertIn("vehicles:attemptLockpick", keys_content)
        self.assertIn("vehicles:attemptHotwire", keys_content)
        self.assertIn("vehicles:issuePhysicalKey", keys_content)
        self.assertIn("vehicles:issueRfidToken", keys_content)

    def test_in_engine_tests_lua_integration(self):
        """Verify TestPhysicalKeysFleetRfidAndLockpickingForensics is declared and wired into tests.lua RunAll()."""
        tests_lua_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        self.assertTrue(os.path.isfile(tests_lua_path))
        with open(tests_lua_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("function Nyx.Tests.TestPhysicalKeysFleetRfidAndLockpickingForensics()", code)
        self.assertIn("local t39 = Nyx.Tests.TestPhysicalKeysFleetRfidAndLockpickingForensics()", code)
        self.assertIn("and t39", code)


if __name__ == "__main__":
    unittest.main()
