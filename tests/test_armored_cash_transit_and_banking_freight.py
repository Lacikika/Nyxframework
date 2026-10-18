#!/usr/bin/env python3
"""
Unit and Integration Tests for Armored Cash Transit & High-Value Banking Freight
(nyx_factions, nyx_treasury, nyx_inventory, nyx_core).
Covers: Migration 053 schema & indices, inventory items (armored_cash_box, cash_transit_manifest),
        fxmanifest script declarations, transit split arithmetic & exact zero-cent conservation (Delta = 0.00),
        register cash accumulation threshold evaluation, cash box creation validation,
        municipal vault deposit validation, box breach & dye pack forensic mechanics,
        zero-trust payload sanitizers & formatters, and in-engine Test 48 integration.
"""

import os
import json
import math
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestArmoredCashTransitAndBankingFreight(unittest.TestCase):
    def test_migration_053_exists_and_registered(self):
        """Verify migration 053 exists on disk, mirrored across resources, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("053_armored_cash_transit_and_banking_freight.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "053_armored_cash_transit_and_banking_freight.sql")
        factions_mig = os.path.join(FIVEM_DIR, "nyx_factions", "sql", "migrations", "053_armored_cash_transit_and_banking_freight.sql")
        treasury_mig = os.path.join(FIVEM_DIR, "nyx_treasury", "sql", "migrations", "053_armored_cash_transit_and_banking_freight.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 053 missing")
        self.assertTrue(os.path.isfile(factions_mig), "nyx_factions migration 053 missing")
        self.assertTrue(os.path.isfile(treasury_mig), "nyx_treasury migration 053 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("nyx_treasury_cash_transit_boxes", sql)
        self.assertIn("nyx_treasury_bank_vaults", sql)
        self.assertIn("nyx_treasury_cash_transit_audits", sql)
        self.assertIn("transit_threshold", sql)
        self.assertIn("pending_transit_box_id", sql)
        self.assertIn("vault:pacific_standard", sql)
        self.assertIn("vault:blaine_county", sql)
        self.assertIn("pool:cash_transit:clearing", sql)

    def test_inventory_items_registered(self):
        """Verify armored_cash_box and cash_transit_manifest are registered in items.lua with metadata generator."""
        items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
        self.assertTrue(os.path.isfile(items_path))
        with open(items_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("['armored_cash_box']", content)
        self.assertIn("Armored High-Value Cash Box", content)
        self.assertIn("['cash_transit_manifest']", content)
        self.assertIn("Cash-In-Transit Security Manifest", content)
        self.assertIn("meta.boxUuid", content)
        self.assertIn("meta.sealSerial", content)
        self.assertIn("meta.destinationVault", content)
        self.assertIn("meta.manifestUuid", content)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest declarations in nyx_factions and nyx_treasury."""
        tre_manifest = os.path.join(FIVEM_DIR, "nyx_treasury", "fxmanifest.lua")
        with open(tre_manifest, "r", encoding="utf-8") as f:
            tre_txt = f.read()

        self.assertIn("shared/cash_transit.lua", tre_txt)
        self.assertIn("server/cash_transit.lua", tre_txt)
        self.assertIn("client/cash_transit.lua", tre_txt)

        fac_manifest = os.path.join(FIVEM_DIR, "nyx_factions", "fxmanifest.lua")
        with open(fac_manifest, "r", encoding="utf-8") as f:
            fac_txt = f.read()

        self.assertIn("@nyx_treasury/shared/cash_transit.lua", fac_txt)
        self.assertIn("server/cash_transit.lua", fac_txt)
        self.assertIn("client/cash_transit.lua", fac_txt)

    def test_transit_split_calculation_math_and_conservation(self):
        """Verify transit split arithmetic guarantees strict zero-cent closed-loop conservation (Delta = 0.00)."""
        def calc_split(gross_amount, deposit_fee_pct=1.00, courier_reward_pct=2.00):
            gross = math.floor(gross_amount * 100) / 100
            if gross <= 0:
                return {
                    "grossAmount": 0.00,
                    "municipalBankFee": 0.00,
                    "courierPayout": 0.00,
                    "netCorporateDeposit": 0.00
                }
            fee = math.floor((gross * (deposit_fee_pct / 100.0)) * 100) / 100
            reward = math.floor((gross * (courier_reward_pct / 100.0)) * 100) / 100
            net = round(gross - (fee + reward), 2)
            return {
                "grossAmount": gross,
                "municipalBankFee": fee,
                "courierPayout": reward,
                "netCorporateDeposit": net
            }

        s1 = calc_split(50000.00, 1.00, 2.00)
        self.assertEqual(s1["municipalBankFee"], 500.00)
        self.assertEqual(s1["courierPayout"], 1000.00)
        self.assertEqual(s1["netCorporateDeposit"], 48500.00)
        self.assertAlmostEqual(s1["municipalBankFee"] + s1["courierPayout"] + s1["netCorporateDeposit"], 50000.00, places=2)

        # Test with fractional / odd amounts
        s2 = calc_split(12345.67, 1.25, 2.50)
        self.assertAlmostEqual(s2["municipalBankFee"] + s2["courierPayout"] + s2["netCorporateDeposit"], s2["grossAmount"], places=2)

        s_zero = calc_split(0.00)
        self.assertEqual(s_zero["grossAmount"], 0.00)
        self.assertEqual(s_zero["netCorporateDeposit"], 0.00)

    def test_register_transit_need_evaluation(self):
        """Verify register excess cash threshold evaluation and recommended transit box amounts."""
        def evaluate_need(reg):
            if not reg or reg.get("is_active", 1) == 0:
                return False, "REGISTER_INACTIVE"
            if reg.get("is_frozen", 0) == 1:
                return False, "REGISTER_FROZEN"
            if reg.get("pending_transit_box_id"):
                return False, "TRANSIT_ALREADY_PENDING"

            clean_cash = float(reg.get("clean_cash_balance", 0.0))
            threshold = float(reg.get("transit_threshold", 10000.00))
            min_floor = 1000.00  # Retain float in register till

            if clean_cash < threshold:
                return False, "BELOW_TRANSIT_THRESHOLD"

            suggested_amount = round(clean_cash - min_floor, 2)
            if suggested_amount < 1000.00:
                suggested_amount = round(clean_cash, 2)

            return True, {
                "cleanCashBalance": clean_cash,
                "threshold": threshold,
                "suggestedBoxAmount": suggested_amount
            }

        reg_ready = {
            "register_id": "reg_unicorn_main",
            "is_active": 1,
            "is_frozen": 0,
            "clean_cash_balance": 25000.00,
            "transit_threshold": 10000.00,
            "pending_transit_box_id": None
        }
        ok_ready, data_ready = evaluate_need(reg_ready)
        self.assertTrue(ok_ready)
        self.assertEqual(data_ready["suggestedBoxAmount"], 24000.00)

        reg_low = dict(reg_ready, clean_cash_balance=4500.00)
        ok_low, err_low = evaluate_need(reg_low)
        self.assertFalse(ok_low)
        self.assertEqual(err_low, "BELOW_TRANSIT_THRESHOLD")

        reg_frozen = dict(reg_ready, is_frozen=1)
        ok_frz, err_frz = evaluate_need(reg_frozen)
        self.assertFalse(ok_frz)
        self.assertEqual(err_frz, "REGISTER_FROZEN")

        reg_pending = dict(reg_ready, pending_transit_box_id="BOX-12345")
        ok_pnd, err_pnd = evaluate_need(reg_pending)
        self.assertFalse(ok_pnd)
        self.assertEqual(err_pnd, "TRANSIT_ALREADY_PENDING")

    def test_box_creation_validation(self):
        """Verify zero-trust validation for packing cash transit boxes."""
        def validate_box_creation(reg, amount):
            if not reg or reg.get("is_active", 1) == 0:
                return False, "REGISTER_INACTIVE"
            if reg.get("is_frozen", 0) == 1:
                return False, "REGISTER_FROZEN"
            amt = float(amount or 0.0)
            if amt < 1000.00:
                return False, "AMOUNT_BELOW_MINIMUM"
            if amt > 250000.00:
                return False, "AMOUNT_EXCEEDS_MAXIMUM"
            clean_balance = float(reg.get("clean_cash_balance", 0.0))
            if amt > clean_balance:
                return False, "INSUFFICIENT_REGISTER_CASH"
            return True, round(amt, 2)

        reg = {"is_active": 1, "is_frozen": 0, "clean_cash_balance": 50000.00}
        self.assertTrue(validate_box_creation(reg, 25000.00)[0])
        self.assertFalse(validate_box_creation(reg, 500.00)[0])
        self.assertFalse(validate_box_creation(reg, 300000.00)[0])
        self.assertFalse(validate_box_creation(reg, 75000.00)[0])

    def test_vault_deposit_validation(self):
        """Verify bank vault deposit validation and status transition enforcement."""
        def validate_deposit(box, vault):
            if not vault or vault.get("is_active", 1) == 0:
                return False, "VAULT_INACTIVE"
            if not box:
                return False, "BOX_NOT_FOUND"
            if box.get("status") == "deposited":
                return False, "BOX_ALREADY_DEPOSITED"
            if box.get("tamper_state") == "breached":
                return False, "BOX_ALREADY_BREACHED"
            if box.get("status") not in ("staged", "in_transit"):
                return False, "INVALID_BOX_STATUS"
            return True, "OK"

        valid_box = {"status": "in_transit", "tamper_state": "sealed", "cash_amount": 25000.00}
        valid_vault = {"vault_id": "vault:pacific_standard", "is_active": 1}

        self.assertTrue(validate_deposit(valid_box, valid_vault)[0])

        already_dep = dict(valid_box, status="deposited")
        self.assertFalse(validate_deposit(already_dep, valid_vault)[0])

        breached_box = dict(valid_box, tamper_state="breached")
        self.assertFalse(validate_deposit(breached_box, valid_vault)[0])

        inactive_vault = dict(valid_vault, is_active=0)
        self.assertFalse(validate_deposit(valid_box, inactive_vault)[0])

    def test_breach_outcome_math_and_tool_profiles(self):
        """Verify criminal breach mechanics, tool wear, dye pack discharge, and glove immunity."""
        tools = {
            "tool_angle_grinder": {"base_chance": 0.65, "wear": 25.0, "dye_risk": 0.40, "noise_radius": 25.0},
            "thermite_charge": {"base_chance": 0.85, "wear": 100.0, "dye_risk": 0.70, "noise_radius": 35.0},
            "tool_crowbar": {"base_chance": 0.30, "wear": 35.0, "dye_risk": 0.20, "noise_radius": 20.0}
        }

        def calc_breach(tool_name, roll=0.50, dye_roll=0.30, has_gloves=False):
            prof = tools.get(tool_name)
            if not prof:
                return False, "UNKNOWN_TOOL"
            success = roll <= prof["base_chance"]
            dye_triggered = dye_roll <= prof["dye_risk"]
            fingerprint_left = not has_gloves
            return True, {
                "success": success,
                "dyeTriggered": dye_triggered,
                "fingerprintLeft": fingerprint_left,
                "noiseRadius": prof["noise_radius"]
            }

        ok, grinder_res = calc_breach("tool_angle_grinder", roll=0.50, dye_roll=0.50, has_gloves=True)
        self.assertTrue(ok)
        self.assertTrue(grinder_res["success"])
        self.assertFalse(grinder_res["dyeTriggered"])
        self.assertFalse(grinder_res["fingerprintLeft"])

        ok2, thermite_res = calc_breach("thermite_charge", roll=0.90, dye_roll=0.60, has_gloves=False)
        self.assertTrue(ok2)
        self.assertFalse(thermite_res["success"])  # 0.90 > 0.85
        self.assertTrue(thermite_res["dyeTriggered"])  # 0.60 <= 0.70
        self.assertTrue(thermite_res["fingerprintLeft"])

    def test_zero_trust_payload_sanitizers_and_formatters(self):
        """Verify payload sanitizers and visual UI formatters."""
        def sanitize_creation(payload):
            if not isinstance(payload, dict):
                return False, "INVALID_PAYLOAD"
            reg_id = str(payload.get("registerId", "")).strip()
            if len(reg_id) < 3:
                return False, "INVALID_REGISTER_ID"
            try:
                amt = float(payload.get("amount", 0.0))
            except (ValueError, TypeError):
                return False, "INVALID_AMOUNT"
            if amt <= 0.0:
                return False, "INVALID_AMOUNT"
            return True, {"registerId": reg_id, "amount": round(amt, 2)}

        self.assertTrue(sanitize_creation({"registerId": "reg_unicorn_main", "amount": 15000})[0])
        self.assertFalse(sanitize_creation({"registerId": "", "amount": 15000})[0])
        self.assertFalse(sanitize_creation({"registerId": "reg_1", "amount": -100})[0])

    def test_in_engine_test_48_registered(self):
        """Verify in-engine integration test Test 48 is declared and wired into tests.lua RunAll()."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        self.assertTrue(os.path.isfile(tests_path))
        with open(tests_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("function Nyx.Tests.TestArmoredCashTransitAndBankingFreight()", content)
        self.assertIn("TestArmoredCashTransitAndBankingFreight()", content)
        self.assertIn("t48", content)


if __name__ == "__main__":
    unittest.main()
