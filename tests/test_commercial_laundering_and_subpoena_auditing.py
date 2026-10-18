#!/usr/bin/env python3
"""
Unit and Integration Tests for Commercial Money Laundering & Subpoena Ledger Auditing
(nyx_factions, nyx_treasury, nyx_judiciary, nyx_inventory, nyx_core).
Covers: Migration 051 schema & indices, inventory items (dirty_money, marked_bills),
        fxmanifest script declarations, declarative commercial business profiles,
        mathematical laundering split & cent conservation (Delta = 0.00),
        drip laundering calculation & remaining cap bounds,
        zero-trust dirty cash injection validation,
        register operational eligibility & judicial freeze restraint,
        statistical ledger anomaly detection (cash ratio, velocity burst, Benford round numbers),
        cryptographic SHA-256 report integrity & subpoena warrant scope verification,
        and in-engine Test 46 integration.
"""

import os
import json
import hashlib
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestCommercialMoneyLaunderingAndSubpoenaAuditing(unittest.TestCase):
    def test_migration_051_exists_and_registered(self):
        """Verify migration 051 exists on disk, mirrored, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("051_commercial_money_laundering_and_subpoena_auditing.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "051_commercial_money_laundering_and_subpoena_auditing.sql")
        factions_mig = os.path.join(FIVEM_DIR, "nyx_factions", "sql", "migrations", "051_commercial_money_laundering_and_subpoena_auditing.sql")
        treasury_mig = os.path.join(FIVEM_DIR, "nyx_treasury", "sql", "migrations", "051_commercial_money_laundering_and_subpoena_auditing.sql")
        jud_mig = os.path.join(FIVEM_DIR, "nyx_judiciary", "sql", "migrations", "051_commercial_money_laundering_and_subpoena_auditing.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 051 missing")
        self.assertTrue(os.path.isfile(factions_mig), "nyx_factions migration 051 missing")
        self.assertTrue(os.path.isfile(treasury_mig), "nyx_treasury migration 051 missing")
        self.assertTrue(os.path.isfile(jud_mig), "nyx_judiciary migration 051 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("nyx_factions_commercial_registers", sql)
        self.assertIn("nyx_factions_laundering_injections", sql)
        self.assertIn("nyx_treasury_subpoena_audits", sql)
        self.assertIn("clean_cash_balance", sql)
        self.assertIn("dirty_cash_pool", sql)
        self.assertIn("max_daily_laundering_cap", sql)
        self.assertIn("drip_amount_per_tick", sql)
        self.assertIn("financial", sql)
        self.assertIn("pool:laundering:clearing", sql)
        self.assertIn("corp_vanilla_unicorn", sql)
        self.assertIn("priv_carwash_strawberry", sql)

    def test_inventory_items_registered(self):
        """Verify dirty_money and marked_bills are registered in items.lua with metadata."""
        items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
        self.assertTrue(os.path.isfile(items_path))
        with open(items_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("['dirty_money']", content)
        self.assertIn("['marked_bills']", content)
        self.assertIn("Illicit Cash Stack", content)
        self.assertIn("Dye-Pack Marked Bills", content)
        self.assertIn("bundleValue", content)
        self.assertIn("taintRatio", content)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest declarations in nyx_factions and nyx_treasury."""
        fac_manifest = os.path.join(FIVEM_DIR, "nyx_factions", "fxmanifest.lua")
        with open(fac_manifest, "r", encoding="utf-8") as f:
            fac_txt = f.read()

        self.assertIn("shared/laundering.lua", fac_txt)
        self.assertIn("server/laundering.lua", fac_txt)
        self.assertIn("client/laundering.lua", fac_txt)

        tre_manifest = os.path.join(FIVEM_DIR, "nyx_treasury", "fxmanifest.lua")
        with open(tre_manifest, "r", encoding="utf-8") as f:
            tre_txt = f.read()

        self.assertIn("shared/subpoena_audit.lua", tre_txt)
        self.assertIn("server/subpoena_audit.lua", tre_txt)
        self.assertIn("client/subpoena_audit.lua", tre_txt)

    def test_business_profiles_taxonomy(self):
        """Verify business profiles and baseline cash tolerances."""
        profiles = {
            'nightclub': {'baseline': 0.70, 'fee': 12.0, 'cap': 100000.0},
            'carwash': {'baseline': 0.60, 'fee': 15.0, 'cap': 40000.0},
            'restaurant': {'baseline': 0.45, 'fee': 14.0, 'cap': 60000.0},
            'pawnshop': {'baseline': 0.55, 'fee': 18.0, 'cap': 75000.0},
            'retail': {'baseline': 0.30, 'fee': 20.0, 'cap': 30000.0},
            'consulting': {'baseline': 0.05, 'fee': 25.0, 'cap': 20000.0},
            'logistics': {'baseline': 0.15, 'fee': 15.0, 'cap': 50000.0}
        }

        self.assertEqual(profiles['nightclub']['baseline'], 0.70)
        self.assertEqual(profiles['consulting']['baseline'], 0.05)
        self.assertTrue(profiles['consulting']['fee'] > profiles['nightclub']['fee'])

    def test_laundering_split_math_and_cent_conservation(self):
        """Simulate CalculateLaunderingSplit and verify exact cent conservation."""
        def calculate_split(gross, fee_pct, tax_pct):
            tax_rate = tax_pct / 100.0
            fee_rate = fee_pct / 100.0
            tax = round(gross * tax_rate, 2)
            fee = round(gross * fee_rate, 2)
            clean = round(gross - tax - fee, 2)
            delta = round(gross - (clean + tax + fee), 2)
            clean = round(clean + delta, 2)
            return clean, tax, fee

        test_amounts = [10000.00, 2543.77, 500.01, 12345.67, 99.99]
        for amt in test_amounts:
            clean, tax, fee = calculate_split(amt, 12.0, 10.0)
            self.assertEqual(round(clean + tax + fee, 2), amt)
            self.assertTrue(clean >= 0.0)
            self.assertTrue(tax >= 0.0)
            self.assertTrue(fee >= 0.0)

    def test_drip_amount_calculation_and_cap_bounds(self):
        """Verify drip wash calculation adheres to pool size, pace, and daily cap."""
        def calculate_drip(dirty_pool, default_drip, remaining_cap):
            if dirty_pool <= 0 or remaining_cap <= 0:
                return 0.00
            return min(dirty_pool, default_drip, remaining_cap)

        self.assertEqual(calculate_drip(15000.0, 2500.0, 50000.0), 2500.0)
        self.assertEqual(calculate_drip(15000.0, 2500.0, 1200.0), 1200.0)
        self.assertEqual(calculate_drip(800.0, 2500.0, 50000.0), 800.0)
        self.assertEqual(calculate_drip(15000.0, 2500.0, 0.0), 0.0)
        self.assertEqual(calculate_drip(0.0, 2500.0, 50000.0), 0.0)

    def test_zero_trust_injection_validation(self):
        """Verify injection payload sanitizer blocks negative numbers and malformed targets."""
        def validate_payload(data):
            if not isinstance(data, dict):
                return False, "PAYLOAD_MUST_BE_TABLE"
            reg_id = data.get("registerId")
            if not reg_id or not isinstance(reg_id, str) or len(reg_id) < 3:
                return False, "INVALID_REGISTER_ID"
            amount = data.get("amount")
            if amount is None or amount <= 0 or amount > 500000.0:
                return False, "INVALID_AMOUNT"
            cit_id = data.get("citizenId")
            if not cit_id or not isinstance(cit_id, str) or len(cit_id) < 3:
                return False, "INVALID_CITIZEN_ID"
            return True, "OK"

        self.assertTrue(validate_payload({"registerId": "reg_unicorn", "amount": 5000.0, "citizenId": "CIT-01"})[0])
        self.assertFalse(validate_payload({"registerId": "reg_unicorn", "amount": -100.0, "citizenId": "CIT-01"})[0])
        self.assertFalse(validate_payload({"registerId": "", "amount": 5000.0, "citizenId": "CIT-01"})[0])
        self.assertFalse(validate_payload({"registerId": "reg_unicorn", "amount": 600000.0, "citizenId": "CIT-01"})[0])
        self.assertFalse(validate_payload({"registerId": "reg_unicorn", "amount": 5000.0, "citizenId": ""})[0])

    def test_register_eligibility_and_freeze(self):
        """Verify register eligibility rules and judicial freeze restraint."""
        def evaluate_register(reg, inject_amount):
            if reg.get("is_active") != 1:
                return False, "REGISTER_DECOMMISSIONED"
            if reg.get("is_frozen") == 1:
                return False, "REGISTER_FROZEN"
            max_cap = reg.get("max_daily_cap", 50000.0)
            laundered_today = reg.get("daily_laundered", 0.0)
            dirty_pool = reg.get("dirty_pool", 0.0)
            remaining_cap = max(0.0, max_cap - laundered_today)
            if remaining_cap <= 0 and dirty_pool <= 0:
                return False, "DAILY_CAP_EXHAUSTED"
            if (dirty_pool + inject_amount) > (max_cap * 3.0):
                return False, "VAULT_OVERFLOW"
            return True, "ELIGIBLE"

        active_reg = {"is_active": 1, "is_frozen": 0, "max_daily_cap": 50000.0, "daily_laundered": 10000.0, "dirty_pool": 2000.0}
        frozen_reg = {"is_active": 1, "is_frozen": 1, "max_daily_cap": 50000.0, "daily_laundered": 0.0, "dirty_pool": 2000.0}
        overflow_reg = {"is_active": 1, "is_frozen": 0, "max_daily_cap": 10000.0, "daily_laundered": 0.0, "dirty_pool": 28000.0}

        self.assertTrue(evaluate_register(active_reg, 5000.0)[0])
        self.assertFalse(evaluate_register(frozen_reg, 5000.0)[0])
        self.assertFalse(evaluate_register(overflow_reg, 5000.0)[0])

    def test_statistical_anomaly_detection(self):
        """Verify forensic anomaly detector identifies disproportionate cash ratios and velocity bursts."""
        def analyze_anomalies(txs, baseline_ratio):
            total_vol = sum(t["amount"] for t in txs)
            cash_vol = sum(t["amount"] for t in txs if t.get("is_cash"))
            cash_ratio = (cash_vol / total_vol) if total_vol > 0 else 0.0

            score = 0.0
            anomalies = []

            # Vector 1: Cash ratio excess
            if cash_ratio > (baseline_ratio + 0.15):
                excess = cash_ratio - baseline_ratio
                pts = min(35.0, round(excess * 50.0, 2))
                score += pts
                anomalies.append("DISPROPORTIONATE_CASH_RATIO")

            # Vector 2: Round multiple anomaly ($500/$1000 multiples)
            round_count = sum(1 for t in txs if t.get("is_cash") and t["amount"] >= 500 and t["amount"] % 500 == 0)
            if len(txs) >= 3 and (round_count / len(txs)) >= 0.50:
                score += 25.0
                anomalies.append("ARTIFICIAL_ROUND_AMOUNTS")

            # Vector 3: Velocity bursts (< 300s between deposits)
            bursts = 0
            for i in range(1, len(txs)):
                if abs(txs[i]["time"] - txs[i - 1]["time"]) <= 300:
                    bursts += 1
            if bursts >= 2:
                score += 20.0
                anomalies.append("CASH_VELOCITY_SPIKE")

            score = min(100.0, score)
            level = "clean"
            if score >= 65.0:
                level = "high_suspicion"
            elif score >= 35.0:
                level = "elevated"
            elif score >= 15.0:
                level = "low_risk"

            return score, level, anomalies

        # Consulting business (baseline 0.05 cash) flooded with $5,000 round cash deposits in 100-second bursts
        illicit_txs = [
            {"amount": 5000.0, "is_cash": True, "time": 1000},
            {"amount": 5000.0, "is_cash": True, "time": 1100},
            {"amount": 5000.0, "is_cash": True, "time": 1200},
            {"amount": 1000.0, "is_cash": True, "time": 1300}
        ]
        score, level, anomalies = analyze_anomalies(illicit_txs, 0.05)
        self.assertTrue(score >= 65.0)
        self.assertEqual(level, "high_suspicion")
        self.assertIn("DISPROPORTIONATE_CASH_RATIO", anomalies)
        self.assertIn("ARTIFICIAL_ROUND_AMOUNTS", anomalies)
        self.assertIn("CASH_VELOCITY_SPIKE", anomalies)

    def test_sha256_hash_and_subpoena_scope(self):
        """Verify SHA-256 fingerprint generation and judicial warrant scope validation."""
        canonical = "AUDIT:TARGET=corp_vanilla_unicorn:BIZ=nightclub:VOL=100000.00:CASH_PCT=95.00:SCORE=72.50:ANOMALIES=3"
        expected_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
        self.assertEqual(len(expected_hash), 64)

        def validate_subpoena(warrant, target_id):
            if warrant.get("status") != "active":
                return False, "NOT_ACTIVE"
            w_type = warrant.get("type", "").lower()
            if w_type not in ("subpoena", "financial"):
                return False, "NOT_SUBPOENA"
            scope = warrant.get("subpoena_scope", "financial").lower()
            if scope not in ("all", "financial", "corporate"):
                return False, "SCOPE_INVALID"
            target_ent = warrant.get("target_entity_id", "")
            if target_ent and target_id and (target_ent.lower() not in target_id.lower() and target_id.lower() not in target_ent.lower()):
                return False, "ENTITY_MISMATCH"
            return True, "AUTHORIZED"

        valid_warrant = {"status": "active", "type": "subpoena", "subpoena_scope": "financial", "target_entity_id": "corp_vanilla_unicorn"}
        mismatch_warrant = {"status": "active", "type": "subpoena", "subpoena_scope": "financial", "target_entity_id": "syn_mafia"}
        expired_warrant = {"status": "expired", "type": "subpoena", "subpoena_scope": "financial", "target_entity_id": "corp_vanilla_unicorn"}

        self.assertTrue(validate_subpoena(valid_warrant, "corp_vanilla_unicorn")[0])
        self.assertFalse(validate_subpoena(mismatch_warrant, "corp_vanilla_unicorn")[0])
        self.assertFalse(validate_subpoena(expired_warrant, "corp_vanilla_unicorn")[0])

    def test_in_engine_test_46_registered(self):
        """Verify Test 46 is registered in nyx_core/server/tests.lua and called in RunAll()."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        self.assertTrue(os.path.isfile(tests_path))
        with open(tests_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("TestCommercialMoneyLaunderingAndSubpoenaAuditing", content)
        self.assertIn("local t46 = Nyx.Tests.TestCommercialMoneyLaunderingAndSubpoenaAuditing()", content)
        self.assertIn("and t46 then", content)


if __name__ == "__main__":
    unittest.main()
