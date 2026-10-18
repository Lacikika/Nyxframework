"""
Unit tests for Instant-Runoff Voting (IRV) election engine & live penal code sync
(nyx_parliament).
"""

import math
import pytest


class IRVEngine:
    @staticmethod
    def sanitize_ballot(raw_preferences, allowed_candidates):
        if not raw_preferences:
            return []
        allowed_set = set(allowed_candidates) if allowed_candidates else None
        seen = set()
        sanitized = []
        for choice in raw_preferences:
            if isinstance(choice, str) and choice:
                if (allowed_set is None or choice in allowed_set) and choice not in seen:
                    seen.add(choice)
                    sanitized.append(choice)
        return sanitized

    @staticmethod
    def tabulate(raw_ballots, candidate_list, options=None):
        options = options or {}
        quorum = options.get("quorum", 1)
        maj_percent = options.get("majority_threshold_percent", 50.0)

        if not raw_ballots or len(raw_ballots) == 0:
            return None, "NO_BALLOTS_SUBMITTED", [], {}, 0

        if not candidate_list or len(candidate_list) == 0:
            return None, "NO_CANDIDATES_REGISTERED", [], {}, 0

        # Unique candidates
        active_candidates = set(candidate_list)
        candidate_array = sorted(list(active_candidates))

        # Sanitize ballots
        ballots = []
        for raw in raw_ballots:
            clean = IRVEngine.sanitize_ballot(raw, active_candidates)
            if clean:
                ballots.append(clean)

        total_valid = len(ballots)
        if total_valid < quorum:
            return None, "QUORUM_NOT_MET", [], {}, 0

        if len(candidate_array) == 1:
            sole = candidate_array[0]
            count = sum(1 for b in ballots if b[0] == sole)
            round_log = {
                "round": 1,
                "continuing_ballots": total_valid,
                "exhausted_ballots": 0,
                "majority_needed": 1,
                "tally": {sole: count},
                "winner": sole
            }
            return sole, "SINGLE_CANDIDATE", [round_log], {sole: count}, 0

        round_logs = []
        round_idx = 1
        total_exhausted = 0
        final_counts = {}

        while True:
            tally = {c: 0 for c in active_candidates}
            continuing = 0
            round_exhausted = 0

            for prefs in ballots:
                voted = False
                for c in prefs:
                    if c in active_candidates:
                        tally[c] += 1
                        continuing += 1
                        voted = True
                        break
                if not voted:
                    round_exhausted += 1

            total_exhausted = round_exhausted
            final_counts = dict(tally)

            if continuing == 0:
                return None, "DEADLOCK_NO_CONTINUING_BALLOTS", round_logs, final_counts, total_exhausted

            majority_needed = math.floor(continuing * (maj_percent / 100.0)) + 1
            percentages = {c: round((votes / continuing) * 100.0, 2) for c, votes in tally.items()}

            highest_cand = None
            highest_votes = -1
            lowest_cand = None
            lowest_votes = float("inf")
            lowest_list = []

            for c, votes in tally.items():
                if votes > highest_votes:
                    highest_votes = votes
                    highest_cand = c
                if votes < lowest_votes:
                    lowest_votes = votes
                    lowest_cand = c
                    lowest_list = [c]
                elif votes == lowest_votes:
                    lowest_list.append(c)

            # Check majority winner
            if highest_votes >= majority_needed:
                round_log = {
                    "round": round_idx,
                    "continuing_ballots": continuing,
                    "exhausted_ballots": round_exhausted,
                    "majority_needed": majority_needed,
                    "tally": dict(tally),
                    "percentages": percentages,
                    "winner": highest_cand,
                    "eliminated": None
                }
                round_logs.append(round_log)
                return highest_cand, "WINNER_MAJORITY", round_logs, final_counts, total_exhausted

            # Check if only 2 candidates remain
            if len(active_candidates) <= 2:
                win_cand = highest_cand
                win_status = "FINAL_ROUND_WINNER"

                if len(lowest_list) == 2 and lowest_votes == highest_votes:
                    lowest_list.sort()
                    win_cand = lowest_list[0]
                    win_status = "TIE_RESOLVED_LEXICOGRAPHICAL"

                round_log = {
                    "round": round_idx,
                    "continuing_ballots": continuing,
                    "exhausted_ballots": round_exhausted,
                    "majority_needed": majority_needed,
                    "tally": dict(tally),
                    "percentages": percentages,
                    "winner": win_cand,
                    "eliminated": None
                }
                round_logs.append(round_log)
                return win_cand, win_status, round_logs, final_counts, total_exhausted

            # 3+ candidates: eliminate lowest
            to_eliminate = lowest_cand
            if len(lowest_list) > 1:
                lowest_list.sort()
                to_eliminate = lowest_list[-1]  # eliminate last alphabetically

            round_log = {
                "round": round_idx,
                "continuing_ballots": continuing,
                "exhausted_ballots": round_exhausted,
                "majority_needed": majority_needed,
                "tally": dict(tally),
                "percentages": percentages,
                "winner": None,
                "eliminated": to_eliminate
            }
            round_logs.append(round_log)

            active_candidates.remove(to_eliminate)
            round_idx += 1
            if round_idx > 50:
                return highest_cand, "SAFETY_MAX_ROUNDS", round_logs, final_counts, total_exhausted


class MockStatutesRegistry:
    def __init__(self):
        self.laws = {
            "penal:reckless_driving": {
                "id": "penal:reckless_driving",
                "title": "Reckless Driving",
                "category": "penal_misdemeanor",
                "current": {"fine": 750, "months": 5},
                "min_allowed": {"fine": 250, "months": 0},
                "max_allowed": {"fine": 2500, "months": 15}
            },
            "penal:armed_robbery": {
                "id": "penal:armed_robbery",
                "title": "Armed Robbery",
                "category": "penal_felony",
                "current": {"fine": 10000, "months": 25},
                "min_allowed": {"fine": 5000, "months": 10},
                "max_allowed": {"fine": 30000, "months": 60}
            },
            "tax:sales_rate": {
                "id": "tax:sales_rate",
                "title": "Sales Tax",
                "category": "fiscal_policy",
                "current": {"rate": 0.08},
                "min_allowed": {"rate": 0.00},
                "max_allowed": {"rate": 0.15}
            }
        }

    def validate_bill_action(self, target_law_id, field, new_val):
        law = self.laws.get(target_law_id)
        if not law:
            return False, f"LAW_NOT_FOUND: '{target_law_id}'"

        try:
            val = float(new_val)
        except (ValueError, TypeError):
            return False, "INVALID_NUMERIC_VALUE"

        min_val = law.get("min_allowed", {}).get(field)
        max_val = law.get("max_allowed", {}).get(field)

        if min_val is not None and val < float(min_val):
            return False, "STATUTORY_MINIMUM_VIOLATION"

        if max_val is not None and val > float(max_val):
            return False, "STATUTORY_MAXIMUM_VIOLATION"

        return True, "OK"

    def enact_action(self, target_law_id, field, new_val):
        ok, err = self.validate_bill_action(target_law_id, field, new_val)
        if not ok:
            return False, err
        self.laws[target_law_id]["current"][field] = float(new_val)
        return True, "ENACTED"


class MockMDT:
    def __init__(self, statutes: MockStatutesRegistry):
        self.statutes = statutes
        self.default_fine_limit = 25000.0

    def issue_fine(self, charge_id, amount):
        law = self.statutes.laws.get(charge_id)
        max_fine = self.default_fine_limit
        min_fine = 0.0

        if law and "fine" in law.get("max_allowed", {}):
            max_fine = float(law["max_allowed"]["fine"])
        if law and "fine" in law.get("min_allowed", {}):
            min_fine = float(law["min_allowed"]["fine"])

        if amount > max_fine:
            return False, "EXCEEDS_STATUTORY_MAXIMUM", max_fine

        if amount < min_fine:
            return False, "BELOW_STATUTORY_MINIMUM", min_fine

        return True, "ISSUED", amount


class MockCandidateRegistry:
    def __init__(self, required_endorsements=3):
        self.required_endorsements = required_endorsements
        self.candidates = {}
        self.endorsements = set()  # (cand_id, cit_id)

    def register_candidate(self, session_id, citizen_id, name):
        cand_id = f"cand_{citizen_id}_{session_id}"
        if cand_id in self.candidates:
            return False, "ALREADY_REGISTERED"
        self.candidates[cand_id] = {
            "candidate_id": cand_id,
            "session_id": session_id,
            "citizen_id": citizen_id,
            "name": name,
            "endorsements_count": 0,
            "status": "nominated"
        }
        return True, self.candidates[cand_id]

    def endorse(self, cand_id, citizen_id):
        cand = self.candidates.get(cand_id)
        if not cand:
            return False, "CANDIDATE_NOT_FOUND"
        if cand["citizen_id"] == citizen_id:
            return False, "CANNOT_ENDORSE_SELF"
        if (cand_id, citizen_id) in self.endorsements:
            return False, "ALREADY_ENDORSED"

        self.endorsements.add((cand_id, citizen_id))
        cand["endorsements_count"] += 1
        if cand["endorsements_count"] >= self.required_endorsements:
            cand["status"] = "qualified"
        return True, cand["status"]


# ==============================================================================
# PYTEST TEST CASES
# ==============================================================================

def test_irv_round1_majority():
    # 10 ballots, candidate A gets 6 (60% > 50%)
    ballots = [
        ["cand_a"], ["cand_a"], ["cand_a"], ["cand_a"], ["cand_a"], ["cand_a"],
        ["cand_b"], ["cand_b"], ["cand_b"],
        ["cand_c"]
    ]
    candidates = ["cand_a", "cand_b", "cand_c"]
    winner, status, rounds, tally, exhausted = IRVEngine.tabulate(ballots, candidates, {"quorum": 5})

    assert winner == "cand_a"
    assert status == "WINNER_MAJORITY"
    assert len(rounds) == 1
    assert tally["cand_a"] == 6
    assert exhausted == 0


def test_irv_multi_round_elimination_and_transfer():
    # 10 ballots:
    # 4 for A (2nd B)
    # 3 for B (2nd C)
    # 3 for C (2nd B)
    ballots = [
        ["cand_a", "cand_b"], ["cand_a", "cand_b"], ["cand_a", "cand_b"], ["cand_a", "cand_b"],
        ["cand_b", "cand_c"], ["cand_b", "cand_c"], ["cand_b", "cand_c"],
        ["cand_c", "cand_b"], ["cand_c", "cand_b"], ["cand_c", "cand_b"]
    ]
    candidates = ["cand_a", "cand_b", "cand_c"]
    winner, status, rounds, tally, exhausted = IRVEngine.tabulate(ballots, candidates, {"quorum": 5})

    # C eliminated, transfers 3 votes to B -> B reaches 6 (60%)
    assert winner == "cand_b"
    assert status == "WINNER_MAJORITY"
    assert len(rounds) == 2
    assert tally["cand_b"] == 6
    assert tally["cand_a"] == 4
    assert exhausted == 0


def test_irv_ballot_exhaustion_dynamic_majority():
    # 10 ballots:
    # 4 for A (no second choice)
    # 3 for B (2nd C)
    # 3 for C (bullet vote - exhausted on C elimination)
    ballots = [
        ["cand_a"], ["cand_a"], ["cand_a"], ["cand_a"],
        ["cand_b", "cand_c"], ["cand_b", "cand_c"], ["cand_b", "cand_c"],
        ["cand_c"], ["cand_c"], ["cand_c"]
    ]
    candidates = ["cand_a", "cand_b", "cand_c"]
    winner, status, rounds, tally, exhausted = IRVEngine.tabulate(ballots, candidates, {"quorum": 5})

    # Round 1: A=4, B=3, C=3. C eliminated.
    # Round 2: 3 ballots for C have no remaining candidates -> exhausted!
    # Continuing ballots = 10 - 3 = 7. Majority needed = floor(7*0.5)+1 = 4.
    # A has 4 >= 4 -> A wins on round 2!
    assert winner == "cand_a"
    assert status == "WINNER_MAJORITY"
    assert len(rounds) == 2
    assert exhausted == 3
    assert rounds[1]["continuing_ballots"] == 7
    assert rounds[1]["majority_needed"] == 4


def test_irv_quorum_failure():
    ballots = [["cand_a"], ["cand_b"]]
    candidates = ["cand_a", "cand_b"]
    winner, status, rounds, tally, exhausted = IRVEngine.tabulate(ballots, candidates, {"quorum": 5})

    assert winner is None
    assert status == "QUORUM_NOT_MET"


def test_irv_deterministic_tie_breaking():
    ballots = [
        ["cand_x"], ["cand_x"],
        ["cand_y"], ["cand_y"]
    ]
    candidates = ["cand_x", "cand_y"]
    winner, status, rounds, tally, exhausted = IRVEngine.tabulate(ballots, candidates, {"quorum": 2})

    assert winner in ["cand_x", "cand_y"]
    assert status in ["FINAL_ROUND_WINNER", "TIE_RESOLVED_LEXICOGRAPHICAL"]


def test_candidate_endorsement_state_machine():
    registry = MockCandidateRegistry(required_endorsements=3)
    ok, cand = registry.register_candidate("election_mayor", "CIT_100", "Elena Vance")
    assert ok is True
    assert cand["status"] == "nominated"
    cand_id = cand["candidate_id"]

    # 1. Self endorsement must fail
    ok, err = registry.endorse(cand_id, "CIT_100")
    assert ok is False
    assert err == "CANNOT_ENDORSE_SELF"

    # 2. First endorsement
    ok, status = registry.endorse(cand_id, "CIT_201")
    assert ok is True
    assert status == "nominated"
    assert cand["endorsements_count"] == 1

    # 3. Duplicate endorsement must fail
    ok, err = registry.endorse(cand_id, "CIT_201")
    assert ok is False
    assert err == "ALREADY_ENDORSED"

    # 4. Second endorsement
    ok, status = registry.endorse(cand_id, "CIT_202")
    assert ok is True
    assert status == "nominated"
    assert cand["endorsements_count"] == 2

    # 5. Third endorsement: Reaches threshold -> QUALIFIED!
    ok, status = registry.endorse(cand_id, "CIT_203")
    assert ok is True
    assert status == "qualified"
    assert cand["endorsements_count"] == 3
    assert cand["status"] == "qualified"


def test_statutory_penal_boundary_clamping():
    statutes = MockStatutesRegistry()

    # Valid amendment within bounds ($1,500 is in 250 - 2,500)
    ok, err = statutes.validate_bill_action("penal:reckless_driving", "fine", 1500)
    assert ok is True
    assert err == "OK"

    # Exceeding statutory maximum ($5,000 > 2,500)
    ok, err = statutes.validate_bill_action("penal:reckless_driving", "fine", 5000)
    assert ok is False
    assert err == "STATUTORY_MAXIMUM_VIOLATION"

    # Below statutory minimum ($100 < 250)
    ok, err = statutes.validate_bill_action("penal:reckless_driving", "fine", 100)
    assert ok is False
    assert err == "STATUTORY_MINIMUM_VIOLATION"

    # Enact valid change
    ok, _ = statutes.enact_action("penal:reckless_driving", "fine", 1500)
    assert ok is True
    assert statutes.laws["penal:reckless_driving"]["current"]["fine"] == 1500.0


def test_mdt_statutory_fine_ceiling_enforcement():
    statutes = MockStatutesRegistry()
    mdt = MockMDT(statutes)

    # Valid citation ($1,500 <= max $2,500)
    ok, res, amt = mdt.issue_fine("penal:reckless_driving", 1500.0)
    assert ok is True
    assert res == "ISSUED"
    assert amt == 1500.0

    # Exceeds statutory maximum ($3,000 > max $2,500)
    ok, res, max_allowed = mdt.issue_fine("penal:reckless_driving", 3000.0)
    assert ok is False
    assert res == "EXCEEDS_STATUTORY_MAXIMUM"
    assert max_allowed == 2500.0

    # Below statutory minimum ($100 < min $250)
    ok, res, min_allowed = mdt.issue_fine("penal:reckless_driving", 100.0)
    assert ok is False
    assert res == "BELOW_STATUTORY_MINIMUM"
    assert min_allowed == 250.0
