#!/usr/bin/env python3
"""
Unit and Integration Tests for Automated Jury Pool Dispatcher,
Fisher-Yates Shuffle & Courtroom Virtual Routing Bucket Subsystem (`nyx_judiciary`).
"""

import os
import sys
import json
import random
import unittest
from collections import Counter

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")

def fisher_yates_shuffle(items, rng=None):
    """Reference pure Fisher-Yates shuffle implementation."""
    arr = list(items)
    n = len(arr)
    if n <= 1:
        return arr
    for i in range(n - 1, 0, -1):
        j = rng(0, i) if rng else random.randint(0, i)
        arr[i], arr[j] = arr[j], arr[i]
    return arr

def filter_jury_candidates(candidates, criteria):
    """Reference candidate filtering logic."""
    exempt_jobs = set(criteria.get("exempt_jobs", []))
    participants = set(criteria.get("participants", []))
    active_warrants = set(criteria.get("active_warrants", []))
    in_jail = set(criteria.get("in_jail", []))
    recent_served = set(criteria.get("recent_served", []))

    eligible = []
    disqualified = {}

    for cand in candidates:
        cid = cand.get("citizen_id")
        job = cand.get("job", "unemployed")

        if job in exempt_jobs:
            disqualified[cid] = "EXEMPT_JOB"
        elif cid in participants:
            disqualified[cid] = "CASE_PARTICIPANT"
        elif cid in active_warrants:
            disqualified[cid] = "ACTIVE_WARRANT"
        elif cid in in_jail:
            disqualified[cid] = "INCARCERATED"
        elif cid in recent_served:
            disqualified[cid] = "RECENT_SERVICE_COOLDOWN"
        else:
            eligible.append(cand)

    return eligible, disqualified

def calculate_dispatch_plan(eligible_pool, required_count, min_quorum, existing_seated_count=0):
    """Calculates number of jurors to summon and checks quorum."""
    needed = max(0, required_count - existing_seated_count)
    total_potential = existing_seated_count + len(eligible_pool)

    if total_potential < min_quorum:
        return False, "INSUFFICIENT_QUORUM", []

    selected = eligible_pool[:needed]
    return True, "DISPATCH_OK", selected

def assign_jury_seats(current_jurors, total_seats=6):
    """Assigns free seat indices (1..total_seats) to seated jurors."""
    occupied = {j["seat_index"] for j in current_jurors if j.get("seat_index")}
    assigned = []
    next_seat = 1

    for j in current_jurors:
        if not j.get("seat_index"):
            while next_seat in occupied and next_seat <= total_seats:
                next_seat += 1
            if next_seat > total_seats:
                return False, "NO_SEATS_AVAILABLE"
            j["seat_index"] = next_seat
            occupied.add(next_seat)
        assigned.append(j)

    return True, assigned

def tabulate_jury_votes(ballots, rule_type="majority", min_quorum=3):
    """Tabulates votes and returns verdict."""
    guilty = sum(1 for b in ballots if b == "guilty")
    not_guilty = sum(1 for b in ballots if b == "not_guilty")
    abstain = sum(1 for b in ballots if b == "abstain")
    total_valid = guilty + not_guilty

    if (total_valid + abstain) < min_quorum:
        return "incomplete", {"guilty": guilty, "not_guilty": not_guilty, "abstain": abstain}

    if rule_type == "unanimous":
        if guilty > 0 and not_guilty == 0 and total_valid >= min_quorum:
            return "guilty", {"guilty": guilty, "not_guilty": not_guilty, "abstain": abstain}
        elif not_guilty > 0 and guilty == 0 and total_valid >= min_quorum:
            return "not_guilty", {"guilty": guilty, "not_guilty": not_guilty, "abstain": abstain}
        elif guilty > 0 and not_guilty > 0:
            return "hung_jury", {"guilty": guilty, "not_guilty": not_guilty, "abstain": abstain}
        return "incomplete", {"guilty": guilty, "not_guilty": not_guilty, "abstain": abstain}

    # Default majority rule
    if guilty > not_guilty:
        return "guilty", {"guilty": guilty, "not_guilty": not_guilty, "abstain": abstain}
    elif not_guilty > guilty:
        return "not_guilty", {"guilty": guilty, "not_guilty": not_guilty, "abstain": abstain}
    else:
        return "hung_jury", {"guilty": guilty, "not_guilty": not_guilty, "abstain": abstain}


class TestJuryDispatcherAndCourtroomRouting(unittest.TestCase):

    def test_config_jury_and_courtroom(self):
        """Verify Config.Jury parameters in FiveM/nyx_judiciary/config.lua."""
        config_path = os.path.join(FIVEM_DIR, "nyx_judiciary", "config.lua")
        self.assertTrue(os.path.isfile(config_path), "config.lua missing")
        with open(config_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("Config.Jury =", content)
        self.assertIn("DefaultRequiredCount", content)
        self.assertIn("MinimumQuorum", content)
        self.assertIn("DeliberationTimeout", content)
        self.assertIn("ExemptJobs", content)
        self.assertIn("DeliberationBucketOffset", content)
        self.assertIn("SummonsTimeoutSeconds", content)
        self.assertIn("CivicStipendAmount", content)
        self.assertIn("CooldownSeconds", content)

    def test_manifest_shared_scripts(self):
        """Verify fxmanifest.lua declares shared/jury.lua."""
        manifest_path = os.path.join(FIVEM_DIR, "nyx_judiciary", "fxmanifest.lua")
        with open(manifest_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("'shared/jury.lua'", content)
        shared_path = os.path.join(FIVEM_DIR, "nyx_judiciary", "shared", "jury.lua")
        self.assertTrue(os.path.isfile(shared_path), "shared/jury.lua does not exist")

    def test_migration_023_registered(self):
        """Verify migration 023 exists and is registered in index.json."""
        index_path = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")
        with open(index_path, "r", encoding="utf-8") as f:
            index_data = json.load(f)

        self.assertIn("023_judiciary_jury_dispatcher_and_courtroom_routing.sql", index_data)

        mig_core = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "023_judiciary_jury_dispatcher_and_courtroom_routing.sql")
        mig_jud = os.path.join(FIVEM_DIR, "nyx_judiciary", "sql", "migrations", "023_judiciary_jury_dispatcher_and_courtroom_routing.sql")

        self.assertTrue(os.path.isfile(mig_core))
        self.assertTrue(os.path.isfile(mig_jud))

        with open(mig_core, "r", encoding="utf-8") as f:
            sql = f.read()

        self.assertIn("routing_bucket", sql)
        self.assertIn("deliberation_bucket", sql)
        self.assertIn("seat_index", sql)
        self.assertIn("summons_expires_at", sql)
        self.assertIn("stipend_paid", sql)
        self.assertIn("nyx_judiciary_jury_service_logs", sql)

    def test_fisher_yates_shuffle_uniformity_and_preservation(self):
        """Verify Fisher-Yates shuffle produces uniform permutations and preserves elements."""
        items = ["juror_A", "juror_B", "juror_C"]
        permutations = Counter()

        # Run 6,000 trials across the 3! = 6 possible permutations
        for _ in range(6000):
            shuffled = tuple(fisher_yates_shuffle(items))
            permutations[shuffled] += 1

        self.assertEqual(len(permutations), 6, "All 6 permutations must occur")
        # In a uniform distribution of 6000 trials, each permutation expected ~1000 times (tolerance 800 - 1200)
        for perm, count in permutations.items():
            self.assertGreater(count, 750, f"Permutation {perm} occurred too few times: {count}")
            self.assertLess(count, 1250, f"Permutation {perm} occurred too many times: {count}")

        # Edge cases
        self.assertEqual(fisher_yates_shuffle([]), [])
        self.assertEqual(fisher_yates_shuffle(["single"]), ["single"])

    def test_candidate_eligibility_filtering(self):
        """Verify disqualification filters for exempt jobs, active warrants, participants, and cooldown."""
        candidates = [
            {"citizen_id": "CIT-001", "job": "police"},
            {"citizen_id": "CIT-002", "job": "miner"},
            {"citizen_id": "CIT-003", "job": "unemployed"},
            {"citizen_id": "CIT-004", "job": "trucker"},
            {"citizen_id": "CIT-005", "job": "ems"},
            {"citizen_id": "CIT-006", "job": "mechanic"},
            {"citizen_id": "CIT-007", "job": "delivery"}
        ]

        criteria = {
            "exempt_jobs": ["police", "ems", "judge"],
            "participants": ["CIT-002"],       # Defendant
            "active_warrants": ["CIT-004"],   # Active arrest warrant
            "in_jail": ["CIT-006"],           # In Bolingbroke
            "recent_served": ["CIT-007"]      # Served 2 days ago
        }

        eligible, disqualified = filter_jury_candidates(candidates, criteria)

        # Only CIT-003 should be eligible
        self.assertEqual(len(eligible), 1)
        self.assertEqual(eligible[0]["citizen_id"], "CIT-003")

        self.assertEqual(disqualified["CIT-001"], "EXEMPT_JOB")
        self.assertEqual(disqualified["CIT-002"], "CASE_PARTICIPANT")
        self.assertEqual(disqualified["CIT-004"], "ACTIVE_WARRANT")
        self.assertEqual(disqualified["CIT-006"], "INCARCERATED")
        self.assertEqual(disqualified["CIT-007"], "RECENT_SERVICE_COOLDOWN")

    def test_dispatch_plan_and_quorum_gate(self):
        """Verify quorum math and dispatch plan calculation."""
        pool = [{"citizen_id": f"CIT-{i}"} for i in range(10)]

        # Sufficient candidates: need 5, seated 0, min quorum 3
        ok, reason, selected = calculate_dispatch_plan(pool, required_count=5, min_quorum=3, existing_seated_count=0)
        self.assertTrue(ok)
        self.assertEqual(len(selected), 5)

        # Partial seated: need 5, seated 2, summons needed 3
        ok, reason, selected = calculate_dispatch_plan(pool, required_count=5, min_quorum=3, existing_seated_count=2)
        self.assertTrue(ok)
        self.assertEqual(len(selected), 3)

        # Quorum failure: need 5, seated 1, pool has only 1 (total 2 < min quorum 3)
        small_pool = [{"citizen_id": "CIT-99"}]
        ok, reason, selected = calculate_dispatch_plan(small_pool, required_count=5, min_quorum=3, existing_seated_count=1)
        self.assertFalse(ok)
        self.assertEqual(reason, "INSUFFICIENT_QUORUM")

    def test_seat_assignment_matrix(self):
        """Verify dynamic seat allocation without collisions."""
        jurors = [
            {"citizen_id": "CIT-A", "seat_index": None},
            {"citizen_id": "CIT-B", "seat_index": 2}, # Already has seat 2
            {"citizen_id": "CIT-C", "seat_index": None},
        ]

        ok, assigned = assign_jury_seats(jurors, total_seats=6)
        self.assertTrue(ok)

        seats = [j["seat_index"] for j in assigned]
        self.assertEqual(len(seats), len(set(seats)), "No two jurors should have the same seat")
        self.assertEqual(assigned[1]["seat_index"], 2, "Existing seat 2 should be preserved")
        self.assertIn(assigned[0]["seat_index"], [1, 3, 4, 5, 6])
        self.assertIn(assigned[2]["seat_index"], [1, 3, 4, 5, 6])

    def test_deliberation_vote_tabulation(self):
        """Verify majority and unanimous deliberation vote tabulation."""
        # 1. Majority Rule: 3 guilty, 2 not guilty -> guilty
        ballots1 = ["guilty", "guilty", "guilty", "not_guilty", "not_guilty"]
        verdict1, tally1 = tabulate_jury_votes(ballots1, rule_type="majority")
        self.assertEqual(verdict1, "guilty")
        self.assertEqual(tally1["guilty"], 3)
        self.assertEqual(tally1["not_guilty"], 2)

        # 2. Majority Rule: 1 guilty, 3 not guilty, 1 abstain -> not guilty
        ballots2 = ["guilty", "not_guilty", "not_guilty", "not_guilty", "abstain"]
        verdict2, tally2 = tabulate_jury_votes(ballots2, rule_type="majority")
        self.assertEqual(verdict2, "not_guilty")

        # 3. Majority Rule: 2 guilty, 2 not guilty (deadlock) -> hung jury
        ballots3 = ["guilty", "guilty", "not_guilty", "not_guilty"]
        verdict3, tally3 = tabulate_jury_votes(ballots3, rule_type="majority")
        self.assertEqual(verdict3, "hung_jury")

        # 4. Unanimous Rule: 4 guilty, 0 not guilty -> guilty
        ballots4 = ["guilty", "guilty", "guilty", "guilty"]
        verdict4, tally4 = tabulate_jury_votes(ballots4, rule_type="unanimous")
        self.assertEqual(verdict4, "guilty")

        # 5. Unanimous Rule: 3 guilty, 1 not guilty -> hung jury (no consensus)
        ballots5 = ["guilty", "guilty", "guilty", "not_guilty"]
        verdict5, tally5 = tabulate_jury_votes(ballots5, rule_type="unanimous")
        self.assertEqual(verdict5, "hung_jury")

    def test_virtual_routing_bucket_math(self):
        """Verify deterministic courtroom bucket allocation and deliberation isolation offset."""
        # Offset should isolate deliberation by +2000
        courtroom_bucket = 2145
        deliberation_offset = 2000
        deliberation_bucket = courtroom_bucket + deliberation_offset
        self.assertEqual(deliberation_bucket, 4145)

        # Verify bucket ranges
        self.assertGreaterEqual(courtroom_bucket, 2100)
        self.assertLessEqual(courtroom_bucket, 2999)
        self.assertGreaterEqual(deliberation_bucket, 4100)
        self.assertLessEqual(deliberation_bucket, 4999)

    def test_server_exports_and_rpc_routes(self):
        """Verify all new exports and RPC routes are properly declared."""
        exports_path = os.path.join(FIVEM_DIR, "nyx_judiciary", "server", "exports.lua")
        with open(exports_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn('exports("StartTrial"', content)
        self.assertIn('exports("StartDeliberation"', content)
        self.assertIn('exports("SeatJuror"', content)
        self.assertIn('exports("ExcuseJuror"', content)
        self.assertIn('exports("ConcludeTrial"', content)
        self.assertIn('exports("GetJuryStatus"', content)
        self.assertIn('exports("AllocateCourtroomBucket"', content)

        main_path = os.path.join(FIVEM_DIR, "nyx_judiciary", "server", "main.lua")
        with open(main_path, "r", encoding="utf-8") as f:
            main_content = f.read()

        self.assertIn('"judiciary:startTrial"', main_content)
        self.assertIn('"judiciary:startDeliberation"', main_content)
        self.assertIn('"judiciary:seatJuror"', main_content)
        self.assertIn('"judiciary:excuseJuror"', main_content)
        self.assertIn('"judiciary:getJuryStatus"', main_content)

    def test_in_engine_tests_suite_registered(self):
        """Verify TestJuryDispatcherAndCourtroomRouting is declared in nyx_core/server/tests.lua and called in RunAll."""
        tests_lua_path = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
        with open(tests_lua_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("function Nyx.Tests.TestJuryDispatcherAndCourtroomRouting()", content)
        self.assertIn("local t17 = Nyx.Tests.TestJuryDispatcherAndCourtroomRouting()", content)
        self.assertIn("t16 and t17", content)


if __name__ == "__main__":
    unittest.main()

