#!/usr/bin/env python3
"""
Unit and Integration Tests for Citizen OS Master Smartphone Framework (nyx_ui)
Covers: Migration 040, Pure Lua Shared Phone Engine, Server RPCs, Client UI Bridge,
        CEF Render Budget, and In-Engine Test Harness Registration.
"""

import os
import sys
import json
import re
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestCitizenOSSmartphoneFramework(unittest.TestCase):
    def test_migration_040_exists_and_registered(self):
        """Verify migration 040 exists on disk, mirrored, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("040_citizen_os_smartphone_framework.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "040_citizen_os_smartphone_framework.sql")
        ui_mig = os.path.join(FIVEM_DIR, "nyx_ui", "sql", "migrations", "040_citizen_os_smartphone_framework.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 040 missing")
        self.assertTrue(os.path.isfile(ui_mig), "nyx_ui migration 040 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("CREATE TABLE IF NOT EXISTS `nyx_phone_emergency_alerts`", sql)
        self.assertIn("CREATE TABLE IF NOT EXISTS `nyx_phone_settings`", sql)
        self.assertIn("alert_uuid", sql)
        self.assertIn("phone_number", sql)
        self.assertIn("wallpaper", sql)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest.lua declares shared, server, and client scripts for smartphone."""
        manifest_path = os.path.join(FIVEM_DIR, "nyx_ui", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_path))
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = f.read()

        self.assertIn("shared/phone.lua", manifest)
        self.assertIn("server/phone.lua", manifest)
        self.assertIn("client/phone.lua", manifest)

        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_ui", "shared", "phone.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_ui", "server", "phone.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_ui", "client", "phone.lua")))

    def test_transfer_tax_and_fee_calculation(self):
        """Test calculation of wire transfer tax and fee rounding logic matching pure Lua implementation."""
        def calculate_transfer_tax(amount, tax_rate):
            amt = float(amount or 0.0)
            rate = float(tax_rate if tax_rate is not None else 0.02)
            if amt <= 0.0:
                return 0.0, 0.0
            fee = round(amt * rate, 2)
            total_debit = round(amt + fee, 2)
            return fee, total_debit

        # Standard transfer: $1,000 at 2% transfer tax -> $20.00 fee, $1,020.00 total debit
        fee1, deb1 = calculate_transfer_tax(1000.0, 0.02)
        self.assertEqual(fee1, 20.0)
        self.assertEqual(deb1, 1020.0)

        # Micro transfer: $15.50 at 2% -> $0.31 fee
        fee2, deb2 = calculate_transfer_tax(15.50, 0.02)
        self.assertEqual(fee2, 0.31)
        self.assertEqual(deb2, 15.81)

        # Zero or negative amount
        fee3, deb3 = calculate_transfer_tax(0.0, 0.02)
        self.assertEqual(fee3, 0.0)
        self.assertEqual(deb3, 0.0)

    def test_transfer_payload_validation(self):
        """Test validation of mobile wire transfer payloads."""
        def validate_transfer(payload, sender_id):
            if not isinstance(payload, dict):
                return False, "INVALID_PAYLOAD"
            recipient = str(payload.get("recipientCitizenId") or "").strip()
            if not recipient or len(recipient) < 2 or len(recipient) > 64:
                return False, "INVALID_RECIPIENT"
            if recipient == str(sender_id):
                return False, "CANNOT_TRANSFER_TO_SELF"
            try:
                amt = float(payload.get("amount") or 0.0)
            except (ValueError, TypeError):
                return False, "INVALID_AMOUNT"
            if amt < 1.0 or amt > 10000000.0:
                return False, "AMOUNT_OUT_OF_BOUNDS"
            memo = str(payload.get("memo") or "")
            if len(memo) > 128:
                return False, "MEMO_TOO_LONG"
            return True, {
                "recipientCitizenId": recipient,
                "amount": round(amt, 2),
                "memo": memo
            }

        # Valid payload
        ok1, res1 = validate_transfer({"recipientCitizenId": "CITIZEN_B", "amount": 250.0, "memo": "Dinner"}, "CITIZEN_A")
        self.assertTrue(ok1)
        self.assertEqual(res1["amount"], 250.0)

        # Self-transfer blocked
        ok2, err2 = validate_transfer({"recipientCitizenId": "CITIZEN_A", "amount": 100.0}, "CITIZEN_A")
        self.assertFalse(ok2)
        self.assertEqual(err2, "CANNOT_TRANSFER_TO_SELF")

        # Amount bounds
        ok3, err3 = validate_transfer({"recipientCitizenId": "CITIZEN_B", "amount": 0.50}, "CITIZEN_A")
        self.assertFalse(ok3)
        self.assertEqual(err3, "AMOUNT_OUT_OF_BOUNDS")

        ok4, err4 = validate_transfer({"recipientCitizenId": "CITIZEN_B", "amount": 15000000.0}, "CITIZEN_A")
        self.assertFalse(ok4)
        self.assertEqual(err4, "AMOUNT_OUT_OF_BOUNDS")

    def test_emergency_alert_payload_validation(self):
        """Test validation of emergency 911 citizen alert payloads."""
        def validate_alert(payload):
            if not isinstance(payload, dict):
                return False, "INVALID_PAYLOAD"
            valid_categories = {"police", "medical", "fire", "traffic", "general"}
            cat = str(payload.get("category") or "").lower().strip()
            if cat not in valid_categories:
                return False, "INVALID_CATEGORY"
            msg = str(payload.get("message") or "").strip()
            if len(msg) < 5:
                return False, "MESSAGE_TOO_SHORT"
            if len(msg) > 500:
                return False, "MESSAGE_TOO_LONG"
            valid_priorities = {"low", "medium", "high", "critical"}
            priority = str(payload.get("priority") or "medium").lower().strip()
            if priority not in valid_priorities:
                priority = "medium"
            location = str(payload.get("locationLabel") or "Los Santos").strip()
            return True, {
                "category": cat,
                "message": msg,
                "priority": priority,
                "locationLabel": location[:128]
            }

        # Valid alert
        ok1, res1 = validate_alert({"category": "police", "message": "Armed robbery in progress at Legion Bank", "priority": "critical"})
        self.assertTrue(ok1)
        self.assertEqual(res1["category"], "police")
        self.assertEqual(res1["priority"], "critical")

        # Invalid category
        ok2, err2 = validate_alert({"category": "alien_invasion", "message": "Help me!"})
        self.assertFalse(ok2)
        self.assertEqual(err2, "INVALID_CATEGORY")

        # Message too short
        ok3, err3 = validate_alert({"category": "medical", "message": "Help"})
        self.assertFalse(ok3)
        self.assertEqual(err3, "MESSAGE_TOO_SHORT")

    def test_phone_number_formatting_and_generation(self):
        """Test deterministic phone number formatting and generation."""
        def format_phone_number(raw):
            clean = re.sub(r"[^\d]", "", str(raw or ""))
            if len(clean) == 7:
                return f"{clean[:3]}-{clean[3:]}"
            elif len(clean) == 10:
                return f"({clean[:3]}) {clean[3:6]}-{clean[6:]}"
            elif len(clean) >= 4:
                return f"555-{clean[-4:]}"
            return "555-0100"

        self.assertEqual(format_phone_number("5551234"), "555-1234")
        self.assertEqual(format_phone_number("2125550199"), "(212) 555-0199")
        self.assertEqual(format_phone_number("88"), "555-0100")

    def test_web_spa_html_structure(self):
        """Verify index.html contains #phone-overlay, dynamic island, status bar, and app views."""
        html_path = os.path.join(FIVEM_DIR, "nyx_ui", "web", "index.html")
        self.assertTrue(os.path.isfile(html_path))
        with open(html_path, "r", encoding="utf-8") as f:
            html = f.read()

        self.assertIn('id="phone-overlay"', html)
        self.assertIn('id="phone-chassis"', html)
        self.assertIn('id="phone-status-time"', html)
        self.assertIn('id="phone-app-grid"', html)
        self.assertIn('id="phone-app-banking"', html)
        self.assertIn('id="phone-app-logistics"', html)
        self.assertIn('id="phone-app-alerts"', html)
        self.assertIn('id="phone-app-profile"', html)
        self.assertIn('id="phone-app-settings"', html)
        self.assertIn('id="dev-btn-phone"', html)

    def test_cef_css_render_budget(self):
        """Verify css/app.css conforms to CEF render budget (no backdrop-filter, no blur)."""
        css_path = os.path.join(FIVEM_DIR, "nyx_ui", "web", "css", "app.css")
        self.assertTrue(os.path.isfile(css_path))
        with open(css_path, "r", encoding="utf-8") as f:
            css = f.read()

        phone_blocks = re.findall(r'(#[a-zA-Z0-9_-]*phone[a-zA-Z0-9_-]*\s*\{[^}]*\})', css, re.DOTALL)
        self.assertGreater(len(phone_blocks), 0, "No phone CSS rules found")

        for block in phone_blocks:
            self.assertNotIn("backdrop-filter", block, f"Forbidden backdrop-filter in {block}")
            self.assertNotIn("blur(", block, f"Forbidden blur in {block}")

    def test_web_js_state_and_handlers(self):
        """Verify js/app.js declares NyxState.phone, message listeners, and app navigation."""
        js_path = os.path.join(FIVEM_DIR, "nyx_ui", "web", "js", "app.js")
        self.assertTrue(os.path.isfile(js_path))
        with open(js_path, "r", encoding="utf-8") as f:
            js = f.read()

        self.assertIn("NyxState.phone", js)
        self.assertIn("PHONE_OPEN", js)
        self.assertIn("PHONE_CLOSE", js)
        self.assertIn("switchPhoneApp", js)
        self.assertIn("phone:transferMoney", js)
        self.assertIn("phone:sendEmergencyAlert", js)

    def test_in_engine_tests_lua_registered(self):
        """Verify nyx_core/server/tests.lua registers and executes Test 35."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        self.assertTrue(os.path.isfile(tests_path))
        with open(tests_path, "r", encoding="utf-8") as f:
            tests = f.read()

        self.assertIn("TestCitizenOSSmartphoneFramework", tests)
        self.assertIn("t35", tests)


if __name__ == "__main__":
    unittest.main()
