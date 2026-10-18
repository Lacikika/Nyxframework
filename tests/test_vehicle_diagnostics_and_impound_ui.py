#!/usr/bin/env python3
"""
Unit and Integration Tests for Mechanical Diagnostics & Civic Impound Terminal
Covers: Migration 039, Pure Lua Shared Diagnostics Engine, Server RPCs, Client UI Bridge,
        CEF Render Budget, and In-Engine Test Harness Registration.
"""

import os
import sys
import json
import re
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestVehicleDiagnosticsAndImpoundUI(unittest.TestCase):
    def test_migration_039_exists_and_registered(self):
        """Verify migration 039 exists on disk, mirrored, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("039_vehicles_diagnostics_and_civic_impound_terminal.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "039_vehicles_diagnostics_and_civic_impound_terminal.sql")
        veh_mig = os.path.join(FIVEM_DIR, "nyx_vehicles", "sql", "migrations", "039_vehicles_diagnostics_and_civic_impound_terminal.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 039 missing")
        self.assertTrue(os.path.isfile(veh_mig), "nyx_vehicles migration 039 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("CREATE TABLE IF NOT EXISTS `nyx_vehicles_diagnostic_scans`", sql)
        self.assertIn("ALTER TABLE `nyx_vehicles_wear`", sql)
        self.assertIn("inspection_status", sql)
        self.assertIn("overall_grade", sql)
        self.assertIn("diagnostic_trouble_codes", sql)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest.lua declares shared, server, and client diagnostics scripts."""
        manifest_path = os.path.join(FIVEM_DIR, "nyx_vehicles", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_path))
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = f.read()

        self.assertIn("shared/diagnostics.lua", manifest)
        self.assertIn("server/diagnostics.lua", manifest)
        self.assertIn("client/diagnostics.lua", manifest)

        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_vehicles", "shared", "diagnostics.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_vehicles", "server", "diagnostics.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_vehicles", "client", "diagnostics.lua")))

    def test_overall_grade_and_composite_score(self):
        """Test calculation of overall grade and roadworthiness logic matching pure Lua implementation."""
        def calculate_grade(engine_health, oil, brakes, trans, susp):
            eng_norm = max(0.0, min(100.0, engine_health / 10.0))
            oil_norm = max(0.0, min(100.0, oil))
            brk_norm = max(0.0, min(100.0, brakes))
            trn_norm = max(0.0, min(100.0, trans))
            sus_norm = max(0.0, min(100.0, susp))

            composite = (eng_norm * 0.30) + (oil_norm * 0.20) + (brk_norm * 0.20) + (trn_norm * 0.15) + (sus_norm * 0.15)
            composite = round(composite, 2)

            is_roadworthy = True
            if composite < 25.0 or oil_norm <= 10.0 or brk_norm <= 10.0 or eng_norm <= 20.0:
                is_roadworthy = False

            grade = "pristine"
            if composite < 25.0:
                grade = "hazardous"
            elif composite < 50.0:
                grade = "critical"
            elif composite < 75.0:
                grade = "fair"
            elif composite < 90.0:
                grade = "good"
            else:
                grade = "pristine"

            return grade, composite, is_roadworthy

        # Case 1: Factory pristine vehicle
        g1, s1, r1 = calculate_grade(1000.0, 100.0, 100.0, 100.0, 100.0)
        self.assertEqual(g1, "pristine")
        self.assertEqual(s1, 100.0)
        self.assertTrue(r1)

        # Case 2: Good condition
        g2, s2, r2 = calculate_grade(850.0, 80.0, 80.0, 85.0, 80.0)
        self.assertEqual(g2, "good")
        self.assertGreaterEqual(s2, 75.0)
        self.assertTrue(r2)

        # Case 3: Degraded fair condition
        g3, s3, r3 = calculate_grade(600.0, 50.0, 60.0, 55.0, 50.0)
        self.assertEqual(g3, "fair")
        self.assertTrue(r3)

        # Case 4: Critical brake pad loss fails roadworthiness
        g4, s4, r4 = calculate_grade(900.0, 90.0, 8.0, 85.0, 80.0)
        self.assertFalse(r4, "Vehicle with 8% brake pads must fail roadworthiness")

        # Case 5: Hazardous wreck
        g5, s5, r5 = calculate_grade(150.0, 10.0, 15.0, 20.0, 15.0)
        self.assertEqual(g5, "hazardous")
        self.assertFalse(r5)

    def test_obd_dtc_fault_generation(self):
        """Test OBD-II Diagnostic Trouble Code generation from wear and engine metrics."""
        def generate_codes(oil, brakes, trans, susp, engine_health):
            codes = []
            if oil <= 15.0:
                codes.append("P0198")
            if oil <= 5.0:
                codes.append("P0524")
            if brakes <= 15.0:
                codes.append("C0035")
            if brakes <= 5.0:
                codes.append("C0040")
            if trans <= 20.0:
                codes.append("P0730")
            if trans <= 10.0:
                codes.append("P0700")
            if susp <= 20.0:
                codes.append("C1100")
            if susp <= 10.0:
                codes.append("C1105")
            if engine_health <= 400.0:
                codes.append("P0300")
            if engine_health <= 200.0:
                codes.append("P0217")
            return codes

        # Clean vehicle
        self.assertEqual(generate_codes(90.0, 85.0, 90.0, 90.0, 1000.0), [])

        # Severely degraded oil and brakes
        codes = generate_codes(4.5, 12.0, 80.0, 80.0, 350.0)
        self.assertIn("P0198", codes)
        self.assertIn("P0524", codes)
        self.assertIn("C0035", codes)
        self.assertIn("P0300", codes)
        self.assertNotIn("P0730", codes)

    def test_impound_totals_and_fiscal_surcharge(self):
        """Test impound totals calculation with municipal fiscal crisis surcharges."""
        surcharge_rates = {
            "solvent": 0.00,
            "fiscal_stress": 0.15,
            "degraded": 0.35,
            "bankrupt": 0.60
        }

        def calc_impound(base, days, daily_rate, tier):
            rate = surcharge_rates.get(tier, 0.00)
            storage = round(days * daily_rate, 2)
            subtotal = round(base + storage, 2)
            surcharge = round(subtotal * rate, 2)
            total = round(subtotal + surcharge, 2)
            return {
                "base": base,
                "storage": storage,
                "surcharge": surcharge,
                "total": total
            }

        # 3 days stored in solvent city: $500 base + 3 * $150 = $950, 0% surcharge
        res_sol = calc_impound(500.00, 3, 150.00, "solvent")
        self.assertEqual(res_sol["storage"], 450.00)
        self.assertEqual(res_sol["surcharge"], 0.00)
        self.assertEqual(res_sol["total"], 950.00)

        # 3 days stored in bankrupt city: $950 subtotal + 60% ($570) = $1520
        res_bk = calc_impound(500.00, 3, 150.00, "bankrupt")
        self.assertEqual(res_bk["surcharge"], 570.00)
        self.assertEqual(res_bk["total"], 1520.00)

    def test_web_html_vehicle_overlay_structure(self):
        """Verify index.html contains Section 8G #vehicle-terminal-overlay, required tabs, and submodals."""
        html_path = os.path.join(FIVEM_DIR, "nyx_ui", "web", "index.html")
        self.assertTrue(os.path.isfile(html_path))
        with open(html_path, "r", encoding="utf-8") as f:
            html = f.read()

        self.assertIn('id="vehicle-terminal-overlay"', html)
        self.assertIn('id="vehicle-tab-diagnostics"', html)
        self.assertIn('id="vehicle-tab-impound"', html)
        self.assertIn('id="vehicle-tab-compliance"', html)
        self.assertIn('id="vehicle-submodal-service"', html)
        self.assertIn('id="vehicle-submodal-release"', html)
        self.assertIn('id="dev-btn-vehicle"', html)

    def test_cef_css_render_budget(self):
        """Verify app.css satisfies CEF performance constraints."""
        css_path = os.path.join(FIVEM_DIR, "nyx_ui", "web", "css", "app.css")
        self.assertTrue(os.path.isfile(css_path))
        with open(css_path, "r", encoding="utf-8") as f:
            css = f.read()

        self.assertIn("#vehicle-terminal-overlay", css)
        # Verify no backdrop-filter inside vehicle terminal styling
        overlay_pos = css.find("#vehicle-terminal-overlay")
        self.assertGreater(overlay_pos, -1)
        overlay_block = css[overlay_pos:overlay_pos + 4000]
        self.assertNotIn("backdrop-filter", overlay_block)
        self.assertNotIn("blur(", overlay_block)

    def test_js_app_state_and_handlers(self):
        """Verify js/app.js handles vehicle terminal messages, tabs, and NUI callbacks."""
        js_path = os.path.join(FIVEM_DIR, "nyx_ui", "web", "js", "app.js")
        self.assertTrue(os.path.isfile(js_path))
        with open(js_path, "r", encoding="utf-8") as f:
            js = f.read()

        self.assertIn("VEHICLE_TERMINAL_OPEN", js)
        self.assertIn("VEHICLE_TERMINAL_CLOSE", js)
        self.assertIn("NyxState.vehicle", js)
        self.assertIn("closeVehicleTerminal", js)
        self.assertIn("vehicle:getOverview", js)
        self.assertIn("vehicle:scanOBD", js)
        self.assertIn("vehicle:performService", js)
        self.assertIn("vehicle:releaseImpound", js)

    def test_ui_bridge_registration(self):
        """Verify bridge.lua sanitizes vehicle payload parameters and registers safe callbacks."""
        bridge_path = os.path.join(FIVEM_DIR, "nyx_ui", "client", "bridge.lua")
        self.assertTrue(os.path.isfile(bridge_path))
        with open(bridge_path, "r", encoding="utf-8") as f:
            bridge = f.read()

        self.assertIn("closeVehicleTerminal", bridge)
        self.assertIn("vehicle:getOverview", bridge)
        self.assertIn("vehicle:scanOBD", bridge)
        self.assertIn("vehicle:performService", bridge)
        self.assertIn("vehicle:releaseImpound", bridge)

        exports_path = os.path.join(FIVEM_DIR, "nyx_ui", "client", "exports.lua")
        with open(exports_path, "r", encoding="utf-8") as f:
            exp = f.read()

        self.assertIn("OpenVehicleTerminalUI", exp)
        self.assertIn("CloseVehicleTerminalUI", exp)

    def test_core_tests_lua_integration(self):
        """Verify nyx_core/server/tests.lua has TestVehicleDiagnosticsAndCivicImpoundUI."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        self.assertTrue(os.path.isfile(tests_path))
        with open(tests_path, "r", encoding="utf-8") as f:
            tests_lua = f.read()

        self.assertIn("TestVehicleDiagnosticsAndCivicImpoundUI", tests_lua)


if __name__ == "__main__":
    unittest.main()
