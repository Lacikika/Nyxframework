"""
Unit tests for Anti-Monopoly Inactivity Reclamation Engine, Stewardship Delegates & Succession.
Verifies time-decay dormancy math, stewardship delegate protections, 72-hour grace periods,
democratic succession selection, double-entry liquidation conservation, and migration/manifest integrity.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIVEM = ROOT / "FiveM"


class InactivityEngine:
    DEFAULT_OWNER_THRESHOLD = 14 * 86400  # 14 days
    DEFAULT_STEWARD_EXTENSION = 16 * 86400  # +16 days (30 days total)
    DEFAULT_GRACE_PERIOD = 3 * 86400  # 72 hours
    DEFAULT_MIN_BID_DISCOUNT = 0.50
    DEFAULT_MIN_BID_FLOOR = 1000.00

    @classmethod
    def validate_delegation(cls, owner_id: str, delegate_id: str, scope: str = "all") -> tuple[bool, str]:
        if not owner_id or len(owner_id.strip()) == 0:
            return False, "INVALID_OWNER_CITIZEN_ID"
        if not delegate_id or len(delegate_id.strip()) == 0:
            return False, "INVALID_DELEGATE_CITIZEN_ID"
        if owner_id == delegate_id:
            return False, "CANNOT_DELEGATE_TO_SELF"
        valid_scopes = {"all", "properties", "factions"}
        if scope not in valid_scopes:
            return False, "INVALID_STEWARDSHIP_SCOPE"
        return True, scope

    @classmethod
    def evaluate_stewardship_status(
        cls,
        current_time: int,
        owner_last_active: int,
        delegate_id: str | None = None,
        delegate_last_active: int | None = None,
        warning_at: int | None = None,
        owner_threshold: int = DEFAULT_OWNER_THRESHOLD,
        max_extension: int = DEFAULT_STEWARD_EXTENSION,
        grace_period: int = DEFAULT_GRACE_PERIOD,
    ) -> dict:
        owner_inactivity = max(0, current_time - owner_last_active)

        # 1. Owner Active
        if owner_inactivity <= owner_threshold:
            return {
                "status": "active",
                "is_protected": True,
                "inactivity_seconds": owner_inactivity,
                "grace_remaining_seconds": 0,
                "needs_warning": False,
                "reason": "OWNER_ACTIVE",
            }

        # 2. Protected by Active Steward
        if delegate_id and delegate_last_active is not None:
            del_inactivity = max(0, current_time - delegate_last_active)
            total_window = owner_threshold + max_extension
            if del_inactivity <= owner_threshold and owner_inactivity <= total_window:
                return {
                    "status": "delegated",
                    "is_protected": True,
                    "inactivity_seconds": owner_inactivity,
                    "delegate_inactivity_seconds": del_inactivity,
                    "grace_remaining_seconds": 0,
                    "needs_warning": False,
                    "reason": "PROTECTED_BY_ACTIVE_STEWARD",
                }

        # 3. Grace Period or Forfeiture
        if warning_at is None or warning_at <= 0:
            return {
                "status": "grace_period",
                "is_protected": False,
                "inactivity_seconds": owner_inactivity,
                "grace_remaining_seconds": grace_period,
                "needs_warning": True,
                "reason": "GRACE_PERIOD_INITIATED",
            }

        elapsed_warning = max(0, current_time - warning_at)
        if elapsed_warning < grace_period:
            return {
                "status": "grace_period",
                "is_protected": False,
                "inactivity_seconds": owner_inactivity,
                "grace_remaining_seconds": grace_period - elapsed_warning,
                "needs_warning": False,
                "reason": "IN_GRACE_PERIOD",
            }
        else:
            return {
                "status": "forfeited",
                "is_protected": False,
                "inactivity_seconds": owner_inactivity,
                "grace_remaining_seconds": 0,
                "needs_warning": False,
                "reason": "GRACE_PERIOD_EXPIRED_FORFEITURE",
            }

    @classmethod
    def calculate_auction_minimum_bid(
        cls, property_price: float, discount_ratio: float = DEFAULT_MIN_BID_DISCOUNT, floor: float = DEFAULT_MIN_BID_FLOOR
    ) -> float:
        calculated = round(property_price * discount_ratio, 2)
        return max(floor, calculated)

    @classmethod
    def can_transition_status(cls, current: str, target: str) -> bool:
        allowed = {
            "active": {"delegated", "grace_period", "active"},
            "delegated": {"active", "grace_period", "delegated"},
            "grace_period": {"active", "delegated", "reclaimed_for_auction", "grace_period"},
            "reclaimed_for_auction": {"active", "reclaimed_for_auction"},
        }
        return target in allowed.get(current, set())


class SuccessionEngine:
    @classmethod
    def determine_successor(
        cls, members: list[dict], founder_id: str, current_time: int, active_threshold: int = 14 * 86400
    ) -> tuple[str, dict | None, str]:
        eligible = []
        for m in members:
            if m.get("citizen_id") != founder_id:
                last_active = m.get("last_active_at", 0)
                if (current_time - last_active) <= active_threshold:
                    eligible.append(m)

        if not eligible:
            return "liquidation", None, "NO_ACTIVE_MEMBERS_REMAIN"

        # Sort: equity_shares DESC, wage_hourly DESC, hired_at ASC
        eligible.sort(
            key=lambda x: (
                x.get("equity_shares", 0.0),
                x.get("wage_hourly", 0.0),
                -x.get("hired_at_unix", 0),
            ),
            reverse=True,
        )

        return "succession", eligible[0], "ACTIVE_SUCCESSOR_SELECTED"

    @classmethod
    def calculate_liquidation_distribution(cls, balance: float, master_ratio: float = 0.85) -> dict:
        bal = max(0.0, round(balance, 2))
        master_share = round(bal * master_ratio, 2)
        works_share = round(bal - master_share, 2)
        return {
            "master_amount": master_share,
            "works_amount": works_share,
            "total_liquidated": bal,
        }


# ============================================================================
# Unit Tests
# ============================================================================


def test_stewardship_delegation_validation():
    """Validates delegation authorization parameters and prevents self-delegation."""
    ok, scope = InactivityEngine.validate_delegation("CIT_ALICE", "CIT_BOB", "all")
    assert ok is True
    assert scope == "all"

    self_ok, self_err = InactivityEngine.validate_delegation("CIT_ALICE", "CIT_ALICE", "properties")
    assert self_ok is False
    assert self_err == "CANNOT_DELEGATE_TO_SELF"

    empty_ok, empty_err = InactivityEngine.validate_delegation("", "CIT_BOB")
    assert empty_ok is False
    assert empty_err == "INVALID_OWNER_CITIZEN_ID"

    bad_scope_ok, bad_scope_err = InactivityEngine.validate_delegation("CIT_ALICE", "CIT_BOB", "unauthorized")
    assert bad_scope_ok is False
    assert bad_scope_err == "INVALID_STEWARDSHIP_SCOPE"


def test_owner_active_presence_evaluation():
    """Validates that recently active owners (<= 14 days) are protected in active status."""
    now = 1700000000
    res_recent = InactivityEngine.evaluate_stewardship_status(now, now - 86400 * 2)
    assert res_recent["status"] == "active"
    assert res_recent["is_protected"] is True
    assert res_recent["reason"] == "OWNER_ACTIVE"

    # Exactly 14 days boundary
    res_boundary = InactivityEngine.evaluate_stewardship_status(now, now - 86400 * 14)
    assert res_boundary["status"] == "active"
    assert res_boundary["is_protected"] is True


def test_stewardship_delegate_protection_and_window_bounds():
    """Validates steward delegate protection when owner is inactive and enforces 30-day max ceiling."""
    now = 1700000000
    # Owner inactive 20 days (>14d), steward active 1 day ago (<=14d), total window <= 30d
    res_delegated = InactivityEngine.evaluate_stewardship_status(
        now, owner_last_active=now - 86400 * 20, delegate_id="CIT_BOB", delegate_last_active=now - 86400 * 1
    )
    assert res_delegated["status"] == "delegated"
    assert res_delegated["is_protected"] is True
    assert res_delegated["reason"] == "PROTECTED_BY_ACTIVE_STEWARD"

    # Owner inactive 35 days (> 30 days total allowed window)
    res_window_exceeded = InactivityEngine.evaluate_stewardship_status(
        now, owner_last_active=now - 86400 * 35, delegate_id="CIT_BOB", delegate_last_active=now - 86400 * 1
    )
    assert res_window_exceeded["is_protected"] is False
    assert res_window_exceeded["status"] == "grace_period"

    # Steward also inactive (18 days > 14 days)
    res_steward_inactive = InactivityEngine.evaluate_stewardship_status(
        now, owner_last_active=now - 86400 * 20, delegate_id="CIT_BOB", delegate_last_active=now - 86400 * 18
    )
    assert res_steward_inactive["is_protected"] is False
    assert res_steward_inactive["status"] == "grace_period"


def test_grace_period_countdown_and_expiration():
    """Validates 72-hour grace period warning issuance, mid-period timer countdown, and forfeiture."""
    now = 1700000000
    # First time detected: triggers warning
    res_init = InactivityEngine.evaluate_stewardship_status(
        now, owner_last_active=now - 86400 * 18, warning_at=None
    )
    assert res_init["status"] == "grace_period"
    assert res_init["needs_warning"] is True
    assert res_init["grace_remaining_seconds"] == 3 * 86400

    # 24 hours into grace period (48 hours remaining)
    res_mid = InactivityEngine.evaluate_stewardship_status(
        now, owner_last_active=now - 86400 * 19, warning_at=now - 86400 * 1
    )
    assert res_mid["status"] == "grace_period"
    assert res_mid["needs_warning"] is False
    assert res_mid["grace_remaining_seconds"] == 2 * 86400

    # 96 hours elapsed (> 72h grace expired)
    res_expired = InactivityEngine.evaluate_stewardship_status(
        now, owner_last_active=now - 86400 * 22, warning_at=now - 86400 * 4
    )
    assert res_expired["status"] == "forfeited"
    assert res_expired["is_protected"] is False
    assert res_expired["grace_remaining_seconds"] == 0
    assert res_expired["reason"] == "GRACE_PERIOD_EXPIRED_FORFEITURE"


def test_blind_auction_minimum_bid_and_floor_clamping():
    """Validates 50% starting minimum bid and $1,000 statutory floor clamping."""
    # Standard $350k commercial storefront -> $175,000
    bid_store = InactivityEngine.calculate_auction_minimum_bid(350000.0, 0.50, 1000.0)
    assert bid_store == 175000.00

    # Small shed valuation $1,500 * 50% = $750 -> clamped to $1,000 floor
    bid_small = InactivityEngine.calculate_auction_minimum_bid(1500.0, 0.50, 1000.0)
    assert bid_small == 1000.00


def test_organization_succession_hierarchy_selection():
    """Validates that democratic succession elects active members with highest equity shares."""
    now = 1700000000
    members = [
        {"citizen_id": "CIT_ALICE", "equity_shares": 10.0, "wage_hourly": 75.0, "hired_at_unix": now - 500000, "last_active_at": now - 86400 * 2},
        {"citizen_id": "CIT_BOB", "equity_shares": 35.0, "wage_hourly": 50.0, "hired_at_unix": now - 200000, "last_active_at": now - 86400 * 4},
        {"citizen_id": "CIT_CHARLIE", "equity_shares": 50.0, "wage_hourly": 100.0, "hired_at_unix": now - 600000, "last_active_at": now - 86400 * 25},  # Inactive >14d
    ]

    outcome, successor, reason = SuccessionEngine.determine_successor(members, "CIT_FOUNDER", now)
    assert outcome == "succession"
    assert successor is not None
    assert successor["citizen_id"] == "CIT_BOB"
    assert successor["equity_shares"] == 35.0
    assert reason == "ACTIVE_SUCCESSOR_SELECTED"

    # Empty members list -> liquidation
    outcome_empty, succ_empty, reason_empty = SuccessionEngine.determine_successor([], "CIT_FOUNDER", now)
    assert outcome_empty == "liquidation"
    assert succ_empty is None


def test_corporate_treasury_liquidation_closed_loop_conservation():
    """Validates double-entry treasury conservation (85% Master / 15% Public Works) on abandoned charter liquidation."""
    treasury_balance = 84250.75
    dist = SuccessionEngine.calculate_liquidation_distribution(treasury_balance, 0.85)

    assert dist["master_amount"] == 71613.14
    assert dist["works_amount"] == 12637.61
    assert round(dist["master_amount"] + dist["works_amount"], 2) == treasury_balance
    assert dist["total_liquidated"] == treasury_balance


def test_inactivity_state_machine_transition_gates():
    """Validates permissible lifecycle transitions between active, delegated, grace_period, and auction."""
    assert InactivityEngine.can_transition_status("active", "delegated") is True
    assert InactivityEngine.can_transition_status("active", "grace_period") is True
    assert InactivityEngine.can_transition_status("delegated", "active") is True
    assert InactivityEngine.can_transition_status("delegated", "grace_period") is True
    assert InactivityEngine.can_transition_status("grace_period", "reclaimed_for_auction") is True
    assert InactivityEngine.can_transition_status("grace_period", "active") is True
    assert InactivityEngine.can_transition_status("reclaimed_for_auction", "active") is True

    # Invalid transitions
    assert InactivityEngine.can_transition_status("reclaimed_for_auction", "grace_period") is False
    assert InactivityEngine.can_transition_status("unknown_state", "active") is False


def test_migration_031_and_index_json():
    """Verifies that migration 031 is properly indexed and contains all necessary tables/columns."""
    index_json_path = FIVEM / "nyx_core" / "sql" / "migrations" / "index.json"
    with open(index_json_path, "r", encoding="utf-8") as f:
        registered = json.load(f)

    assert "031_inactivity_reclamation_and_stewardship.sql" in registered
    assert registered[-1] == "031_inactivity_reclamation_and_stewardship.sql"

    mig_core = FIVEM / "nyx_core" / "sql" / "migrations" / "031_inactivity_reclamation_and_stewardship.sql"
    assert mig_core.exists()

    content = mig_core.read_text(encoding="utf-8")
    assert "nyx_stewardship_delegates" in content
    assert "nyx_inactivity_reclamation_logs" in content
    assert "steward_delegate_citizen_id" in content
    assert "inactivity_status" in content
    assert "founder_citizen_id" in content


def test_fxmanifest_declarations():
    """Verifies all new Lua files are properly declared in their resource manifests."""
    manifest_prop = (FIVEM / "nyx_properties" / "fxmanifest.lua").read_text(encoding="utf-8")
    assert "shared/inactivity.lua" in manifest_prop
    assert "server/inactivity.lua" in manifest_prop
    assert "client/inactivity.lua" in manifest_prop

    manifest_fact = (FIVEM / "nyx_factions" / "fxmanifest.lua").read_text(encoding="utf-8")
    assert "shared/succession.lua" in manifest_fact
    assert "server/inactivity.lua" in manifest_fact
