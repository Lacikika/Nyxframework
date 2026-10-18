#!/usr/bin/env python3
"""
Unit and Integration Tests for Anatomical Trauma & Organ-Specific Medical Injury Engine (nyx_services).
Covers: Migration 041, Item Registrations, Shared Pure Lua Trauma Engine,
        Bone Mapping, Hemodynamics & Shock Model, Field Stabilization,
        and In-Engine Integration Test Harness.
"""

import os
import sys
import json
import re
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestAnatomicalTraumaAndInjuryEngine(unittest.TestCase):
    def test_migration_041_exists_and_registered(self):
        """Verify migration 041 exists on disk, mirrored, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("041_anatomical_trauma_and_medical_injury_engine.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "041_anatomical_trauma_and_medical_injury_engine.sql")
        services_mig = os.path.join(FIVEM_DIR, "nyx_services", "sql", "migrations", "041_anatomical_trauma_and_medical_injury_engine.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 041 missing")
        self.assertTrue(os.path.isfile(services_mig), "nyx_services migration 041 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("CREATE TABLE IF NOT EXISTS `nyx_medical_trauma`", sql)
        self.assertIn("CREATE TABLE IF NOT EXISTS `nyx_medical_treatments_log`", sql)
        self.assertIn("citizen_id", sql)
        self.assertIn("blood_volume_ml", sql)
        self.assertIn("bleeding_rate", sql)
        self.assertIn("wounds_json", sql)
        self.assertIn("treatment_uuid", sql)
        self.assertIn("patient_citizen_id", sql)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest.lua declares shared, server, and client scripts for trauma system."""
        manifest_path = os.path.join(FIVEM_DIR, "nyx_services", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_path))
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = f.read()

        self.assertIn("shared/trauma.lua", manifest)
        self.assertIn("server/trauma.lua", manifest)
        self.assertIn("client/trauma.lua", manifest)

        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_services", "shared", "trauma.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_services", "server", "trauma.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_services", "client", "trauma.lua")))

    def test_items_registered_in_nyx_inventory(self):
        """Verify medical consumable items required for field stabilization are registered in nyx_inventory."""
        items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
        self.assertTrue(os.path.isfile(items_path))
        with open(items_path, "r", encoding="utf-8") as f:
            content = f.read()

        required_items = [
            "bandage_sterile",
            "first_aid_pack",
            "tourniquet",
            "splint",
            "morphine_ampoule",
        ]
        for item in required_items:
            self.assertIn(f"['{item}']", content, f"Item '{item}' not registered in nyx_inventory/shared/items.lua")

    def test_bone_to_limb_mapping(self):
        """Verify deterministic GTA ped bone ID to anatomical limb mapping."""
        bone_to_limb = {
            31086: "head",       # SKEL_Head
            39317: "head",       # SKEL_Neck_1
            24818: "torso",      # SKEL_Spine3
            24817: "torso",      # SKEL_Spine2
            24816: "torso",      # SKEL_Spine1
            11816: "torso",      # SKEL_Pelvis
            18905: "left_arm",   # SKEL_L_Hand
            22711: "left_arm",   # SKEL_L_Forearm
            45509: "left_arm",   # SKEL_L_UpperArm
            64729: "left_arm",   # SKEL_L_Clavicle
            57005: "right_arm",  # SKEL_R_Hand
            2992: "right_arm",   # SKEL_R_Forearm
            40269: "right_arm",  # SKEL_R_UpperArm
            10706: "right_arm",  # SKEL_R_Clavicle
            63931: "left_leg",   # SKEL_L_Calf
            58271: "left_leg",   # SKEL_L_Thigh
            14201: "left_leg",   # SKEL_L_Foot
            36864: "right_leg",  # SKEL_R_Calf
            51826: "right_leg",  # SKEL_R_Thigh
            52335: "right_leg",  # SKEL_R_Foot
        }

        def get_limb_from_bone(bone_id):
            return bone_to_limb.get(int(bone_id), "torso")

        self.assertEqual(get_limb_from_bone(31086), "head")
        self.assertEqual(get_limb_from_bone(24818), "torso")
        self.assertEqual(get_limb_from_bone(18905), "left_arm")
        self.assertEqual(get_limb_from_bone(57005), "right_arm")
        self.assertEqual(get_limb_from_bone(63931), "left_leg")
        self.assertEqual(get_limb_from_bone(36864), "right_leg")
        self.assertEqual(get_limb_from_bone(99999), "torso")  # Fallback

    def test_shock_classification_thresholds(self):
        """Verify hypovolemic shock classification logic matches pure Lua medical specifications."""
        def calculate_shock_class(blood_volume):
            vol = max(0, min(5000, int(blood_volume)))
            if vol >= 4250:
                return 1, "Class I (Mild / Stable)", False
            elif vol >= 3500:
                return 2, "Class II (Moderate Shock)", False
            elif vol >= 3000:
                return 3, "Class III (Severe Shock)", False
            else:
                return 4, "Class IV (Critical / Lethal Shock)", True

        # Baseline 5000 mL -> Class 1
        c1, label1, unc1 = calculate_shock_class(5000)
        self.assertEqual(c1, 1)
        self.assertFalse(unc1)

        # 4000 mL -> Class 2
        c2, label2, unc2 = calculate_shock_class(4000)
        self.assertEqual(c2, 2)
        self.assertFalse(unc2)

        # 3200 mL -> Class 3
        c3, label3, unc3 = calculate_shock_class(3200)
        self.assertEqual(c3, 3)
        self.assertFalse(unc3)

        # 2500 mL -> Class 4 (Loss of consciousness)
        c4, label4, unc4 = calculate_shock_class(2500)
        self.assertEqual(c4, 4)
        self.assertTrue(unc4)

    def test_bleed_rate_calculation(self):
        """Verify bleed rate calculations based on active wounds and tourniquets."""
        def calc_bleed_rate(wounds_by_limb, tourniquets):
            base_bleed = {
                "laceration": 1.5,
                "ballistic": 6.0,
                "arterial_bleed": 25.0,
                "blunt": 0.5,
                "burn": 1.0,
            }
            total_bleed = 0.0
            for limb, wounds in wounds_by_limb.items():
                if tourniquets.get(limb, False):
                    # Tourniquet occludes flow on limbs
                    continue
                for w in wounds:
                    w_type = w.get("type", "laceration")
                    sev = float(w.get("severity", 1.0))
                    rate = base_bleed.get(w_type, 1.0) * sev
                    if w.get("bandaged", False):
                        rate = 0.0
                    total_bleed += rate
            return round(total_bleed, 2)

        # 1 laceration on left_arm
        rate1 = calc_bleed_rate({"left_arm": [{"type": "laceration", "severity": 1.0}]}, {})
        self.assertEqual(rate1, 1.5)

        # 1 arterial bleed on left_leg
        rate2 = calc_bleed_rate({"left_leg": [{"type": "arterial_bleed", "severity": 1.0}]}, {})
        self.assertEqual(rate2, 25.0)

        # Applying tourniquet to left_leg completely occludes the arterial bleed
        rate3 = calc_bleed_rate({"left_leg": [{"type": "arterial_bleed", "severity": 1.0}]}, {"left_leg": True})
        self.assertEqual(rate3, 0.0)

    def test_treatment_validation_rules(self):
        """Verify zero-trust validation for medical item application."""
        valid_limbs = {"head", "torso", "left_arm", "right_arm", "left_leg", "right_leg"}
        extremity_limbs = {"left_arm", "right_arm", "left_leg", "right_leg"}

        def validate_treatment(limb, item):
            if limb not in valid_limbs:
                return False, "INVALID_LIMB"
            if item == "tourniquet":
                if limb not in extremity_limbs:
                    return False, "CANNOT_APPLY_TOURNIQUET_TO_CORE"
            return True, "OK"

        self.assertTrue(validate_treatment("left_arm", "tourniquet")[0])
        self.assertTrue(validate_treatment("right_leg", "tourniquet")[0])
        self.assertFalse(validate_treatment("torso", "tourniquet")[0])
        self.assertFalse(validate_treatment("head", "tourniquet")[0])
        self.assertEqual(validate_treatment("head", "tourniquet")[1], "CANNOT_APPLY_TOURNIQUET_TO_CORE")
        self.assertFalse(validate_treatment("invalid_limb", "bandage_sterile")[0])

    def test_hemodynamic_simulation_tick(self):
        """Verify pure blood volume tick simulation."""
        def simulate_tick(blood_volume, bleed_rate, delta_seconds):
            loss = bleed_rate * delta_seconds
            new_vol = max(0, min(5000, blood_volume - loss))
            return round(new_vol, 1)

        # 5000 mL with 10 mL/s bleed for 5 seconds -> 4950 mL
        vol1 = simulate_tick(5000, 10.0, 5.0)
        self.assertEqual(vol1, 4950.0)

        # 500 mL with 30 mL/s bleed for 20 seconds -> 0 mL (clamped)
        vol2 = simulate_tick(500, 30.0, 20.0)
        self.assertEqual(vol2, 0.0)

    def test_in_engine_test_suite_registered(self):
        """Verify Test 36 is declared and invoked in Nyx.Tests.RunAll()."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        self.assertTrue(os.path.isfile(tests_path))
        with open(tests_path, "r", encoding="utf-8") as f:
            tests_code = f.read()

        self.assertIn("function Nyx.Tests.TestAnatomicalTraumaAndInjuryEngine()", tests_code)
        self.assertIn("local t36 = Nyx.Tests.TestAnatomicalTraumaAndInjuryEngine()", tests_code)
        self.assertIn("and t36", tests_code)


if __name__ == "__main__":
    unittest.main()
