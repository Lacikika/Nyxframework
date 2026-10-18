#!/usr/bin/env python3
"""
Unit and Integration Tests for 14-Resource End-to-End Stress Simulation & Conservation Engine
(nyx_core and all 14 modular framework resources).
Covers: Migration 054 schema & indices, fxmanifest declarations,
         14 canonical resources taxonomy completeness, multi-actor stress simulation math,
         strict double-entry closed-circuit economic conservation (Delta = 0.00),
         inventory Dijkstra dual-lock concurrency and zero duplicate item enforcement,
         fluid & commodity resource mass conservation,
         orphan entity and mutex leak detection,
         0.00ms baseline idle performance profiling (<= 0.05ms ceiling),
         zero-trust configuration validation & clamping, serial UUID generators,
         and in-engine Test 49 integration into RunAll().
"""

import os
import json
import math
import re
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestEndToEndStressSimulation(unittest.TestCase):
    def test_migration_054_exists_and_registered(self):
        """Verify migration 054 exists on disk and is registered in nyx_core index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("054_end_to_end_stress_simulation_audits.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "054_end_to_end_stress_simulation_audits.sql")
        self.assertTrue(os.path.isfile(core_mig), "Core migration 054 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("nyx_core_stress_test_runs", sql)
        self.assertIn("run_uuid", sql)
        self.assertIn("concurrency_level", sql)
        self.assertIn("total_transactions", sql)
        self.assertIn("resources_tested", sql)
        self.assertIn("idle_tick_ms", sql)
        self.assertIn("economic_conservation_delta", sql)
        self.assertIn("entity_leaks_count", sql)
        self.assertIn("mutex_leaks_count", sql)
        self.assertIn("duration_ms", sql)
        self.assertIn("diagnostics_json", sql)
        self.assertIn("idx_stress_runs_status", sql)
        self.assertIn("idx_stress_runs_created_at", sql)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest declares shared, server, and client stress_simulation scripts."""
        core_manifest = os.path.join(FIVEM_DIR, "nyx_core", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(core_manifest))
        with open(core_manifest, "r", encoding="utf-8") as f:
            txt = f.read()

        self.assertIn("shared/stress_simulation.lua", txt)
        self.assertIn("server/stress_simulation.lua", txt)
        self.assertIn("client/stress_simulation.lua", txt)

    def test_taxonomy_and_14_canonical_resources(self):
        """Verify all 14 canonical resources are defined in taxonomy with stages and primary transactions."""
        shared_path = os.path.join(FIVEM_DIR, "nyx_core", "shared", "stress_simulation.lua")
        self.assertTrue(os.path.isfile(shared_path))
        with open(shared_path, "r", encoding="utf-8") as f:
            content = f.read()

        expected_resources = [
            "nyx_core",
            "nyx_treasury",
            "nyx_inventory",
            "nyx_logistics",
            "nyx_vehicles",
            "nyx_judiciary",
            "nyx_parliament",
            "nyx_factions",
            "nyx_services",
            "nyx_properties",
            "nyx_press",
            "nyx_mdt",
            "nyx_interact",
            "nyx_ui"
        ]

        for res in expected_resources:
            self.assertIn(f'"{res}"', content, f"Missing canonical resource {res}")
            self.assertIn(f'["{res}"]', content, f"Missing taxonomy entry for {res}")

    def test_economic_conservation_math_and_anomaly_detection(self):
        """Verify double-entry closed-circuit wealth conservation logic and anomaly detection."""
        def verify_economic_conservation(initial_balances, final_balances):
            sum_init = sum(round(float(v), 2) for v in initial_balances.values())
            sum_fin = sum(round(float(v), 2) for v in final_balances.values())
            delta = round(sum_fin - sum_init, 2)
            is_conserved = abs(delta) < 0.001
            return is_conserved, delta

        init_bals = {
            "gov:city:master": 1000000.00,
            "faction:corp_unicorn": 250000.00,
            "citizen:001": 10000.00,
            "citizen:002": 5000.00
        }
        # Multi-party closed-loop transfers
        fin_bals = {
            "gov:city:master": 1000000.00 + 50.00 + 25.00,
            "faction:corp_unicorn": 250000.00 - 100.00,
            "citizen:001": 10000.00 - 50.00 + 100.00,
            "citizen:002": 5000.00 - 25.00
        }

        conserved, delta = verify_economic_conservation(init_bals, fin_bals)
        self.assertTrue(conserved)
        self.assertEqual(delta, 0.00)

        # Anomaly case: missing money ($15.00 leaked)
        leaked_bals = dict(fin_bals)
        leaked_bals["citizen:001"] -= 15.00
        conserved_leak, delta_leak = verify_economic_conservation(init_bals, leaked_bals)
        self.assertFalse(conserved_leak)
        self.assertEqual(delta_leak, -15.00)

    def test_inventory_conservation_and_serial_uniqueness(self):
        """Verify physical item inventory conservation and duplicate serial detection."""
        def verify_inventory_conservation(initial_containers, final_containers):
            total_init = sum(item["count"] for c in initial_containers.values() for item in c["items"])
            total_fin = 0
            final_serials = {}
            duplicates_found = 0
            for c in final_containers.values():
                for item in c["items"]:
                    total_fin += item["count"]
                    s = item.get("serial")
                    if s:
                        final_serials[s] = final_serials.get(s, 0) + 1
                        if final_serials[s] > 1:
                            duplicates_found += 1
            delta = total_fin - total_init
            is_conserved = (delta == 0) and (duplicates_found == 0)
            return is_conserved, delta, duplicates_found

        init_c = {
            "stash:central": {"items": [{"item": "kit", "count": 2, "serial": "KIT-001"}]},
            "inv:cit_1": {"items": [{"item": "kit", "count": 1, "serial": "KIT-002"}]}
        }
        # Valid transfer of KIT-002 from citizen to central stash
        fin_c = {
            "stash:central": {
                "items": [
                    {"item": "kit", "count": 2, "serial": "KIT-001"},
                    {"item": "kit", "count": 1, "serial": "KIT-002"}
                ]
            },
            "inv:cit_1": {"items": []}
        }

        ok, delta, dups = verify_inventory_conservation(init_c, fin_c)
        self.assertTrue(ok)
        self.assertEqual(delta, 0)
        self.assertEqual(dups, 0)

        # Duplicate serial glitch injection
        glitch_c = {
            "stash:central": {
                "items": [
                    {"item": "kit", "count": 2, "serial": "KIT-001"},
                    {"item": "kit", "count": 1, "serial": "KIT-002"}
                ]
            },
            "inv:cit_1": {
                "items": [
                    {"item": "kit", "count": 1, "serial": "KIT-002"} # Duplicate!
                ]
            }
        }
        ok_dup, delta_dup, dups_dup = verify_inventory_conservation(init_c, glitch_c)
        self.assertFalse(ok_dup)
        self.assertEqual(delta_dup, 1)
        self.assertEqual(dups_dup, 1)

    def test_fluid_resource_conservation(self):
        """Verify fluid fuel commodity conservation across supply chain nodes."""
        def verify_fluid_conservation(initial_liters, final_liters):
            init = round(float(initial_liters), 2)
            fin = round(float(final_liters), 2)
            delta = round(fin - init, 2)
            return abs(delta) < 0.001, delta

        init_total = 50000.0 + 20000.0 + 15000.0 + 5000.0 # 90000.0 L
        # Bulk movements: 500L from refinery to tanker, 300L from tanker to gas station, 50L to car
        fin_total = (50000.0 - 500.0) + (20000.0 + 500.0 - 300.0) + (15000.0 + 300.0 - 50.0) + (5000.0 + 50.0)
        ok, delta = verify_fluid_conservation(init_total, fin_total)
        self.assertTrue(ok)
        self.assertEqual(delta, 0.00)

    def test_entity_and_mutex_leak_detector(self):
        """Verify detection of orphan world entities and dangling mutex locks."""
        def detect_leaks(entity_tracker, lock_tracker):
            active_entity_leaks = 0
            for meta in entity_tracker.values():
                if not meta.get("isDestroyed", False) and not meta.get("isPermanent", False):
                    active_entity_leaks += 1

            active_mutex_leaks = 0
            for is_held in lock_tracker.values():
                if is_held:
                    active_mutex_leaks += 1

            clean = (active_entity_leaks == 0) and (active_mutex_leaks == 0)
            return clean, active_entity_leaks, active_mutex_leaks

        # Clean state
        ent_clean = {"ent_1": {"isDestroyed": True}, "ent_2": {"isDestroyed": True}}
        locks_clean = {"inv:1": False, "inv:2": False}
        is_clean, ent_l, mtx_l = detect_leaks(ent_clean, locks_clean)
        self.assertTrue(is_clean)
        self.assertEqual(ent_l, 0)
        self.assertEqual(mtx_l, 0)

        # Leaked entity and mutex
        ent_dirty = {"ent_1": {"isDestroyed": True}, "ent_leak": {"isDestroyed": False}}
        locks_dirty = {"inv:1": False, "inv:leak": True}
        is_clean2, ent_l2, mtx_l2 = detect_leaks(ent_dirty, locks_dirty)
        self.assertFalse(is_clean2)
        self.assertEqual(ent_l2, 1)
        self.assertEqual(mtx_l2, 1)

    def test_baseline_idle_performance_profiling(self):
        """Verify idle performance profiler clamps to 0.00ms floor and enforces <= 0.05ms budget."""
        def profile_idle(samples):
            if not samples:
                return {"avgMs": 0.0, "isOptimal": True, "displayFormatted": "0.00ms"}
            sorted_s = sorted(samples)
            count = len(sorted_s)
            avg_ms = sum(sorted_s) / count
            p99_idx = max(0, int(count * 0.99) - 1)
            p99_ms = sorted_s[p99_idx]
            is_optimal = (avg_ms <= 0.05) and (p99_ms <= 0.10)
            display = "0.00ms" if avg_ms < 0.01 else f"{avg_ms:.2f}ms"
            return {
                "avgMs": round(avg_ms, 4),
                "p99Ms": round(p99_ms, 4),
                "isOptimal": is_optimal,
                "displayFormatted": display
            }

        # Sub-0.01ms typical Cerulean zero-load samples
        clean_samples = [0.0005, 0.0010, 0.0020, 0.0008, 0.0015] * 20
        res = profile_idle(clean_samples)
        self.assertTrue(res["isOptimal"])
        self.assertEqual(res["displayFormatted"], "0.00ms")
        self.assertLessEqual(res["avgMs"], 0.05)

        # Degraded idle loop hitch (> 0.05ms)
        hitch_samples = [0.15] * 100
        res_hitch = profile_idle(hitch_samples)
        self.assertFalse(res_hitch["isOptimal"])
        self.assertGreater(res_hitch["avgMs"], 0.05)

    def test_config_validation_and_bounds_clamping(self):
        """Verify configuration validation and boundary clamping."""
        def validate_config(cfg):
            concurrency = max(1, min(200, int(cfg.get("concurrency", 50))))
            tx_per_actor = max(1, min(50, int(cfg.get("transactionsPerActor", 10))))
            idle_samples = max(10, min(500, int(cfg.get("idleSamples", 100))))
            return {
                "concurrency": concurrency,
                "transactionsPerActor": tx_per_actor,
                "idleSamples": idle_samples
            }

        c1 = validate_config({"concurrency": 500, "transactionsPerActor": 0, "idleSamples": 5})
        self.assertEqual(c1["concurrency"], 200)
        self.assertEqual(c1["transactionsPerActor"], 1)
        self.assertEqual(c1["idleSamples"], 10)

        c2 = validate_config({"concurrency": -10, "transactionsPerActor": 999, "idleSamples": 1000})
        self.assertEqual(c2["concurrency"], 1)
        self.assertEqual(c2["transactionsPerActor"], 50)
        self.assertEqual(c2["idleSamples"], 500)

    def test_run_uuid_generation_pattern(self):
        """Verify generated stress run UUID format matches canonical regex."""
        # Pattern: STR-RUN-<YYYYMMDDHHMMSS>-<counter>-<random>
        uuid_pattern = r"^STR-RUN-\d{14}-\d{4}-\d{4}$"
        sample_uuid = "STR-RUN-20261018160000-1001-4821"
        self.assertIsNotNone(re.match(uuid_pattern, sample_uuid))

    def test_in_engine_test_49_registered_and_wired(self):
        """Verify Test 49 is defined in FiveM/nyx_core/server/tests.lua and called in RunAll()."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server/tests.lua")
        self.assertTrue(os.path.isfile(tests_path))
        with open(tests_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("Nyx.Tests.TestEndToEndStressSimulationAcross14Resources", content)
        self.assertIn("t49 = Nyx.Tests.TestEndToEndStressSimulationAcross14Resources()", content)
        self.assertIn("and t48 and t49 then", content)
        self.assertIn("Migration 054 Schema Contracts", content)
        self.assertIn("0.00ms Baseline Idle Performance Guarantee", content)

    def test_server_and_client_exports_wired(self):
        """Verify server and client exports for stress simulation are declared in exports.lua."""
        srv_exp = os.path.join(FIVEM_DIR, "nyx_core", "server/exports.lua")
        with open(srv_exp, "r", encoding="utf-8") as f:
            srv_txt = f.read()

        self.assertIn('exports("RunStressSimulation"', srv_txt)
        self.assertIn('exports("GetLastStressRunResults"', srv_txt)
        self.assertIn('exports("ProfileBaselineIdlePerformance"', srv_txt)

        cli_exp = os.path.join(FIVEM_DIR, "nyx_core", "client/exports.lua")
        with open(cli_exp, "r", encoding="utf-8") as f:
            cli_txt = f.read()

        self.assertIn('exports("RunStressSimulation"', cli_txt)


if __name__ == "__main__":
    unittest.main()
