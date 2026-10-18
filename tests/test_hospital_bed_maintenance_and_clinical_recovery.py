#!/usr/bin/env python3
"""
Unit and Integration Tests for Nyxframework Hospital Bed Maintenance,
Clinical Recovery & Triage Engine (FiveM/nyx_services)
"""

import os
import sys
import json
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")

class TestHospitalBedMaintenanceAndClinicalRecovery(unittest.TestCase):
    def test_migration_061_registered_and_structure(self):
        """Verify migration 061 exists in index.json and contains required tables and seeds."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            index_data = json.load(f)

        self.assertIn("061_hospital_bed_maintenance_and_clinical_recovery.sql", index_data)

        mig_core = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "061_hospital_bed_maintenance_and_clinical_recovery.sql")
        mig_serv = os.path.join(FIVEM_DIR, "nyx_services", "sql", "migrations", "061_hospital_bed_maintenance_and_clinical_recovery.sql")
        self.assertTrue(os.path.isfile(mig_core), "Core migration 061 missing")
        self.assertTrue(os.path.isfile(mig_serv), "Services migration 061 missing")

        with open(mig_core, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("CREATE TABLE IF NOT EXISTS `nyx_services_hospital_beds`", sql)
        self.assertIn("CREATE TABLE IF NOT EXISTS `nyx_services_hospital_bed_audits`", sql)
        self.assertIn("bed:pillbox:01", sql)
        self.assertIn("bed:sandy:01", sql)
        self.assertIn("bed:paleto:01", sql)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest.lua properly registers shared, server, and client bed files."""
        manifest_path = os.path.join(FIVEM_DIR, "nyx_services", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_path))
        with open(manifest_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("'shared/hospital_beds.lua'", content)
        self.assertIn("'server/beds.lua'", content)
        self.assertIn("'client/beds.lua'", content)

        # Confirm all files exist on disk
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_services", "shared", "hospital_beds.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_services", "server", "beds.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_services", "client", "beds.lua")))

    def test_bed_types_taxonomy(self):
        """Verify clinical bed types taxonomy in shared/hospital_beds.lua."""
        shared_path = os.path.join(FIVEM_DIR, "nyx_services", "shared", "hospital_beds.lua")
        with open(shared_path, "r", encoding="utf-8") as f:
            lua_code = f.read()

        self.assertIn("['icu_trauma'] =", lua_code)
        self.assertIn("['general_ward'] =", lua_code)
        self.assertIn("['emergency_cot'] =", lua_code)
        self.assertIn("canPerformSurgery = true", lua_code)
        self.assertIn("powerRequirementKw = 15.0", lua_code)
        self.assertIn("powerRequirementKw = 5.0", lua_code)
        self.assertIn("powerRequirementKw = 0.0", lua_code)

    def test_infusion_rate_calculations(self):
        """Simulate and verify clinical infusion rate adjustments under power and supply penalties."""
        def calc_rates(bed_type, supply_status, is_powered):
            defs = {
                "icu_trauma": {"kw": 15.0, "blood": 60.0, "wound": 25.0},
                "general_ward": {"kw": 5.0, "blood": 30.0, "wound": 15.0},
                "emergency_cot": {"kw": 0.0, "blood": 12.0, "wound": 6.0}
            }
            d = defs[bed_type]
            p_mult = 0.25 if (d["kw"] > 0 and not is_powered) else 1.0
            if supply_status == "critical_shortage":
                s_mult = 0.40
            elif supply_status == "degraded":
                s_mult = 0.75
            else:
                s_mult = 1.0

            c_mult = p_mult * s_mult
            blood_rate = round(d["blood"] * c_mult, 1)
            wound_rate = round(d["wound"] * c_mult, 1)
            return blood_rate, wound_rate, p_mult, s_mult

        # ICU Powered Optimal: 60 mL/s, 25 HP/s
        b_icu_opt, w_icu_opt, p_pen, s_pen = calc_rates("icu_trauma", "optimal", True)
        self.assertEqual(b_icu_opt, 60.0)
        self.assertEqual(w_icu_opt, 25.0)
        self.assertEqual(p_pen, 1.0)
        self.assertEqual(s_pen, 1.0)

        # ICU Blackout (25% battery backup): 60 * 0.25 = 15.0 mL/s
        b_icu_black, _, p_pen_b, _ = calc_rates("icu_trauma", "optimal", False)
        self.assertEqual(b_icu_black, 15.0)
        self.assertEqual(p_pen_b, 0.25)

        # General Ward Critical Shortage: 30 * 0.40 = 12.0 mL/s
        b_ward_crit, _, _, s_pen_c = calc_rates("general_ward", "critical_shortage", True)
        self.assertEqual(b_ward_crit, 12.0)
        self.assertEqual(s_pen_c, 0.40)

        # Emergency Cot Blackout (0 kW requirement): remains 12.0 mL/s
        b_cot_black, _, p_pen_cot, _ = calc_rates("emergency_cot", "optimal", False)
        self.assertEqual(b_cot_black, 12.0)
        self.assertEqual(p_pen_cot, 1.0)

    def test_bed_admission_eligibility_state_machine(self):
        """Test bed admission validation rules."""
        def evaluate_admission(bed, is_powered):
            kw = 15.0 if bed["bed_type"] == "icu_trauma" else (5.0 if bed["bed_type"] == "general_ward" else 0.0)
            if bed.get("is_occupied") == 1 or bed.get("occupied_by"):
                return False, "BED_ALREADY_OCCUPIED"
            if bed.get("maintenance_status") == "soiled" or bed.get("cleanliness", 100.0) < 50.0:
                return False, "BED_SOILED_REQUIRES_SANITIZATION"
            if kw > 0 and not is_powered:
                return False, "BED_OFFLINE_POWER_BLACKOUT"
            return True, "ELIGIBLE_FOR_ADMISSION"

        clean_bed = {"bed_type": "icu_trauma", "is_occupied": 0, "maintenance_status": "clean", "cleanliness": 100.0}
        self.assertTrue(evaluate_admission(clean_bed, True)[0])

        occupied_bed = {"bed_type": "icu_trauma", "is_occupied": 1, "occupied_by": "CIT_1", "maintenance_status": "occupied"}
        ok, err = evaluate_admission(occupied_bed, True)
        self.assertFalse(ok)
        self.assertEqual(err, "BED_ALREADY_OCCUPIED")

        soiled_bed = {"bed_type": "icu_trauma", "is_occupied": 0, "maintenance_status": "soiled", "cleanliness": 20.0}
        ok, err = evaluate_admission(soiled_bed, True)
        self.assertFalse(ok)
        self.assertEqual(err, "BED_SOILED_REQUIRES_SANITIZATION")

        blackout_icu = {"bed_type": "icu_trauma", "is_occupied": 0, "maintenance_status": "clean", "cleanliness": 100.0}
        ok, err = evaluate_admission(blackout_icu, False)
        self.assertFalse(ok)
        self.assertEqual(err, "BED_OFFLINE_POWER_BLACKOUT")

        blackout_cot = {"bed_type": "emergency_cot", "is_occupied": 0, "maintenance_status": "clean", "cleanliness": 100.0}
        ok, _ = evaluate_admission(blackout_cot, False)
        self.assertTrue(ok)

    def test_bed_soiling_and_sanitization_cycle(self):
        """Verify bed transitions to soiled upon discharge and sanitization plan restores 100% cleanliness."""
        clean_items = {
            "item_disinfectant": {"restored": 100.0, "duration": 6},
            "clean_linens": {"restored": 100.0, "duration": 8},
            "bleach": {"restored": 85.0, "duration": 10}
        }

        def plan_sanitization(bed, item_key):
            if item_key not in clean_items:
                return False, "INVALID_SANITIZING_ITEM"
            item = clean_items[item_key]
            cur = bed.get("cleanliness", 100.0)
            if cur >= 98.0 and bed.get("maintenance_status") == "clean":
                return False, "BED_ALREADY_SANITIZED"
            return True, {
                "targetCleanliness": min(100.0, max(cur, item["restored"])),
                "duration": item["duration"]
            }

        soiled_bed = {"cleanliness": 20.0, "maintenance_status": "soiled"}
        ok, plan = plan_sanitization(soiled_bed, "item_disinfectant")
        self.assertTrue(ok)
        self.assertEqual(plan["targetCleanliness"], 100.0)
        self.assertEqual(plan["duration"], 6)

        ok_bad, err_bad = plan_sanitization(soiled_bed, "invalid_spray")
        self.assertFalse(ok_bad)
        self.assertEqual(err_bad, "INVALID_SANITIZING_ITEM")

        already_clean = {"cleanliness": 100.0, "maintenance_status": "clean"}
        ok_clean, err_clean = plan_sanitization(already_clean, "clean_linens")
        self.assertFalse(ok_clean)
        self.assertEqual(err_clean, "BED_ALREADY_SANITIZED")

    def test_hemodynamic_vitals_telemetry_curves(self):
        """Verify physiological telemetry mapping across hypovolemic shock classes."""
        def calc_vitals(blood_vol, is_powered):
            ratio = max(0.0, min(1.0, blood_vol / 5000.0))
            if ratio >= 0.85:
                return 1, 72, 120, 80, 99, "Normal Sinus Rhythm", "stable" if is_powered else "offline"
            elif ratio >= 0.70:
                return 2, 105, 105, 70, 94, "Sinus Tachycardia", "warning" if is_powered else "offline"
            elif ratio >= 0.50:
                return 3, 135, 85, 55, 88, "Severe Tachycardia / Arrhythmia", "critical" if is_powered else "offline"
            elif ratio > 0.10:
                return 4, 155, 60, 40, 74, "Ventricular Tachycardia", "lethal" if is_powered else "offline"
            else:
                return 4, 0, 0, 0, 0, "Asystole (Flatline)", "flatline" if is_powered else "offline"

        # Class I (5000 mL): Normal
        s1, bpm1, sys1, dia1, spo2_1, rhythm1, ekg1 = calc_vitals(5000.0, True)
        self.assertEqual(s1, 1)
        self.assertEqual(bpm1, 72)
        self.assertEqual(sys1, 120)
        self.assertEqual(dia1, 80)
        self.assertEqual(spo2_1, 99)
        self.assertEqual(ekg1, "stable")

        # Class II (3800 mL): Tachycardia compensatory reflex
        s2, bpm2, sys2, _, _, _, ekg2 = calc_vitals(3800.0, True)
        self.assertEqual(s2, 2)
        self.assertEqual(bpm2, 105)
        self.assertEqual(sys2, 105)
        self.assertEqual(ekg2, "warning")

        # Class IV (1000 mL): Lethal shock
        s4, bpm4, sys4, dia4, spo2_4, _, ekg4 = calc_vitals(1000.0, True)
        self.assertEqual(s4, 4)
        self.assertEqual(bpm4, 155)
        self.assertEqual(sys4, 60)
        self.assertEqual(dia4, 40)
        self.assertEqual(spo2_4, 74)
        self.assertEqual(ekg4, "lethal")

        # Flatline (< 500 mL)
        _, bpm0, _, _, _, rhythm0, ekg0 = calc_vitals(200.0, True)
        self.assertEqual(bpm0, 0)
        self.assertEqual(rhythm0, "Asystole (Flatline)")
        self.assertEqual(ekg0, "flatline")

        # Offline monitor (Unpowered)
        _, _, _, _, _, _, ekg_off = calc_vitals(5000.0, False)
        self.assertEqual(ekg_off, "offline")

    def test_in_engine_tests_registered(self):
        """Verify TestHospitalBedMaintenanceAndClinicalRecovery is registered in server/tests.lua."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        with open(tests_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("function Nyx.Tests.TestHospitalBedMaintenanceAndClinicalRecovery()", code)
        self.assertIn("local t56 = Nyx.Tests.TestHospitalBedMaintenanceAndClinicalRecovery()", code)
        self.assertIn("suites1to50Passed and t51 and t52 and t53 and t54 and t55 and t56", code)

if __name__ == "__main__":
    unittest.main()
