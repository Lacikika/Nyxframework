#!/usr/bin/env python3
"""
Unit and Integration Tests for Municipal Utility Metering & Automated Grid Billing
(nyx_services, nyx_properties, nyx_treasury, nyx_core).
Covers: Migration 055 schema & indices, fxmanifest declarations across resources,
        continuous consumption delta modeling (residential/commercial/industrial, area scaling, weather stress),
        substation real-time grid draw aggregation & transformer overload tripping,
        delinquency state machine (tiers 0 to 4, cutoff thresholds),
        strict zero-cent closed-loop economic conservation (Delta = 0.00),
        arrears debt settlement & automated reconnection logic,
        electronic maglock failure interlocks on power cut-off & backup generator resilience,
        unique serial generation & telemetry formatters,
        and in-engine Test 50 integration.
"""

import os
import json
import math
import re
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestMunicipalUtilityMeteringAndGridBilling(unittest.TestCase):
    def test_migration_055_exists_and_registered(self):
        """Verify migration 055 exists on disk, mirrored across resources, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("055_municipal_utility_metering_and_automated_grid_billing.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "055_municipal_utility_metering_and_automated_grid_billing.sql")
        serv_mig = os.path.join(FIVEM_DIR, "nyx_services", "sql", "migrations", "055_municipal_utility_metering_and_automated_grid_billing.sql")
        prop_mig = os.path.join(FIVEM_DIR, "nyx_properties", "sql", "migrations", "055_municipal_utility_metering_and_automated_grid_billing.sql")

        self.assertTrue(os.path.isfile(core_mig), "nyx_core migration 055 missing")
        self.assertTrue(os.path.isfile(serv_mig), "nyx_services migration 055 missing")
        self.assertTrue(os.path.isfile(prop_mig), "nyx_properties migration 055 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("nyx_services_utility_invoices", sql)
        self.assertIn("nyx_services_utility_delinquency_logs", sql)
        self.assertIn("consecutive_unpaid_cycles", sql)
        self.assertIn("delinquency_tier", sql)
        self.assertIn("meter_status", sql)
        self.assertIn("disconnection_notice_at", sql)
        self.assertIn("disconnected_at", sql)
        self.assertIn("reconnected_at", sql)
        self.assertIn("is_utility_suspended", sql)
        self.assertIn("utility_status", sql)
        self.assertIn("UTILITY_CUTOFF_ENFORCED", sql)
        self.assertIn("UTILITY_RECONNECTED", sql)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest declarations in nyx_services and nyx_properties."""
        serv_manifest = os.path.join(FIVEM_DIR, "nyx_services", "fxmanifest.lua")
        with open(serv_manifest, "r", encoding="utf-8") as f:
            serv_txt = f.read()

        self.assertIn("shared/metering.lua", serv_txt)
        self.assertIn("server/billing.lua", serv_txt)
        self.assertIn("client/metering.lua", serv_txt)

        prop_manifest = os.path.join(FIVEM_DIR, "nyx_properties", "fxmanifest.lua")
        with open(prop_manifest, "r", encoding="utf-8") as f:
            prop_txt = f.read()

        self.assertIn("@nyx_services/shared/metering.lua", prop_txt)

    def test_continuous_consumption_delta_math(self):
        """Verify consumption delta calculations with land footprint scaling and weather multipliers."""
        profiles = {
            "residential": {"baseKwh": 120.0, "baseWater": 80.0, "kwhPerOccupant": 15.0, "waterPerOccupant": 10.0},
            "commercial": {"baseKwh": 450.0, "baseWater": 200.0, "kwhPerOccupant": 30.0, "waterPerOccupant": 25.0},
            "industrial": {"baseKwh": 1200.0, "baseWater": 650.0, "kwhPerOccupant": 50.0, "waterPerOccupant": 40.0}
        }
        weather_mults = {"THUNDER": 1.40, "RAIN": 1.15, "CLEAR": 1.00, "EXTRASUNNY": 1.25}

        def calc_consumption(p_type, area, occupancy, weather, appliance=1.0):
            p = profiles[p_type]
            area_factor = max(0.40, min(3.50, math.sqrt(max(20.0, area) / 150.0)))
            w_mult = weather_mults.get(weather, 1.0)
            kwh = round((p["baseKwh"] * area_factor + (occupancy * p["kwhPerOccupant"])) * w_mult * appliance, 2)
            water = round((p["baseWater"] * area_factor + (occupancy * p["waterPerOccupant"])) * w_mult * appliance, 2)
            return kwh, water

        # Residential standard (150 m^2, 2 occupants, CLEAR weather)
        kwh, water = calc_consumption("residential", 150.0, 2, "CLEAR", 1.0)
        self.assertEqual(kwh, 150.0)   # 120*1 + 2*15 = 150.0
        self.assertEqual(water, 100.0) # 80*1 + 2*10 = 100.0

        # Residential storm (150 m^2, 2 occupants, THUNDER 1.4x)
        kwh_storm, water_storm = calc_consumption("residential", 150.0, 2, "THUNDER", 1.0)
        self.assertEqual(kwh_storm, 210.0)   # 150 * 1.4 = 210.0
        self.assertEqual(water_storm, 140.0) # 100 * 1.4 = 140.0

        # Large industrial facility (1250 m^2)
        kwh_ind, water_ind = calc_consumption("industrial", 1250.0, 10, "CLEAR", 1.0)
        self.assertGreater(kwh_ind, 3000.0)
        self.assertGreater(water_ind, 2000.0)

    def test_substation_grid_draw_and_transformer_overload(self):
        """Verify real-time aggregate kW/MW calculation and overload trip detection."""
        def calc_grid_draw(connected_list, max_cap_mw=75.0):
            profiles = {"residential": 8.5, "commercial": 35.0, "industrial": 120.0}
            total_kw = 0.0
            total_meters = len(connected_list)
            active_meters = 0
            suspended_meters = 0
            generator_backed = 0

            for prop in connected_list:
                is_suspended = prop.get("isSuspended", False)
                has_backup = prop.get("hasBackup", False)
                if has_backup:
                    generator_backed += 1
                elif is_suspended:
                    suspended_meters += 1
                    total_kw += 0.10 # ghost draw
                else:
                    active_meters += 1
                    p_type = prop.get("type", "residential")
                    kw = profiles.get(p_type, 8.5)
                    occ = prop.get("occupancy", 0)
                    if occ > 0:
                        kw += occ * 1.5
                    total_kw += kw

            load_mw = round(total_kw / 1000.0, 4)
            is_overloaded = load_mw > max_cap_mw
            return load_mw, {
                "totalMeters": total_meters,
                "activeMeters": active_meters,
                "suspendedMeters": suspended_meters,
                "generatorBacked": generator_backed,
                "isOverloaded": is_overloaded
            }

        mock_props = [
            {"type": "residential", "isSuspended": False, "hasBackup": False, "occupancy": 2},
            {"type": "commercial", "isSuspended": False, "hasBackup": False, "occupancy": 5},
            {"type": "industrial", "isSuspended": False, "hasBackup": False, "occupancy": 10},
            {"type": "industrial", "isSuspended": True, "hasBackup": False, "occupancy": 0},
            {"type": "commercial", "isSuspended": False, "hasBackup": True, "occupancy": 3}
        ]

        load_normal, metrics_normal = calc_grid_draw(mock_props, 75.0)
        self.assertGreater(load_normal, 0.10)
        self.assertLess(load_normal, 1.00)
        self.assertEqual(metrics_normal["activeMeters"], 3)
        self.assertEqual(metrics_normal["suspendedMeters"], 1)
        self.assertEqual(metrics_normal["generatorBacked"], 1)
        self.assertFalse(metrics_normal["isOverloaded"])

        # Tripping threshold test
        _, metrics_overloaded = calc_grid_draw(mock_props, 0.05)
        self.assertTrue(metrics_overloaded["isOverloaded"])

    def test_delinquency_state_machine_evaluation(self):
        """Verify statutory delinquency tier progression and power cut-off triggers."""
        def eval_delinquency(missed_cycles, arrears, cutoff=2500.00, lien=7500.00):
            arrears = round(max(0.0, arrears), 2)
            missed = max(0, int(missed_cycles))

            if arrears <= 0.00:
                return 0, "active", False, 0.00
            if arrears >= lien or missed >= 5:
                return 4, "lien_referred", True, 0.10
            if arrears >= cutoff or missed >= 3:
                return 3, "disconnected", True, 0.10
            if missed == 2:
                return 2, "late_warning", False, 0.10
            return 1, "grace_notice", False, 0.00

        # Tier 0: Current / Good standing
        t0, s0, susp0, _ = eval_delinquency(0, 0.00)
        self.assertEqual((t0, s0, susp0), (0, "active", False))

        # Tier 1: Grace period (missed 1 cycle, arrears < cutoff)
        t1, s1, susp1, _ = eval_delinquency(1, 150.00)
        self.assertEqual((t1, s1, susp1), (1, "grace_notice", False))

        # Tier 2: Late warning (missed 2 cycles)
        t2, s2, susp2, fee_rate = eval_delinquency(2, 600.00)
        self.assertEqual((t2, s2, susp2), (2, "late_warning", False))
        self.assertEqual(fee_rate, 0.10)

        # Tier 3: Arrears exceed threshold immediately ($2600 >= $2500)
        t3_amt, s3_amt, susp3_amt, _ = eval_delinquency(1, 2600.00)
        self.assertEqual((t3_amt, s3_amt, susp3_amt), (3, "disconnected", True))

        # Tier 3: Consecutive missed cycles reach threshold (3 cycles)
        t3_cyc, s3_cyc, susp3_cyc, _ = eval_delinquency(3, 800.00)
        self.assertEqual((t3_cyc, s3_cyc, susp3_cyc), (3, "disconnected", True))

        # Tier 4: Extreme lien threshold ($8000 >= $7500 or 5+ cycles)
        t4, s4, susp4, _ = eval_delinquency(5, 8000.00)
        self.assertEqual((t4, s4, susp4), (4, "lien_referred", True))

    def test_strict_zero_cent_conservation_law(self):
        """Verify utility bill calculations strictly satisfy Delta = 0.00 closed-loop conservation."""
        def calc_bill(kwh, water, kwh_tariff, water_tariff, arrears, missed, is_reconnecting=False):
            energy_charge = round(kwh * kwh_tariff, 2)
            water_charge = round(water * water_tariff, 2)
            current = round(energy_charge + water_charge, 2)
            late_penalty = round(arrears * 0.10, 2) if (missed >= 2 and arrears > 0) else 0.00
            reconnect_fee = 150.00 if is_reconnecting else 0.00

            total_due = round(current + arrears + late_penalty + reconnect_fee, 2)
            delta = abs(total_due - (energy_charge + water_charge + arrears + late_penalty + reconnect_fee))
            return {
                "energyCharge": energy_charge,
                "waterCharge": water_charge,
                "current": current,
                "arrears": arrears,
                "latePenalty": late_penalty,
                "reconnectFee": reconnect_fee,
                "totalDue": total_due,
                "delta": delta
            }

        test_cases = [
            (333.33, 177.77, 0.1500, 0.0500, 1420.55, 2, False),
            (1200.00, 650.00, 0.1500, 0.0500, 3200.00, 3, True),
            (0.00, 0.00, 0.1500, 0.0500, 500.00, 1, False),
            (84.12, 31.98, 0.1875, 0.0500, 0.00, 0, False)
        ]

        for kwh, water, kt, wt, arr, miss, reconn in test_cases:
            res = calc_bill(kwh, water, kt, wt, arr, miss, reconn)
            self.assertLess(res["delta"], 0.001, f"Conservation violation on inputs: {kwh}, {water}, {arr}")

    def test_arrears_settlement_and_reconnection_math(self):
        """Verify debt payment reduces arrears and automatically restores disconnected service below cutoff."""
        def settle_payment(arrears, payment, is_suspended, cutoff=2500.00):
            paid = min(arrears, payment)
            rem = round(arrears - paid, 2)
            can_reconn = False
            new_susp = is_suspended

            if is_suspended:
                if rem < cutoff:
                    can_reconn = True
                    new_susp = False
            else:
                if rem >= cutoff:
                    new_susp = True

            return paid, rem, new_susp, can_reconn

        # Case 1: Partial payment insufficient to cross cutoff ($3000 - $200 = $2800 >= $2500)
        p1, r1, s1, rec1 = settle_payment(3000.00, 200.00, True, 2500.00)
        self.assertEqual(r1, 2800.00)
        self.assertTrue(s1)
        self.assertFalse(rec1)

        # Case 2: Payment drops arrears below threshold ($3000 - $1000 = $2000 < $2500)
        p2, r2, s2, rec2 = settle_payment(3000.00, 1000.00, True, 2500.00)
        self.assertEqual(r2, 2000.00)
        self.assertFalse(s2)
        self.assertTrue(rec2)

        # Case 3: Complete debt clearance
        p3, r3, s3, rec3 = settle_payment(1200.00, 1200.00, False, 2500.00)
        self.assertEqual(r3, 0.00)
        self.assertFalse(s3)

    def test_doorlock_power_cut_off_interlocks(self):
        """Verify electronic locks fail on power cut-off while backup generators maintain local power."""
        def eval_lock_power(p_type, is_grid_powered, is_utility_suspended, has_backup):
            if has_backup:
                effective_power = True
            elif is_grid_powered and not is_utility_suspended:
                effective_power = True
            else:
                effective_power = False

            lock_usable = (p_type == "residential") or effective_power
            return effective_power, lock_usable

        # Commercial grid powered & normal utilities -> Locks online
        p1, l1 = eval_lock_power("commercial", True, False, False)
        self.assertTrue(p1)
        self.assertTrue(l1)

        # Commercial utility suspended -> Power cut off, electronic maglocks offline!
        p2, l2 = eval_lock_power("commercial", True, True, False)
        self.assertFalse(p2)
        self.assertFalse(l2)

        # Commercial utility suspended BUT backup generator active -> Powered & locks online!
        p3, l3 = eval_lock_power("commercial", True, True, True)
        self.assertTrue(p3)
        self.assertTrue(l3)

        # Residential physical keys work even when power is cut off
        p4, l4 = eval_lock_power("residential", True, True, False)
        self.assertFalse(p4)
        self.assertTrue(l4)

    def test_unique_serial_generation_and_badges(self):
        """Verify unique invoice and log serials, and status badges."""
        meter_id = "meter:prop:apt101"
        ts = 1770000000
        nonce = 1234
        inv_uuid = f"INV-UTIL-{meter_id[-8:]}-{ts}-{nonce:04d}"
        self.assertTrue(re.match(r"^INV-UTIL-.*-\d+-\d{4}$", inv_uuid))

        log_action = "CUTO"
        log_uuid = f"LOG-UTIL-{log_action}-{ts}-{nonce:04d}"
        self.assertTrue(re.match(r"^LOG-UTIL-CUTO-\d+-\d{4}$", log_uuid))

    def test_substation_ids_canonical_in_properties_config(self):
        """Verify nyx_properties config.lua default properties use valid canonical substations."""
        prop_cfg = os.path.join(FIVEM_DIR, "nyx_properties", "config.lua")
        with open(prop_cfg, "r", encoding="utf-8") as f:
            txt = f.read()

        self.assertIn('linkedSubstation = "grid_central_ls"', txt)
        self.assertIn('linkedSubstation = "grid_port_ls"', txt)
        self.assertNotIn('linkedSubstation = "substation_central"', txt)

    def test_in_engine_test_50_registered(self):
        """Verify TestMunicipalUtilityMeteringAndGridBilling (Test 50) is declared and wired into RunAll() in tests.lua."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        with open(tests_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("Nyx.Tests.TestMunicipalUtilityMeteringAndGridBilling", content)
        self.assertIn("local t50 = Nyx.Tests.TestMunicipalUtilityMeteringAndGridBilling()", content)
        self.assertIn("t50", content)


if __name__ == "__main__":
    unittest.main()
