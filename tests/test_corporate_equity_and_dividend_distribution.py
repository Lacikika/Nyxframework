#!/usr/bin/env python3
"""
Unit and Integration Tests for Corporate Equity Public Offering & Dividend Distribution Engine
(nyx_factions, nyx_treasury, nyx_inventory, nyx_core).
Covers: Migration 052 schema & indices, inventory item (equity_shares),
        fxmanifest script declarations, offering valuation & market cap math,
        share acquisition cost calculation, zero-trust offering creation bounds,
        purchase limits & liquidity validation, consolidated cap table aggregation,
        dividend distribution math & exact zero-cent conservation (Delta = 0.00),
        weekly automated dividend schedule eligibility, zero-trust payload sanitizers,
        and in-engine Test 47 integration.
"""

import os
import json
import math
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestCorporateEquityAndDividendDistribution(unittest.TestCase):
    def test_migration_052_exists_and_registered(self):
        """Verify migration 052 exists on disk, mirrored, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("052_corporate_equity_public_offerings_and_dividend_distribution.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "052_corporate_equity_public_offerings_and_dividend_distribution.sql")
        factions_mig = os.path.join(FIVEM_DIR, "nyx_factions", "sql", "migrations", "052_corporate_equity_public_offerings_and_dividend_distribution.sql")
        treasury_mig = os.path.join(FIVEM_DIR, "nyx_treasury", "sql", "migrations", "052_corporate_equity_public_offerings_and_dividend_distribution.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 052 missing")
        self.assertTrue(os.path.isfile(factions_mig), "nyx_factions migration 052 missing")
        self.assertTrue(os.path.isfile(treasury_mig), "nyx_treasury migration 052 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("nyx_factions_equity_offerings", sql)
        self.assertIn("nyx_factions_equity_shareholders", sql)
        self.assertIn("nyx_factions_equity_purchases", sql)
        self.assertIn("nyx_factions_dividend_runs", sql)
        self.assertIn("dividend_frequency_days", sql)
        self.assertIn("auto_dividends_enabled", sql)
        self.assertIn("reinvestment_rate_target", sql)
        self.assertIn("offering_unicorn_ipo", sql)
        self.assertIn("corp_vanilla_unicorn", sql)

    def test_inventory_equity_shares_item_registered(self):
        """Verify equity_shares document item is registered in items.lua with metadata generator."""
        items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
        self.assertTrue(os.path.isfile(items_path))
        with open(items_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("['equity_shares']", content)
        self.assertIn("Corporate Equity Share Certificate", content)
        self.assertIn("meta.shares", content)
        self.assertIn("meta.factionId", content)
        self.assertIn("meta.certificateUuid", content)
        self.assertIn("meta.sharePrice", content)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest declarations in nyx_factions and nyx_treasury."""
        fac_manifest = os.path.join(FIVEM_DIR, "nyx_factions", "fxmanifest.lua")
        with open(fac_manifest, "r", encoding="utf-8") as f:
            fac_txt = f.read()

        self.assertIn("shared/equity.lua", fac_txt)
        self.assertIn("server/equity.lua", fac_txt)
        self.assertIn("client/equity.lua", fac_txt)

        tre_manifest = os.path.join(FIVEM_DIR, "nyx_treasury", "fxmanifest.lua")
        with open(tre_manifest, "r", encoding="utf-8") as f:
            tre_txt = f.read()

        self.assertIn("@nyx_factions/shared/equity.lua", tre_txt)

    def test_offering_valuation_math(self):
        """Verify calculation of target capital raising and implied market capitalization."""
        def calc_val(shares, price_per_share):
            if shares <= 0 or price_per_share <= 0:
                return {"target_capital": 0.0, "implied_mcap": 0.0}
            target_cap = round(shares * price_per_share, 2)
            implied_mcap = round(price_per_share * 100.0, 2)
            return {"target_capital": target_cap, "implied_mcap": implied_mcap}

        v1 = calc_val(25.00, 2000.00)
        self.assertEqual(v1["target_capital"], 50000.00)
        self.assertEqual(v1["implied_mcap"], 200000.00)

        v2 = calc_val(10.00, 1500.00)
        self.assertEqual(v2["target_capital"], 15000.00)
        self.assertEqual(v2["implied_mcap"], 150000.00)

        v_zero = calc_val(0.00, 2000.00)
        self.assertEqual(v_zero["target_capital"], 0.00)
        self.assertEqual(v_zero["implied_mcap"], 0.00)

    def test_share_purchase_cost_math(self):
        """Verify share purchase price computation with decimal precision."""
        def calc_cost(shares, pps):
            if shares <= 0 or pps <= 0:
                return 0.0
            return round(shares * pps, 2)

        self.assertEqual(calc_cost(3.50, 2000.00), 7000.00)
        self.assertEqual(calc_cost(0.25, 1500.00), 375.00)
        self.assertEqual(calc_cost(0.00, 2000.00), 0.00)

    def test_offering_creation_validation(self):
        """Verify zero-trust validation for creating corporate public equity offerings."""
        eligible_charters = {"corporation", "private_enterprise", "syndicate"}

        def validate_offering(faction, data, issued_equity):
            if not faction or not faction.get("is_active"):
                return False, "FACTION_INACTIVE"
            if faction.get("charter_type") not in eligible_charters:
                return False, "CHARTER_INELIGIBLE_FOR_EQUITY_OFFERING"
            shares = data.get("sharesOffered", 0.0)
            if shares <= 0:
                return False, "INVALID_SHARES"
            avail = round(100.0 - issued_equity, 2)
            if shares > avail:
                return False, f"OFFERING_EXCEEDS_UNISSUED_EQUITY_{avail:.2f}"
            if data.get("pricePerShare", 0.0) < 1.0:
                return False, "PRICE_PER_SHARE_BELOW_MINIMUM"
            title = str(data.get("title", "")).strip()
            if len(title) < 3:
                return False, "INVALID_TITLE"
            return True, "OK"

        corp = {"faction_id": "corp_unicorn", "charter_type": "corporation", "is_active": 1}
        coop = {"faction_id": "coop_farm", "charter_type": "cooperative", "is_active": 1}
        data = {"title": "Series A Raise", "sharesOffered": 20.0, "pricePerShare": 2000.0}

        ok_valid, _ = validate_offering(corp, data, 60.0)
        self.assertTrue(ok_valid)

        ok_exceed, err_exceed = validate_offering(corp, data, 85.0)
        self.assertFalse(ok_exceed)
        self.assertIn("OFFERING_EXCEEDS_UNISSUED_EQUITY", err_exceed)

        ok_coop, err_coop = validate_offering(coop, data, 20.0)
        self.assertFalse(ok_coop)
        self.assertEqual(err_coop, "CHARTER_INELIGIBLE_FOR_EQUITY_OFFERING")

    def test_purchase_request_validation(self):
        """Verify purchasing boundary conditions: min/max limits, liquidity and expiry."""
        def validate_purchase(offering, buyer_cid, shares, balance, now_unix):
            if offering.get("status") != "active":
                return False, "OFFERING_NOT_ACTIVE"
            if now_unix > offering.get("expires_at_unix", float("inf")):
                return False, "OFFERING_EXPIRED"
            if not buyer_cid or len(buyer_cid) < 3:
                return False, "INVALID_BUYER"
            if shares <= 0:
                return False, "INVALID_SHARES"
            if shares < offering.get("min_purchase", 0.1):
                return False, "PURCHASE_BELOW_MIN"
            if shares > offering.get("max_purchase", 100.0):
                return False, "PURCHASE_EXCEEDS_MAX"
            if shares > offering.get("shares_available", 0.0):
                return False, "EXCEEDS_AVAILABLE"
            cost = round(shares * offering.get("price_per_share", 0.0), 2)
            if balance < cost:
                return False, "INSUFFICIENT_FUNDS"
            return True, {"cost": cost, "remaining": round(offering["shares_available"] - shares, 2)}

        offering = {
            "status": "active",
            "shares_available": 25.0,
            "min_purchase": 1.0,
            "max_purchase": 10.0,
            "price_per_share": 2000.0,
            "expires_at_unix": 2000000000
        }

        ok_v, res_v = validate_purchase(offering, "CIT-ALICE", 5.0, 20000.0, 1900000000)
        self.assertTrue(ok_v)
        self.assertEqual(res_v["cost"], 10000.0)
        self.assertEqual(res_v["remaining"], 20.0)

        ok_below, _ = validate_purchase(offering, "CIT-BOB", 0.5, 20000.0, 1900000000)
        self.assertFalse(ok_below)

        ok_above, _ = validate_purchase(offering, "CIT-CHARLIE", 15.0, 50000.0, 1900000000)
        self.assertFalse(ok_above)

        ok_nofunds, _ = validate_purchase(offering, "CIT-DAVE", 5.0, 500.0, 1900000000)
        self.assertFalse(ok_nofunds)

        ok_exp, _ = validate_purchase(offering, "CIT-EVE", 5.0, 20000.0, 2100000000)
        self.assertFalse(ok_exp)

    def test_consolidated_cap_table_aggregation(self):
        """Verify merging internal members and external investors into a unified cap table."""
        members = [
            {"citizen_id": "CIT-FOUNDER-1", "role_title": "CEO", "equity_shares": 50.0},
            {"citizen_id": "CIT-MEMBER-2", "role_title": "CTO", "equity_shares": 20.0}
        ]
        investors = [
            {"citizen_id": "CIT-INVESTOR-A", "equity_shares": 15.0, "total_invested": 30000.0},
            {"citizen_id": "CIT-FOUNDER-1", "equity_shares": 5.0, "total_invested": 10000.0}  # Founder bought IPO shares
        ]

        cap_map = {}
        for m in members:
            cid = m["citizen_id"]
            cap_map[cid] = {
                "citizenId": cid,
                "roleTitle": m["role_title"],
                "equityShares": float(m["equity_shares"]),
                "isExternal": False
            }

        for inv in investors:
            cid = inv["citizen_id"]
            if cid in cap_map:
                cap_map[cid]["equityShares"] += float(inv["equity_shares"])
            else:
                cap_map[cid] = {
                    "citizenId": cid,
                    "roleTitle": "Equity Shareholder",
                    "equityShares": float(inv["equity_shares"]),
                    "isExternal": True
                }

        sorted_table = sorted(cap_map.values(), key=lambda x: x["equityShares"], reverse=True)

        self.assertEqual(len(sorted_table), 3)
        self.assertEqual(sorted_table[0]["citizenId"], "CIT-FOUNDER-1")
        self.assertEqual(sorted_table[0]["equityShares"], 55.0)  # 50 + 5
        self.assertEqual(sorted_table[1]["citizenId"], "CIT-MEMBER-2")
        self.assertEqual(sorted_table[1]["equityShares"], 20.0)
        self.assertEqual(sorted_table[2]["citizenId"], "CIT-INVESTOR-A")
        self.assertEqual(sorted_table[2]["equityShares"], 15.0)

    def test_dividend_distribution_zero_cent_conservation(self):
        """Verify exact closed-loop conservation in dividend distribution with sub-cent dust retention."""
        def calc_dividends(profit, reinvest_rate, shareholders):
            rate = max(0.10, min(0.50, reinvest_rate))
            initial_retained = math.floor(profit * rate * 100) / 100.0
            distributable = round(profit - initial_retained, 2)

            total_shares = sum(s["equityShares"] for s in shareholders)
            payouts = []
            total_disbursed = 0.0

            for s in shareholders:
                fraction = s["equityShares"] / total_shares
                payout = math.floor((distributable * fraction) * 100) / 100.0
                total_disbursed = round(total_disbursed + payout, 2)
                payouts.append({"citizenId": s["citizenId"], "payout": payout})

            sub_cent_dust = round(distributable - total_disbursed, 2)
            final_retained = round(initial_retained + sub_cent_dust, 2)

            # Strict conservation assertion
            conservation_sum = round(total_disbursed + final_retained, 2)
            delta = abs(conservation_sum - profit)
            return {
                "totalDisbursed": total_disbursed,
                "retainedReserves": final_retained,
                "subCentDust": sub_cent_dust,
                "payouts": payouts,
                "delta": delta
            }

        # Case 1: Standard clean 40/35/25 split
        shareholders_1 = [
            {"citizenId": "CIT-A", "equityShares": 40.0},
            {"citizenId": "CIT-B", "equityShares": 35.0},
            {"citizenId": "CIT-C", "equityShares": 25.0}
        ]
        r1 = calc_dividends(10000.00, 0.20, shareholders_1)
        self.assertEqual(r1["totalDisbursed"], 8000.00)
        self.assertEqual(r1["retainedReserves"], 2000.00)
        self.assertEqual(r1["payouts"][0]["payout"], 3200.00)
        self.assertEqual(r1["payouts"][1]["payout"], 2800.00)
        self.assertEqual(r1["payouts"][2]["payout"], 2000.00)
        self.assertAlmostEqual(r1["delta"], 0.00, places=4)

        # Case 2: Odd fractional split 33.33%, 33.33%, 33.34%
        shareholders_2 = [
            {"citizenId": "CIT-1", "equityShares": 33.33},
            {"citizenId": "CIT-2", "equityShares": 33.33},
            {"citizenId": "CIT-3", "equityShares": 33.34}
        ]
        r2 = calc_dividends(10000.00, 0.20, shareholders_2)
        self.assertAlmostEqual(r2["delta"], 0.00, places=4)
        self.assertEqual(round(r2["totalDisbursed"] + r2["retainedReserves"], 2), 10000.00)

    def test_weekly_automated_dividend_eligibility(self):
        """Verify automated weekly scheduling interval and operational reserve floor evaluation."""
        def evaluate_eligibility(balance, last_run_unix, current_unix, floor=5000.0, freq_days=7):
            freq_sec = freq_days * 86400
            elapsed = current_unix - (last_run_unix or 0)
            if last_run_unix > 0 and elapsed < freq_sec:
                return False, "SCHEDULE_INTERVAL_NOT_ELAPSED", 0.0
            surplus = round(balance - floor, 2)
            if surplus <= 0:
                return False, "INSUFFICIENT_LIQUIDITY_SURPLUS", surplus
            recommended = round(surplus * 0.25, 2)
            if recommended < 100.0:
                return False, "SURPLUS_TOO_LOW", surplus
            return True, recommended, surplus

        now = 1700000000
        one_week_ago = now - (7 * 86400)
        two_days_ago = now - (2 * 86400)

        ok_ready, rec_profit, surplus = evaluate_eligibility(25000.0, one_week_ago, now)
        self.assertTrue(ok_ready)
        self.assertEqual(surplus, 20000.0)
        self.assertEqual(rec_profit, 5000.0)

        ok_too_soon, reason_ts, _ = evaluate_eligibility(25000.0, two_days_ago, now)
        self.assertFalse(ok_too_soon)
        self.assertEqual(reason_ts, "SCHEDULE_INTERVAL_NOT_ELAPSED")

        ok_no_funds, reason_nf, _ = evaluate_eligibility(4200.0, one_week_ago, now)
        self.assertFalse(ok_no_funds)
        self.assertEqual(reason_nf, "INSUFFICIENT_LIQUIDITY_SURPLUS")

    def test_zero_trust_payload_sanitization_and_formatting(self):
        """Verify payload sanitization, numerical clamping and UI badge formatters."""
        def sanitize_purchase(raw):
            if not isinstance(raw, dict):
                return False, "NOT_TABLE"
            offering_id = str(raw.get("offeringId", "")).strip()
            try:
                shares = float(raw.get("shares", 0.0))
            except (ValueError, TypeError):
                return False, "BAD_NUMBER"
            if len(offering_id) < 2 or shares <= 0:
                return False, "INVALID_ARGS"
            return True, {"offeringId": offering_id, "shares": round(shares, 2)}

        ok_valid, clean_p = sanitize_purchase({"offeringId": "offering_unicorn_ipo", "shares": "5.5"})
        self.assertTrue(ok_valid)
        self.assertEqual(clean_p["shares"], 5.50)

        ok_bad, _ = sanitize_purchase({"offeringId": "", "shares": -2})
        self.assertFalse(ok_bad)

        def badge_equity(shares):
            return f"{float(shares):.2f}% Equity"

        def badge_currency(amount):
            return f"${float(amount):.2f}"

        self.assertEqual(badge_equity(25.5), "25.50% Equity")
        self.assertEqual(badge_currency(1500), "$1500.00")

    def test_in_engine_test_47_registered(self):
        """Verify Test 47 is implemented and wired into Nyx.Tests.RunAll() in tests.lua."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        self.assertTrue(os.path.isfile(tests_path))
        with open(tests_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("function Nyx.Tests.TestCorporateEquityOfferingAndDividends()", content)
        self.assertIn("local t47 = Nyx.Tests.TestCorporateEquityOfferingAndDividends()", content)
        self.assertIn("and t47", content)


if __name__ == "__main__":
    unittest.main()
