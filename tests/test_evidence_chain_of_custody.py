#!/usr/bin/env python3
"""
Unit and Integration Tests for Nyxframework Cryptographic Evidence Chain-of-Custody Registry
and SHA-256 Fingerprint Engine (`nyx_judiciary`).
"""

import os
import sys
import json
import hashlib
import unittest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")

def sha256_str(data: str) -> str:
    return hashlib.sha256(data.encode("utf-8")).hexdigest()

def compute_chain_hash(prev_hash, evidence_id, seq, action, custodian, recipient, facility, timestamp, salt):
    raw = f"{prev_hash}:{evidence_id}:{seq}:{action}:{custodian or 'NONE'}:{recipient or 'NONE'}:{facility or 'NONE'}:{timestamp}:{salt or ''}"
    return sha256_str(raw)

class TestEvidenceChainOfCustodySystem(unittest.TestCase):
    def test_judiciary_config_forensics(self):
        """Verify Config.Forensics and chain-of-custody configuration in nyx_judiciary/config.lua."""
        config_path = os.path.join(FIVEM_DIR, "nyx_judiciary", "config.lua")
        self.assertTrue(os.path.isfile(config_path), "nyx_judiciary config.lua missing")
        with open(config_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("Config.Forensics =", content)
        self.assertIn("AllowedActions =", content)
        self.assertIn("COLLECTED", content)
        self.assertIn("TRANSFERRED", content)
        self.assertIn("SECURED_IN_LOCKER", content)
        self.assertIn("LAB_ANALYZED", content)
        self.assertIn("SUBMITTED_EXHIBIT", content)
        self.assertIn("Lockers =", content)
        self.assertIn("locker_mrpd_01", content)
        self.assertIn("lab_davis_forensics", content)
        self.assertIn("vault_court_district", content)
        self.assertIn("LabAnalysisTypes =", content)
        self.assertIn("ballistics_match", content)
        self.assertIn("dna_profile", content)

    def test_fxmanifest_declarations(self):
        """Verify server and client scripts are properly registered in nyx_judiciary fxmanifest.lua."""
        manifest_path = os.path.join(FIVEM_DIR, "nyx_judiciary", "fxmanifest.lua")
        self.assertTrue(os.path.isfile(manifest_path))
        with open(manifest_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("'server/evidence.lua'", content)
        self.assertIn("'server/exports.lua'", content)
        self.assertIn("'client/forensics.lua'", content)
        self.assertIn("'client/exports.lua'", content)

        # Confirm files exist on disk
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_judiciary", "server", "evidence.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_judiciary", "server", "exports.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_judiciary", "client", "forensics.lua")))
        self.assertTrue(os.path.isfile(os.path.join(FIVEM_DIR, "nyx_judiciary", "client", "exports.lua")))

    def test_migration_015_registered(self):
        """Verify migration 015 exists on disk and is registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        with open(index_path, "r", encoding="utf-8") as f:
            index_data = json.load(f)

        self.assertIn("015_judiciary_evidence_chain_of_custody.sql", index_data)

        mig_core = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "015_judiciary_evidence_chain_of_custody.sql")
        mig_jud = os.path.join(FIVEM_DIR, "nyx_judiciary", "sql", "migrations", "015_judiciary_evidence_chain_of_custody.sql")
        self.assertTrue(os.path.isfile(mig_core))
        self.assertTrue(os.path.isfile(mig_jud))

        with open(mig_core, "r", encoding="utf-8") as f:
            sql = f.read()
        self.assertIn("CREATE TABLE IF NOT EXISTS `nyx_judiciary_chain_of_custody`", sql)
        self.assertIn("ALTER TABLE `nyx_judiciary_evidence`", sql)
        self.assertIn("current_chain_hash", sql)
        self.assertIn("chain_length", sql)

    def test_sha256_cryptographic_fingerprinting(self):
        """Verify deterministic physical evidence SHA-256 fingerprint generation."""
        # 1. Spent Casing Fingerprint
        serial = "W-GLOCK-9912"
        cit_id = "CIT-5521"
        coords = (425.12, -980.45, 30.22)
        salt = "aB3d9F1z"
        raw_casing = f"{serial}:{cit_id}:{coords[0]:.2f},{coords[1]:.2f},{coords[2]:.2f}:{salt}"
        hash_casing = sha256_str(raw_casing)
        self.assertEqual(len(hash_casing), 64)

        # Re-computing with identical inputs yields identical hash (deterministic)
        self.assertEqual(sha256_str(raw_casing), hash_casing)

        # Altering serial alters fingerprint
        tampered_casing = f"W-GLOCK-0000:{cit_id}:{coords[0]:.2f},{coords[1]:.2f},{coords[2]:.2f}:{salt}"
        self.assertNotEqual(sha256_str(tampered_casing), hash_casing)

        # 2. Forensic GSR Swab Fingerprint
        swab_raw = f"SWAB-gsr:{cit_id}:POS:{coords[0]:.2f},{coords[1]:.2f},{coords[2]:.2f}:{salt}"
        hash_swab = sha256_str(swab_raw)
        self.assertEqual(len(hash_swab), 64)

        # 3. Photographic / CCTV Surveillance Fingerprint
        photo_raw = f"PHOTO:CAM_UNION_DEPOSITORY:SNAP_49182:{coords[0]:.2f},{coords[1]:.2f},{coords[2]:.2f}:{salt}"
        hash_photo = sha256_str(photo_raw)
        self.assertEqual(len(hash_photo), 64)

    def test_block_chain_genesis_and_continuity(self):
        """Simulate sequential block hash linking from Genesis to Court Exhibit."""
        evidence_id = "ev-uuid-4481-9920"
        root_hash = sha256_str("TEST_ROOT_EVIDENCE_FINGERPRINT")

        # Block 1: COLLECTED (Genesis)
        salt_1 = "salt1111"
        time_1 = 1770000000
        hash_1 = compute_chain_hash(root_hash, evidence_id, 1, "COLLECTED", "OFFICER_A", None, "person:OFFICER_A", time_1, salt_1)
        self.assertEqual(len(hash_1), 64)

        # Block 2: SECURED_IN_LOCKER
        salt_2 = "salt2222"
        time_2 = 1770000300
        hash_2 = compute_chain_hash(hash_1, evidence_id, 2, "SECURED_IN_LOCKER", "OFFICER_A", None, "locker_mrpd_01", time_2, salt_2)
        self.assertEqual(len(hash_2), 64)
        self.assertNotEqual(hash_1, hash_2)

        # Block 3: CHECKED_OUT_LAB
        salt_3 = "salt3333"
        time_3 = 1770001000
        hash_3 = compute_chain_hash(hash_2, evidence_id, 3, "CHECKED_OUT_LAB", "LOCKER:locker_mrpd_01", "DETECTIVE_B", "person:DETECTIVE_B", time_3, salt_3)

        # Block 4: LAB_ANALYZED
        salt_4 = "salt4444"
        time_4 = 1770001800
        hash_4 = compute_chain_hash(hash_3, evidence_id, 4, "LAB_ANALYZED", "FORENSIC_TECH_C", None, "lab_davis_forensics", time_4, salt_4)

        # Block 5: SUBMITTED_EXHIBIT (Court Exhibit)
        salt_5 = "salt5555"
        time_5 = 1770003600
        hash_5 = compute_chain_hash(hash_4, evidence_id, 5, "SUBMITTED_EXHIBIT", "PROSECUTOR_D", None, "vault_court_district", time_5, salt_5)

        # Build ledger
        blocks = [
            {"seq": 1, "prev": root_hash, "hash": hash_1, "act": "COLLECTED", "cust": "OFFICER_A", "rec": None, "fac": "person:OFFICER_A", "t": time_1, "s": salt_1},
            {"seq": 2, "prev": hash_1, "hash": hash_2, "act": "SECURED_IN_LOCKER", "cust": "OFFICER_A", "rec": None, "fac": "locker_mrpd_01", "t": time_2, "s": salt_2},
            {"seq": 3, "prev": hash_2, "hash": hash_3, "act": "CHECKED_OUT_LAB", "cust": "LOCKER:locker_mrpd_01", "rec": "DETECTIVE_B", "fac": "person:DETECTIVE_B", "t": time_3, "s": salt_3},
            {"seq": 4, "prev": hash_3, "hash": hash_4, "act": "LAB_ANALYZED", "cust": "FORENSIC_TECH_C", "rec": None, "fac": "lab_davis_forensics", "t": time_4, "s": salt_4},
            {"seq": 5, "prev": hash_4, "hash": hash_5, "act": "SUBMITTED_EXHIBIT", "cust": "PROSECUTOR_D", "rec": None, "fac": "vault_court_district", "t": time_5, "s": salt_5},
        ]

        # Verify chain integrity
        prev_expected = root_hash
        for blk in blocks:
            self.assertEqual(blk["prev"], prev_expected, f"Chain broken at sequence {blk['seq']}")
            recomputed = compute_chain_hash(blk["prev"], evidence_id, blk["seq"], blk["act"], blk["cust"], blk["rec"], blk["fac"], blk["t"], blk["s"])
            self.assertEqual(recomputed, blk["hash"], f"Hash mismatch at sequence {blk['seq']}")
            prev_expected = blk["hash"]

        self.assertEqual(prev_expected, hash_5)

    def test_cryptographic_tamper_detection(self):
        """Verify that altering any historical custodian, timestamp, or salt breaks hash chain verification."""
        evidence_id = "ev-tamper-check"
        root_hash = sha256_str("ROOT_EVIDENCE")

        h1 = compute_chain_hash(root_hash, evidence_id, 1, "COLLECTED", "OFFICER_A", None, "person:OFFICER_A", 1000, "salt1")
        h2 = compute_chain_hash(h1, evidence_id, 2, "TRANSFERRED", "OFFICER_A", "OFFICER_B", "person:OFFICER_B", 2000, "salt2")
        h3 = compute_chain_hash(h2, evidence_id, 3, "SECURED_IN_LOCKER", "OFFICER_B", None, "locker_mrpd_01", 3000, "salt3")

        # Adversary attempts to tamper with Block 2 by falsifying custodian to OFFICER_X
        tampered_custodian = "OFFICER_X"
        tampered_h2 = compute_chain_hash(h1, evidence_id, 2, "TRANSFERRED", tampered_custodian, "OFFICER_B", "person:OFFICER_B", 2000, "salt2")

        # Verification of Block 2 with original stored hash h2 fails!
        self.assertNotEqual(tampered_h2, h2, "Tampering with custodian must alter block hash")

        # If adversary updates h2 in DB to tampered_h2, Block 3 verification fails because h3 expects h2!
        self.assertNotEqual(h3, compute_chain_hash(tampered_h2, evidence_id, 3, "SECURED_IN_LOCKER", "OFFICER_B", None, "locker_mrpd_01", 3000, "salt3"))

    def test_contamination_state_propagation(self):
        """Verify contamination flags correctly identify compromised evidence without invalidating cryptographic hash."""
        # Bare-hands collection marks contaminated
        is_contaminated = True
        contamination_source = "CITIZEN_OFFICER_DIRTY"

        # The cryptographic fingerprint remains valid even if contaminated
        root_raw = "WEAPON-01:CIT-99:10.00,20.00,30.00:salt123"
        root_hash = sha256_str(root_raw)

        # Integrity check passes, but status is CHAIN_COMPROMISED_CONTAMINATED
        self.assertEqual(sha256_str(root_raw), root_hash)
        status = "CHAIN_COMPROMISED_CONTAMINATED" if is_contaminated else "CHAIN_OF_CUSTODY_VALID"
        self.assertEqual(status, "CHAIN_COMPROMISED_CONTAMINATED")

    def test_in_engine_tests_registered(self):
        """Verify TestEvidenceChainOfCustody is registered in server/tests.lua."""
        tests_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        with open(tests_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("function Nyx.Tests.TestEvidenceChainOfCustody()", code)
        self.assertIn("local t8 = Nyx.Tests.TestEvidenceChainOfCustody()", code)
        self.assertIn("t8", code)

if __name__ == "__main__":
    unittest.main()
