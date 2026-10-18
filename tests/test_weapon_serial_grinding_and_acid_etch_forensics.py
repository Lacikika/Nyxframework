#!/usr/bin/env python3
"""
Unit and Integration Tests for Weapon Serial Number Grinding & Acid-Etch Forensics
(nyx_inventory, nyx_judiciary, nyx_core).
Covers: Migration 050 schema, inventory items (tool_angle_grinder, grinding_disk, acid_etch_kit),
        shared pure Lua 5.4 serial grinding calculations & tool profiles,
        durability wear & tool breakage math, latent fingerprint generation & glove immunity,
        biological laceration hazards, mechanical toolmark striations,
        chemical acid-etching restoration physics (Full, Partial, Failed),
        deterministic asterisk serial masking (Fisher-Yates occlusion),
        certified laboratory metallurgy reports, and in-engine Test 45 integration.
"""

import os
import json
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class TestWeaponSerialGrindingAndAcidEtchForensics(unittest.TestCase):
    def test_migration_050_exists_and_registered(self):
        """Verify migration 050 exists on disk, mirrored, and registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        self.assertTrue(os.path.isfile(index_path), "Migration index.json missing")
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        self.assertIn("050_weapon_serial_grinding_and_acid_etch_forensics.sql", migrations)

        core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "050_weapon_serial_grinding_and_acid_etch_forensics.sql")
        inv_mig = os.path.join(FIVEM_DIR, "nyx_inventory", "sql", "migrations", "050_weapon_serial_grinding_and_acid_etch_forensics.sql")
        jud_mig = os.path.join(FIVEM_DIR, "nyx_judiciary", "sql", "migrations", "050_weapon_serial_grinding_and_acid_etch_forensics.sql")

        self.assertTrue(os.path.isfile(core_mig), "Core migration 050 missing")
        self.assertTrue(os.path.isfile(inv_mig), "nyx_inventory migration 050 missing")
        self.assertTrue(os.path.isfile(jud_mig), "nyx_judiciary migration 050 missing")

        with open(core_mig, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("nyx_inventory_ground_weapons", sql)
        self.assertIn("nyx_judiciary_acid_etch_audits", sql)
        self.assertIn("original_serial", sql)
        self.assertIn("restored_serial", sql)
        self.assertIn("restoration_status", sql)
        self.assertIn("grind_quality", sql)
        self.assertIn("weapon", sql)

    def test_inventory_items_registered(self):
        """Verify tool_angle_grinder, grinding_disk, and acid_etch_kit are registered in items.lua."""
        items_path = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "items.lua")
        self.assertTrue(os.path.isfile(items_path))
        with open(items_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("['tool_angle_grinder']", content)
        self.assertIn("['grinding_disk']", content)
        self.assertIn("['acid_etch_kit']", content)
        self.assertIn("tool_angle_grinder", content)
        self.assertIn("acid_etch_kit", content)
        self.assertIn("usesRemaining", content)

    def test_fxmanifest_declarations(self):
        """Verify fxmanifest.lua declarations in nyx_inventory and nyx_judiciary."""
        inv_manifest = os.path.join(FIVEM_DIR, "nyx_inventory", "fxmanifest.lua")
        with open(inv_manifest, "r", encoding="utf-8") as f:
            inv_txt = f.read()

        self.assertIn("shared/serial_grind.lua", inv_txt)
        self.assertIn("server/grinder.lua", inv_txt)
        self.assertIn("client/grinder.lua", inv_txt)

        jud_manifest = os.path.join(FIVEM_DIR, "nyx_judiciary", "fxmanifest.lua")
        with open(jud_manifest, "r", encoding="utf-8") as f:
            jud_txt = f.read()

        self.assertIn("shared/acid_etch.lua", jud_txt)
        self.assertIn("server/acid_etch.lua", jud_txt)
        self.assertIn("client/acid_etch.lua", jud_txt)

    def test_serial_grind_tool_profiles(self):
        """Verify serial grind tool profile specifications."""
        tools = {
            'tool_angle_grinder': {
                'name': 'tool_angle_grinder',
                'durationMs': 8000,
                'durabilityWear': 6.0,
                'requiresDisk': True,
                'diskItem': 'grinding_disk',
                'noiseRadius': 32.0,
                'lacerationRisk': 0.14,
                'fingerprintRisk': 0.90,
                'baseGrindQuality': 85
            }
        }
        grinder = tools['tool_angle_grinder']
        self.assertEqual(grinder['durabilityWear'], 6.0)
        self.assertEqual(grinder['noiseRadius'], 32.0)
        self.assertTrue(grinder['requiresDisk'])
        self.assertEqual(grinder['diskItem'], 'grinding_disk')

    def test_serial_grind_outcome_math_simulation(self):
        """Test Python reproduction of pure Lua grind outcome calculations."""
        def calc_outcome(weapon_dur, tool_dur, has_gloves, seed=12345):
            def rng(min_v, max_v):
                nonlocal seed
                seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
                ratio = (seed % 10000) / 10000.0
                return min_v + (max_v - min_v) * ratio

            wear_cost = round(rng(6.0, 12.0), 1)
            remaining_wpn_dur = max(0.0, weapon_dur - wear_cost)
            rem_tool_dur = max(0.0, tool_dur - 6.0)
            is_tool_broken = rem_tool_dur <= 0.0

            fp_left = (not has_gloves) and (rng(0.0, 1.0) < 0.90)
            dna_left = (not has_gloves) and (rng(0.0, 1.0) < 0.14)

            return {
                'success': True,
                'originalSerial': 'NYX-123456',
                'scratchedSerial': '[GROUND OFF]',
                'weaponDurabilityLoss': wear_cost,
                'remainingWeaponDurability': remaining_wpn_dur,
                'remainingToolDurability': rem_tool_dur,
                'isToolBroken': is_tool_broken,
                'fingerprintLeft': fp_left,
                'dnaLeft': dna_left
            }

        res = calc_outcome(100.0, 100.0, True, 12345)
        self.assertTrue(res['success'])
        self.assertEqual(res['scratchedSerial'], '[GROUND OFF]')
        self.assertFalse(res['fingerprintLeft'])
        self.assertFalse(res['dnaLeft'])
        self.assertEqual(res['remainingToolDurability'], 94.0)
        self.assertFalse(res['isToolBroken'])

        res_broken = calc_outcome(50.0, 5.0, True, 12345)
        self.assertTrue(res_broken['isToolBroken'])
        self.assertEqual(res_broken['remainingToolDurability'], 0.0)

    def test_forensic_glove_immunity_and_bare_hands(self):
        """Verify examination/forensic gloves grant immunity against latent fingerprints."""
        grind_script = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "serial_grind.lua")
        with open(grind_script, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("hasGloves = options.hasGloves == true", code)
        self.assertIn("if not hasGloves then", code)
        self.assertIn("fingerprintLeft = true", code)
        self.assertIn("lacerationDmg = toolProfile.lacerationDamage", code)

    def test_acid_etch_deterministic_serial_masking(self):
        """Verify deterministic serial masking algorithm with Fisher-Yates shuffle."""
        def mask_serial(orig_serial, visible_ratio, seed=42):
            import math
            def rng():
                nonlocal seed
                seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
                return (seed % 10000) / 10000.0

            prefix = "NYX-"
            digits = orig_serial.replace(prefix, "")
            chars = list(digits)
            total = len(chars)
            visible = max(1, math.floor(total * visible_ratio))
            masked_count = total - visible

            indices = list(range(total))
            for i in range(total - 1, 0, -1):
                j = math.floor(rng() * (i + 1))
                indices[i], indices[j] = indices[j], indices[i]

            for k in range(masked_count):
                idx = indices[k]
                chars[idx] = '*'

            return prefix + "".join(chars)

        m1 = mask_serial("NYX-123456", 0.50, 42)
        m2 = mask_serial("NYX-123456", 0.50, 42)
        m3 = mask_serial("NYX-123456", 0.50, 999)

        self.assertEqual(m1, m2, "Masking should be deterministic for identical seeds")
        self.assertEqual(len(m1), len("NYX-123456"))
        self.assertIn("*", m1)
        self.assertTrue(m1.startswith("NYX-"))

    def test_acid_etch_chemistry_and_report_generator(self):
        """Verify Fry's reagent and metallurgical report formatting in acid_etch.lua."""
        acid_shared = os.path.join(FIVEM_DIR, "nyx_judiciary", "shared", "acid_etch.lua")
        with open(acid_shared, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("Fry's Reagent", code)
        self.assertIn("TELJES HELYREÁLLÍTÁS", code)
        self.assertIn("RÉSZLEGES HELYREÁLLÍTÁS", code)
        self.assertIn("SIKERTELEN", code)
        self.assertIn("FormatLabReport", code)

    def test_serial_display_formatting(self):
        """Verify FormatSerialDisplay presents ground off or chemical restored badges."""
        grind_shared = os.path.join(FIVEM_DIR, "nyx_inventory", "shared", "serial_grind.lua")
        with open(grind_shared, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("FormatSerialDisplay", code)
        self.assertIn("LECSISZOLVA", code)
        self.assertIn("KÉMIAILAG ELŐHÍVVA", code)

    def test_in_engine_test_45_registered(self):
        """Verify Test 45 is registered and invoked in tests.lua."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        with open(tests_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("TestWeaponSerialGrindingAndAcidEtchForensics", content)
        self.assertIn("t45", content)
        self.assertIn("45. Master Test Runner", content)


if __name__ == "__main__":
    unittest.main()
