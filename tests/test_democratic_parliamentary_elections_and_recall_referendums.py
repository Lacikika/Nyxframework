"""
Unit tests for Democratic Parliamentary Elections & Recall Referendums (nyx_parliament & nyx_ui).
Tests pure domain logic: candidate eligibility, collateral escrow & refund reconciliation,
spatial voting booth proximity, anti-Sybil machine hashing, term limit expiration,
recall petition immunity cooldown, referendum outcomes, Migration 056, and UI bridge integrity.
"""

import os
import re
import json
import math
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class DemocraticElectionsEngine:
    """Pure domain engine mirroring Nyx.DemocraticElections in shared/elections.lua."""

    CONSTANTS = {
        "NominationWindowHours": 48,
        "VotingWindowHours": 72,
        "CollateralRefundVoteThresholdPct": 10.0,
        "CandidateCollateralDefault": 2500.00,
        "RequiredEndorsementsDefault": 3,
        "RecallSignatureThresholdDefault": 5,
        "RecallImmunityCooldownDays": 7,
        "MaxCandidatesPerSession": 10,
        "DefaultBoothInteractDistance": 2.5
    }

    OFFICES = {
        "mayor": {
            "title": "City Mayor",
            "department": "Executive",
            "termDays": 30,
            "maxConsecutiveTerms": 2
        },
        "chief_magistrate": {
            "title": "Chief Magistrate",
            "department": "Judiciary",
            "termDays": 45,
            "maxConsecutiveTerms": 2
        },
        "district_commissioner": {
            "title": "District Commissioner",
            "department": "Legislative",
            "termDays": 30,
            "maxConsecutiveTerms": 3
        }
    }

    BOOTHS = {
        "booth:city_hall": {
            "id": "booth:city_hall",
            "label": "City Hall Council Voting Booth",
            "coords": (-540.9, -199.3, 47.5),
            "radius": 2.5
        },
        "booth:sandy_shores": {
            "id": "booth:sandy_shores",
            "label": "Sandy Shores Regional Ballot Station",
            "coords": (1853.2, 3686.9, 34.3),
            "radius": 2.5
        },
        "booth:paleto_bay": {
            "id": "booth:paleto_bay",
            "label": "Paleto Bay Justice Center Ballot Station",
            "coords": (-448.2, 6012.3, 31.7),
            "radius": 2.5
        }
    }

    @classmethod
    def evaluate_candidate_eligibility(cls, citizen_id, office_id, session, existing_candidates=None, active_official=None, config=None):
        if not citizen_id or not isinstance(citizen_id, str) or len(citizen_id) < 3:
            return False, "INVALID_CITIZEN_ID"

        if not session or not isinstance(session, dict):
            return False, "SESSION_NOT_FOUND"

        if session.get("type") != "election":
            return False, "SESSION_NOT_AN_ELECTION"

        if session.get("status") not in ("active", "scheduled"):
            return False, "SESSION_NOT_OPEN"

        phase = session.get("election_phase")
        if phase and phase not in ("nomination", "voting"):
            return False, "NOMINATION_PERIOD_CLOSED"

        cfg = config or cls.CONSTANTS
        max_candidates = cfg.get("MaxCandidatesPerSession", 10)
        candidates = existing_candidates or []

        if len(candidates) >= max_candidates:
            return False, "MAX_CANDIDATES_REACHED"

        for c in candidates:
            c_cit = c.get("citizen_id") or c.get("citizenId")
            if c_cit == citizen_id and c.get("status") != "withdrawn":
                return False, "ALREADY_REGISTERED_AS_CANDIDATE"

        target_office = office_id or session.get("office_id") or (session.get("metadata", {}).get("officeId"))
        if target_office and active_official:
            act_cit = active_official.get("citizen_id") or active_official.get("citizenId")
            if act_cit == citizen_id:
                office_spec = cls.OFFICES.get(target_office)
                max_terms = office_spec.get("maxConsecutiveTerms", 2) if office_spec else 2
                current_terms = int(active_official.get("consecutive_terms", 1))
                if current_terms >= max_terms:
                    return False, "TERM_LIMIT_EXCEEDED"

        return True, None

    @classmethod
    def calculate_collateral_escrow(cls, collateral_required, bank_balance, citizen_id, session_id):
        required = float(collateral_required if collateral_required is not None else cls.CONSTANTS["CandidateCollateralDefault"])
        balance = float(bank_balance or 0.0)

        if required < 0:
            return False, None, "INVALID_COLLATERAL_AMOUNT"

        if balance < required:
            return False, {
                "required": required,
                "balance": balance,
                "deficit": max(0.0, required - balance)
            }, "INSUFFICIENT_COLLATERAL_FUNDS"

        return True, {
            "required": required,
            "balance": balance,
            "debitAccount": f"char:{citizen_id or 'unknown'}:bank",
            "creditAccount": "gov:city:master",
            "category": "election_collateral",
            "reference": f"parliament:{session_id or 'general'}"
        }, None

    @classmethod
    def evaluate_collateral_refund(cls, candidate, total_valid_ballots, winner_candidate_id=None, threshold_pct=None):
        if not candidate or not isinstance(candidate, dict):
            return {"eligible": False, "amount": 0.0, "status": "forfeited", "reason": "INVALID_CANDIDATE"}

        deposited = float(candidate.get("collateral_deposited", 0.0))
        if deposited <= 0.0:
            return {"eligible": False, "amount": 0.0, "status": "refunded", "reason": "NO_COLLATERAL_DEPOSITED"}

        status = candidate.get("status", "nominated")
        cand_id = candidate.get("candidate_id") or candidate.get("id")

        if status == "withdrawn":
            return {
                "eligible": True,
                "amount": deposited,
                "status": "refunded",
                "reason": "WITHDRAWAL_BEFORE_BALLOT"
            }

        if status == "disqualified":
            return {
                "eligible": False,
                "amount": 0.0,
                "status": "forfeited",
                "reason": "CANDIDATE_DISQUALIFIED"
            }

        if winner_candidate_id and cand_id == winner_candidate_id:
            return {
                "eligible": True,
                "amount": deposited,
                "status": "refunded",
                "reason": "ELECTION_WINNER"
            }

        total_votes = int(total_valid_ballots or 0)
        cand_votes = int(candidate.get("vote_count", 0))
        threshold = float(threshold_pct if threshold_pct is not None else cls.CONSTANTS["CollateralRefundVoteThresholdPct"])

        if total_votes > 0:
            share_pct = (cand_votes / total_votes) * 100.0
            if share_pct >= threshold:
                return {
                    "eligible": True,
                    "amount": deposited,
                    "status": "refunded",
                    "reason": "MET_VOTE_THRESHOLD",
                    "sharePct": share_pct
                }
            else:
                return {
                    "eligible": False,
                    "amount": 0.0,
                    "status": "forfeited",
                    "reason": "BELOW_VOTE_THRESHOLD",
                    "sharePct": share_pct
                }

        if status == "qualified":
            return {
                "eligible": True,
                "amount": deposited,
                "status": "refunded",
                "reason": "QUALIFIED_NO_VOTES_CAST"
            }

        return {
            "eligible": False,
            "amount": 0.0,
            "status": "forfeited",
            "reason": "DID_NOT_QUALIFY"
        }

    @classmethod
    def validate_booth_proximity(cls, player_coords, booths_catalog=None, max_distance=None):
        booths = booths_catalog or cls.BOOTHS
        max_dist = max_distance if max_distance is not None else cls.CONSTANTS["DefaultBoothInteractDistance"]

        if not player_coords:
            return {
                "isNear": False,
                "boothId": None,
                "boothLabel": "Remote Terminal",
                "distance": 999999.0
            }

        px, py, pz = player_coords[0], player_coords[1], player_coords[2]
        nearest_id = None
        nearest_label = None
        shortest_dist = 999999.0

        for b_id, booth in booths.items():
            bx, by, bz = booth["coords"]
            dist = math.sqrt((px - bx)**2 + (py - by)**2 + (pz - bz)**2)
            if dist < shortest_dist:
                shortest_dist = dist
                nearest_id = b_id
                nearest_label = booth["label"]

        is_near = shortest_dist <= max_dist
        return {
            "isNear": is_near,
            "boothId": nearest_id if is_near else None,
            "boothLabel": nearest_label if is_near else "Remote Terminal",
            "distance": round(shortest_dist, 2),
            "nearestBoothId": nearest_id
        }

    @classmethod
    def generate_hardware_footprint_hash(cls, identifiers=None, tokens=None, fallback_src="unknown"):
        if tokens and isinstance(tokens, list) and len(tokens) > 0:
            raw = ":".join(str(t) for t in tokens)
            return f"HWID-{len(raw):08x}{len(tokens)*54321:08x}"

        if identifiers and isinstance(identifiers, list):
            for ident in identifiers:
                if isinstance(ident, str) and ident.startswith("license:"):
                    return "LIC-" + ident[8:]

        return f"ANON-DEV-{fallback_src}"

    @classmethod
    def evaluate_term_expiration(cls, official, current_epoch):
        if not official or not isinstance(official, dict):
            return {"isExpired": False, "error": "INVALID_OFFICIAL"}

        if official.get("status") != "active":
            return {"isExpired": False, "status": official.get("status"), "reason": "NOT_ACTIVE"}

        now = int(current_epoch)
        term_end = int(official.get("term_end_epoch") or (now + 86400))
        is_expired = (now >= term_end)

        return {
            "isExpired": is_expired,
            "officeId": official.get("office_id", "unknown"),
            "citizenId": official.get("citizen_id", "unknown"),
            "remainingSeconds": max(0, term_end - now),
            "consecutiveTerms": int(official.get("consecutive_terms", 1))
        }

    @classmethod
    def evaluate_recall_eligibility(cls, official, initiator_citizen_id, existing_petitions=None, current_epoch=0):
        if not official or not isinstance(official, dict):
            return False, "NO_ACTIVE_OFFICIAL_IN_OFFICE"

        if official.get("status") != "active":
            return False, "OFFICIAL_NOT_ACTIVE"

        target_cit = official.get("citizen_id") or official.get("citizenId")
        if not target_cit:
            return False, "NO_OFFICIAL_ASSIGNED"

        if initiator_citizen_id == target_cit:
            return False, "CANNOT_RECALL_SELF"

        now = int(current_epoch)
        cooldown = official.get("cooldown_until_epoch")
        if cooldown and now < cooldown:
            rem = cooldown - now
            return False, f"RECALL_COOLDOWN_ACTIVE:{rem}"

        if existing_petitions and isinstance(existing_petitions, list):
            for pet in existing_petitions:
                p_office = pet.get("office_id") or pet.get("officeId")
                if p_office == official.get("office_id") and pet.get("status") == "active":
                    return False, "ACTIVE_PETITION_ALREADY_EXISTS"

        return True, None

    @classmethod
    def evaluate_recall_referendum_outcome(cls, winner_option, office_id):
        winner = str(winner_option or "").upper()
        passed = winner in ("RECALL_YES", "PASS", "YES")

        if passed:
            return {
                "passed": True,
                "vacateOfficial": True,
                "scheduleSnapElection": True,
                "action": "OFFICIAL_RECALLED",
                "officeId": office_id
            }
        else:
            return {
                "passed": False,
                "vacateOfficial": False,
                "scheduleSnapElection": False,
                "applyCooldown": True,
                "cooldownDays": cls.CONSTANTS["RecallImmunityCooldownDays"],
                "action": "OFFICIAL_RETAINED",
                "officeId": office_id
            }

    @classmethod
    def format_election_status_badge(cls, phase, status):
        p = str(phase or "").lower()
        s = str(status or "").lower()

        if s == "concluded":
            return {"label": "Lezárult (Hitelesítve)", "badgeClass": "badge-concluded", "icon": "fa-solid fa-award"}
        elif s == "invalidated":
            return {"label": "Érvénytelen (Kórum Hiánya)", "badgeClass": "badge-danger", "icon": "fa-solid fa-ban"}
        elif p == "nomination" or s == "scheduled":
            return {"label": "Jelöltállítási Időszak", "badgeClass": "badge-info", "icon": "fa-solid fa-user-plus"}
        elif p == "voting" or s == "active":
            return {"label": "Aktív Szavazás (Preferenciális)", "badgeClass": "badge-success", "icon": "fa-solid fa-check-to-slot"}
        elif p == "tallying" or s == "tallying":
            return {"label": "Összesítés Folyamatban (IRV)", "badgeClass": "badge-warning", "icon": "fa-solid fa-arrows-rotate"}

        return {"label": "Általános Választás", "badgeClass": "badge-secondary", "icon": "fa-solid fa-landmark"}

    @classmethod
    def format_recall_progress_bar(cls, current_signatures, required_signatures):
        cur = max(0, int(current_signatures or 0))
        req = max(1, int(required_signatures or cls.CONSTANTS["RecallSignatureThresholdDefault"]))
        pct = min(100.0, round((cur / req) * 100.0))
        certified = (cur >= req)

        return {
            "currentSignatures": cur,
            "requiredSignatures": req,
            "progressPercent": pct,
            "isCertified": certified,
            "remainingSignatures": max(0, req - cur),
            "label": f"{cur} / {req} aláírás ({pct}%)"
        }

    @classmethod
    def generate_election_session_id(cls, office_id, year=2026, nonce=1234):
        clean_office = re.sub(r"[^a-zA-Z0-9_]", "", str(office_id or "general").lower())
        return f"election:{clean_office}_{year}_{nonce}"


# ==============================================================================
# PYTEST TEST SUITE
# ==============================================================================

def test_candidate_eligibility_and_term_limits():
    session = {
        "id": "election:mayor_2026",
        "type": "election",
        "status": "active",
        "election_phase": "nomination",
        "office_id": "mayor"
    }

    # 1. Valid registration
    ok, err = DemocraticElectionsEngine.evaluate_candidate_eligibility("CIT_1001", "mayor", session, [])
    assert ok is True
    assert err is None

    # 2. Invalid citizen ID
    ok, err = DemocraticElectionsEngine.evaluate_candidate_eligibility("", "mayor", session)
    assert ok is False
    assert err == "INVALID_CITIZEN_ID"

    # 3. Non-election session type
    invalid_session = dict(session, type="statute_vote")
    ok, err = DemocraticElectionsEngine.evaluate_candidate_eligibility("CIT_1001", "mayor", invalid_session)
    assert ok is False
    assert err == "SESSION_NOT_AN_ELECTION"

    # 4. Closed nomination phase
    closed_session = dict(session, election_phase="concluded")
    ok, err = DemocraticElectionsEngine.evaluate_candidate_eligibility("CIT_1001", "mayor", closed_session)
    assert ok is False
    assert err == "NOMINATION_PERIOD_CLOSED"

    # 5. Maximum candidate capacity reached
    full_candidates = [{"citizen_id": f"CIT_{i}", "status": "nominated"} for i in range(10)]
    ok, err = DemocraticElectionsEngine.evaluate_candidate_eligibility("CIT_9999", "mayor", session, full_candidates)
    assert ok is False
    assert err == "MAX_CANDIDATES_REACHED"

    # 6. Duplicate registration check
    existing = [{"citizen_id": "CIT_1001", "status": "nominated"}]
    ok, err = DemocraticElectionsEngine.evaluate_candidate_eligibility("CIT_1001", "mayor", session, existing)
    assert ok is False
    assert err == "ALREADY_REGISTERED_AS_CANDIDATE"

    # 7. Consecutive term limits exceeded (Mayor allows max 2 terms)
    term_limited_official = {"citizen_id": "CIT_MAYOR_1", "consecutive_terms": 2}
    ok, err = DemocraticElectionsEngine.evaluate_candidate_eligibility(
        "CIT_MAYOR_1", "mayor", session, [], active_official=term_limited_official
    )
    assert ok is False
    assert err == "TERM_LIMIT_EXCEEDED"

    # Official with only 1 term can run again
    eligible_official = {"citizen_id": "CIT_MAYOR_1", "consecutive_terms": 1}
    ok, err = DemocraticElectionsEngine.evaluate_candidate_eligibility(
        "CIT_MAYOR_1", "mayor", session, [], active_official=eligible_official
    )
    assert ok is True


def test_collateral_escrow_calculation():
    # 1. Sufficient balance -> Escrow metadata generated
    ok, data, err = DemocraticElectionsEngine.calculate_collateral_escrow(2500.00, 10000.00, "CIT_1001", "election:mayor_2026")
    assert ok is True
    assert err is None
    assert data["required"] == 2500.00
    assert data["debitAccount"] == "char:CIT_1001:bank"
    assert data["creditAccount"] == "gov:city:master"
    assert data["category"] == "election_collateral"

    # 2. Insufficient balance -> Deficit returned
    ok, data, err = DemocraticElectionsEngine.calculate_collateral_escrow(2500.00, 1200.00, "CIT_1001", "election:mayor_2026")
    assert ok is False
    assert err == "INSUFFICIENT_COLLATERAL_FUNDS"
    assert data["deficit"] == 1300.00

    # 3. Invalid negative amount
    ok, _, err = DemocraticElectionsEngine.calculate_collateral_escrow(-500.00, 5000.00, "CIT_1001", "election:mayor_2026")
    assert ok is False
    assert err == "INVALID_COLLATERAL_AMOUNT"


def test_collateral_refund_and_forfeiture_matrix():
    candidate_base = {
        "candidate_id": "cand_1",
        "citizen_id": "CIT_1001",
        "collateral_deposited": 2500.00,
        "vote_count": 0,
        "status": "nominated"
    }

    # 1. Voluntary withdrawal before voting -> Full refund
    cand_withdrawn = dict(candidate_base, status="withdrawn")
    res = DemocraticElectionsEngine.evaluate_collateral_refund(cand_withdrawn, 100)
    assert res["eligible"] is True
    assert res["amount"] == 2500.00
    assert res["status"] == "refunded"
    assert res["reason"] == "WITHDRAWAL_BEFORE_BALLOT"

    # 2. Disqualified candidate -> Forfeit
    cand_disq = dict(candidate_base, status="disqualified")
    res = DemocraticElectionsEngine.evaluate_collateral_refund(cand_disq, 100)
    assert res["eligible"] is False
    assert res["amount"] == 0.0
    assert res["status"] == "forfeited"
    assert res["reason"] == "CANDIDATE_DISQUALIFIED"

    # 3. Election winner -> Always full refund regardless of vote count
    res = DemocraticElectionsEngine.evaluate_collateral_refund(candidate_base, 100, winner_candidate_id="cand_1")
    assert res["eligible"] is True
    assert res["amount"] == 2500.00
    assert res["status"] == "refunded"
    assert res["reason"] == "ELECTION_WINNER"

    # 4. Meets 10% threshold (15 votes out of 100 = 15%) -> Refund
    cand_met = dict(candidate_base, vote_count=15)
    res = DemocraticElectionsEngine.evaluate_collateral_refund(cand_met, 100, winner_candidate_id="cand_2")
    assert res["eligible"] is True
    assert res["amount"] == 2500.00
    assert res["status"] == "refunded"
    assert res["reason"] == "MET_VOTE_THRESHOLD"
    assert res["sharePct"] == 15.0

    # 5. Below 10% threshold (5 votes out of 100 = 5%) -> Forfeit
    cand_below = dict(candidate_base, vote_count=5)
    res = DemocraticElectionsEngine.evaluate_collateral_refund(cand_below, 100, winner_candidate_id="cand_2")
    assert res["eligible"] is False
    assert res["amount"] == 0.0
    assert res["status"] == "forfeited"
    assert res["reason"] == "BELOW_VOTE_THRESHOLD"
    assert res["sharePct"] == 5.0


def test_spatial_voting_booth_proximity():
    # City Hall booth coords: (-540.9, -199.3, 47.5)
    # 1. Player directly at City Hall booth
    res = DemocraticElectionsEngine.validate_booth_proximity((-540.9, -199.3, 47.5))
    assert res["isNear"] is True
    assert res["boothId"] == "booth:city_hall"
    assert "City Hall" in res["boothLabel"]
    assert res["distance"] == 0.0

    # 2. Player 1.5m away (within 2.5m limit)
    res = DemocraticElectionsEngine.validate_booth_proximity((-540.9, -198.0, 47.5))
    assert res["isNear"] is True
    assert res["boothId"] == "booth:city_hall"
    assert res["distance"] == 1.3

    # 3. Player 100m away in the street
    res = DemocraticElectionsEngine.validate_booth_proximity((-440.9, -199.3, 47.5))
    assert res["isNear"] is False
    assert res["boothId"] is None
    assert res["boothLabel"] == "Remote Terminal"
    assert res["distance"] >= 100.0

    # 4. Player coords missing
    res = DemocraticElectionsEngine.validate_booth_proximity(None)
    assert res["isNear"] is False
    assert res["boothId"] is None


def test_anti_sybil_machine_footprint_hashing():
    # 1. Hardware tokens available
    tokens = ["token_a1", "token_b2", "token_c3"]
    h1 = DemocraticElectionsEngine.generate_hardware_footprint_hash(tokens=tokens)
    assert h1.startswith("HWID-")
    assert len(h1) == 21

    # 2. License identifier fallback
    identifiers = ["ip:127.0.0.1", "license:abcdef1234567890", "discord:9999"]
    h2 = DemocraticElectionsEngine.generate_hardware_footprint_hash(identifiers=identifiers)
    assert h2 == "LIC-abcdef1234567890"

    # 3. Dev anonymous fallback
    h3 = DemocraticElectionsEngine.generate_hardware_footprint_hash(fallback_src=42)
    assert h3 == "ANON-DEV-42"


def test_term_limit_expiration_state_machine():
    now = 1770000000

    # 1. Active official whose term ended 100 seconds ago -> Expired
    expired_official = {
        "citizen_id": "CIT_MAYOR_1",
        "office_id": "mayor",
        "status": "active",
        "term_end_epoch": now - 100,
        "consecutive_terms": 1
    }
    res = DemocraticElectionsEngine.evaluate_term_expiration(expired_official, now)
    assert res["isExpired"] is True
    assert res["remainingSeconds"] == 0

    # 2. Active official with 5 days remaining -> Not expired
    active_official = {
        "citizen_id": "CIT_MAYOR_1",
        "office_id": "mayor",
        "status": "active",
        "term_end_epoch": now + 432000,
        "consecutive_terms": 1
    }
    res = DemocraticElectionsEngine.evaluate_term_expiration(active_official, now)
    assert res["isExpired"] is False
    assert res["remainingSeconds"] == 432000

    # 3. Vacated or inactive official -> Not active
    vacated_official = dict(expired_official, status="vacated")
    res = DemocraticElectionsEngine.evaluate_term_expiration(vacated_official, now)
    assert res["isExpired"] is False
    assert res["reason"] == "NOT_ACTIVE"


def test_recall_petition_eligibility_and_cooldown():
    now = 1770000000
    official = {
        "citizen_id": "CIT_OFFICIAL_1",
        "office_id": "mayor",
        "status": "active",
        "cooldown_until_epoch": None
    }

    # 1. Valid petition by regular citizen
    ok, err = DemocraticElectionsEngine.evaluate_recall_eligibility(official, "CIT_CITIZEN_2", [], now)
    assert ok is True
    assert err is None

    # 2. Official cannot initiate recall against self
    ok, err = DemocraticElectionsEngine.evaluate_recall_eligibility(official, "CIT_OFFICIAL_1", [], now)
    assert ok is False
    assert err == "CANNOT_RECALL_SELF"

    # 3. Cooldown active (survived recall recently)
    official_immune = dict(official, cooldown_until_epoch=now + 50000)
    ok, err = DemocraticElectionsEngine.evaluate_recall_eligibility(official_immune, "CIT_CITIZEN_2", [], now)
    assert ok is False
    assert "RECALL_COOLDOWN_ACTIVE:50000" in err

    # 4. Duplicate active petition already exists
    active_pets = [{"office_id": "mayor", "status": "active"}]
    ok, err = DemocraticElectionsEngine.evaluate_recall_eligibility(official, "CIT_CITIZEN_2", active_pets, now)
    assert ok is False
    assert err == "ACTIVE_PETITION_ALREADY_EXISTS"


def test_recall_referendum_outcomes():
    # 1. Recall passes (YES / RECALL_YES) -> Official vacated, snap election scheduled
    res_pass = DemocraticElectionsEngine.evaluate_recall_referendum_outcome("RECALL_YES", "mayor")
    assert res_pass["passed"] is True
    assert res_pass["vacateOfficial"] is True
    assert res_pass["scheduleSnapElection"] is True
    assert res_pass["action"] == "OFFICIAL_RECALLED"

    # 2. Recall rejected (NO / RETAIN) -> Official retained, 7-day immunity cooldown applied
    res_fail = DemocraticElectionsEngine.evaluate_recall_referendum_outcome("RECALL_NO", "mayor")
    assert res_fail["passed"] is False
    assert res_fail["vacateOfficial"] is False
    assert res_fail["scheduleSnapElection"] is False
    assert res_fail["applyCooldown"] is True
    assert res_fail["cooldownDays"] == 7
    assert res_fail["action"] == "OFFICIAL_RETAINED"


def test_status_badge_and_progress_formatters():
    # 1. Status badges
    badge_nom = DemocraticElectionsEngine.format_election_status_badge("nomination", "active")
    assert badge_nom["badgeClass"] == "badge-info"
    assert "Jelöltállítási" in badge_nom["label"]

    badge_vote = DemocraticElectionsEngine.format_election_status_badge("voting", "active")
    assert badge_vote["badgeClass"] == "badge-success"

    badge_concl = DemocraticElectionsEngine.format_election_status_badge("concluded", "concluded")
    assert badge_concl["badgeClass"] == "badge-concluded"

    # 2. Recall progress bar
    bar = DemocraticElectionsEngine.format_recall_progress_bar(3, 5)
    assert bar["currentSignatures"] == 3
    assert bar["requiredSignatures"] == 5
    assert bar["progressPercent"] == 60.0
    assert bar["isCertified"] is False
    assert bar["remainingSignatures"] == 2

    # Certified threshold reached
    bar_cert = DemocraticElectionsEngine.format_recall_progress_bar(5, 5)
    assert bar_cert["isCertified"] is True
    assert bar_cert["progressPercent"] == 100.0


def test_migration_056_and_index_json_schema():
    """Verify Migration 056 exists in core & parliament, is indexed, and contains required schema."""
    core_mig = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "056_democratic_parliamentary_elections_and_recall_referendums.sql")
    parl_mig = os.path.join(ROOT_DIR, "FiveM", "nyx_parliament", "sql", "migrations", "056_democratic_parliamentary_elections_and_recall_referendums.sql")
    index_file = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "index.json")

    assert os.path.isfile(core_mig), "056 migration missing from nyx_core"
    assert os.path.isfile(parl_mig), "056 migration missing from nyx_parliament"
    assert os.path.isfile(index_file), "migrations index.json missing"

    with open(index_file, "r", encoding="utf-8") as f:
        index_data = json.load(f)

    # Verify step 56 is registered in index.json
    assert "056_democratic_parliamentary_elections_and_recall_referendums.sql" in index_data

    with open(core_mig, "r", encoding="utf-8") as f:
        sql = f.read()

    # Schema changes assertions
    assert "nyx_parliament_sessions" in sql
    assert "election_phase" in sql
    assert "nyx_parliament_candidates" in sql
    assert "collateral_status" in sql
    assert "refund_treasury_tx_id" in sql
    assert "nyx_parliament_ballots" in sql
    assert "booth_id" in sql
    assert "booth_label" in sql
    assert "nyx_parliament_officials" in sql
    assert "cooldown_until" in sql
    assert "consecutive_terms" in sql
    assert "nyx_parliament_term_audits" in sql
    assert "nyx_parliament_booth_terminals" in sql
    assert "booth:city_hall" in sql


def test_parliament_manifest_and_exports_declarations():
    """Verify shared/elections.lua in fxmanifest and proper server/client exports."""
    manifest_file = os.path.join(ROOT_DIR, "FiveM", "nyx_parliament", "fxmanifest.lua")
    assert os.path.isfile(manifest_file), "fxmanifest.lua missing"

    with open(manifest_file, "r", encoding="utf-8") as f:
        manifest = f.read()

    assert "shared/elections.lua" in manifest

    server_exports_file = os.path.join(ROOT_DIR, "FiveM", "nyx_parliament", "server", "exports.lua")
    with open(server_exports_file, "r", encoding="utf-8") as f:
        srv_exports = f.read()

    assert "WithdrawCandidacy" in srv_exports
    assert "ScheduleElectionSession" in srv_exports
    assert "VacateOfficial" in srv_exports
    assert "ReconcileElectionCollaterals" in srv_exports
    assert "GetBoothTerminals" in srv_exports
    assert "GetTermAudits" in srv_exports

    client_exports_file = os.path.join(ROOT_DIR, "FiveM", "nyx_parliament", "client", "exports.lua")
    with open(client_exports_file, "r", encoding="utf-8") as f:
        cli_exports = f.read()

    assert "GetCurrentBooth" in cli_exports
    assert "WithdrawCandidacy" in cli_exports


def test_ui_bridge_and_js_integration():
    """Verify nyx_ui client bridge and app.js handlers for elections and recall referendums."""
    bridge_lua = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "client", "bridge.lua")
    with open(bridge_lua, "r", encoding="utf-8") as f:
        bridge = f.read()

    assert 'Nyx.UI.SafeNUICallback("parliament:withdrawCandidacy"' in bridge
    assert 'Nyx.UI.SafeNUICallback("parliament:getBoothTerminals"' in bridge
    assert 'Nyx.UI.SafeNUICallback("parliament:getTermAudits"' in bridge
    assert "boothId" in bridge
    assert "boothLabel" in bridge

    app_js = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "web", "js", "app.js")
    with open(app_js, "r", encoding="utf-8") as f:
        js = f.read()

    assert "function openParliamentUI(" in js
    assert "boothId" in js
    assert "boothLabel" in js
    assert "termAudits" in js
    assert "parliament:getBoothTerminals" in js
    assert "booth:city_hall" in js


def test_in_engine_suite_test_51_registration():
    """Verify tests.lua in nyx_core declares and executes Test 51."""
    tests_lua = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "server", "tests.lua")
    with open(tests_lua, "r", encoding="utf-8") as f:
        content = f.read()

    assert "function Nyx.Tests.TestDemocraticParliamentaryElectionsAndRecallReferendums()" in content
    assert "local t51 = Nyx.Tests.TestDemocraticParliamentaryElectionsAndRecallReferendums()" in content
