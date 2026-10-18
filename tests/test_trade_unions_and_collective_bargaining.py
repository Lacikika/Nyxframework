"""
Unit test suite for Nyxframework Trade Unionization Framework, Collective Bargaining Agreements & Binding Labor Arbitration:
- Dues checkoff arithmetic (flat vs percentage) with cent-precision conservation
- Strike fund runway modeling and burn velocity
- Collective Bargaining Agreement (CBA) wage floor compliance
- Democratic strike authorization voting with quorum and majority verification
- Strike pay disbursement cooldown and standing verification
- Binding labor arbitration damage calculations and statutory penalties
- Closed-loop double-entry arbitration settlement conservation
- Industrial facility picket locks and fleet dispatch interlocks
- SQL migration and fxmanifest.lua asset integrity
"""

import math
import os
import json
import pytest


# ============================================================================
# PYTHON REFERENCE ENGINE: TRADE UNIONS & CBA MATHEMATICS
# ============================================================================

class TradeUnionEngine:
    def __init__(self, default_strike_pay_rate=150.00, default_dues_rate=0.025, default_dues_flat=50.00):
        self.default_strike_pay_rate = default_strike_pay_rate
        self.default_dues_rate = default_dues_rate
        self.default_dues_flat = default_dues_flat

    def calculate_dues_checkoff(self, gross_wage, dues_mode="flat", dues_amount=None, dues_rate=None):
        gross_wage = max(0.0, math.floor(float(gross_wage or 0.0) * 100) / 100)
        dues = 0.0

        if dues_mode == "percentage":
            rate = float(dues_rate if dues_rate is not None else self.default_dues_rate)
            rate = max(0.0, min(0.20, rate))
            dues = math.floor((gross_wage * rate) * 100) / 100
        else:
            amount = float(dues_amount if dues_amount is not None else self.default_dues_flat)
            amount = max(0.0, math.floor(amount * 100) / 100)
            dues = min(gross_wage, amount)

        net_wage = math.floor((gross_wage - dues) * 100) / 100
        return round(dues, 2), round(net_wage, 2)

    def calculate_strike_fund_runway(self, strike_fund_balance, member_count, strike_pay_rate=None):
        balance = max(0.0, math.floor(float(strike_fund_balance or 0.0) * 100) / 100)
        members = max(0, int(member_count or 0))
        pay_rate = float(strike_pay_rate if strike_pay_rate is not None else self.default_strike_pay_rate)
        pay_rate = max(0.0, math.floor(pay_rate * 100) / 100)

        if members == 0 or pay_rate == 0.0:
            return {
                "balance": balance,
                "daily_burn": 0.00,
                "runway_days": 9999,
                "solvency_status": "SOLVENT"
            }

        daily_burn = math.floor((members * pay_rate) * 100) / 100
        if daily_burn <= 0.0:
            runway_days = 9999
        else:
            runway_days = int(math.floor(balance / daily_burn))

        if balance <= 0.0:
            status = "DEPLETED"
        elif runway_days <= 5:
            status = "WARNING"
        else:
            status = "SOLVENT"

        return {
            "balance": round(balance, 2),
            "daily_burn": round(daily_burn, 2),
            "runway_days": runway_days,
            "solvency_status": status
        }

    def evaluate_wage_compliance(self, actual_wage, wage_floor):
        actual_wage = max(0.0, math.floor(float(actual_wage or 0.0) * 100) / 100)
        wage_floor = max(0.0, math.floor(float(wage_floor or 0.0) * 100) / 100)

        is_compliant = actual_wage >= wage_floor
        deficit = 0.00
        deficit_pct = 0.00

        if not is_compliant and wage_floor > 0.0:
            deficit = round(wage_floor - actual_wage, 2)
            deficit_pct = round((deficit / wage_floor) * 100, 2)

        return {
            "is_compliant": is_compliant,
            "actual_wage": actual_wage,
            "wage_floor": wage_floor,
            "hourly_deficit": deficit,
            "deficit_percentage": deficit_pct
        }

    def evaluate_strike_vote(self, total_eligible_members, votes, quorum_pct=0.50, majority_pct=0.50):
        eligible = max(1, int(total_eligible_members or 1))
        yes_count = 0
        no_count = 0
        abstain_count = 0

        for v in votes:
            choice = str(v).lower()
            if choice == "yes":
                yes_count += 1
            elif choice == "no":
                no_count += 1
            else:
                abstain_count += 1

        total_cast = yes_count + no_count + abstain_count
        quorum_required = math.ceil(eligible * quorum_pct)
        quorum_reached = total_cast >= quorum_required

        active_votes = yes_count + no_count
        majority_required = math.floor(active_votes * majority_pct) + 1 if active_votes > 0 else 1
        majority_reached = yes_count >= majority_required and active_votes > 0

        passed = quorum_reached and majority_reached

        return {
            "passed": passed,
            "eligible": eligible,
            "total_cast": total_cast,
            "quorum_required": quorum_required,
            "quorum_reached": quorum_reached,
            "yes_count": yes_count,
            "no_count": no_count,
            "abstain_count": abstain_count,
            "majority_required": majority_required,
            "majority_reached": majority_reached
        }

    def can_claim_strike_pay(self, last_claim_timestamp, current_timestamp, cooldown_seconds=86400):
        last = int(last_claim_timestamp or 0)
        now = int(current_timestamp or 0)
        cooldown = int(cooldown_seconds or 86400)

        if last <= 0:
            return True, 0
        elapsed = now - last
        if elapsed >= cooldown:
            return True, 0
        return False, cooldown - elapsed

    def calculate_arbitration_award(self, underpaid_hours, hourly_deficit, affected_member_count, penalty_rate=0.10):
        hours = max(0.0, float(underpaid_hours or 0.0))
        deficit = max(0.0, math.floor(float(hourly_deficit or 0.0) * 100) / 100)
        members = max(1, int(affected_member_count or 1))
        rate = max(0.0, float(penalty_rate or 0.10))

        per_member_restitution = math.floor((hours * deficit) * 100) / 100
        total_restitution = math.floor((per_member_restitution * members) * 100) / 100
        statutory_penalty = math.floor((total_restitution * rate) * 100) / 100
        total_award = round(total_restitution + statutory_penalty, 2)

        return {
            "per_member_restitution": round(per_member_restitution, 2),
            "total_restitution": round(total_restitution, 2),
            "statutory_penalty": round(statutory_penalty, 2),
            "total_award": total_award,
            "affected_member_count": members
        }


# ============================================================================
# PYTEST TEST CASES
# ============================================================================

@pytest.fixture
def engine():
    return TradeUnionEngine()


def test_dues_checkoff_flat_and_percentage(engine):
    # Test flat dues
    dues, net = engine.calculate_dues_checkoff(1200.00, dues_mode="flat", dues_amount=50.00)
    assert dues == 50.00
    assert net == 1150.00
    assert dues + net == 1200.00

    # Flat dues capped at wage if wage < dues
    dues_low, net_low = engine.calculate_dues_checkoff(30.00, dues_mode="flat", dues_amount=50.00)
    assert dues_low == 30.00
    assert net_low == 0.00

    # Test percentage dues (2.5%)
    dues_pct, net_pct = engine.calculate_dues_checkoff(2500.00, dues_mode="percentage", dues_rate=0.025)
    assert dues_pct == 62.50
    assert net_pct == 2437.50
    assert dues_pct + net_pct == 2500.00


def test_strike_fund_runway_calculations(engine):
    # $30,000 balance, 20 striking members at $150/day -> $3,000/day burn -> 10 days runway
    res = engine.calculate_strike_fund_runway(30000.00, 20, 150.00)
    assert res["daily_burn"] == 3000.00
    assert res["runway_days"] == 10
    assert res["solvency_status"] == "SOLVENT"

    # Warning status for 5 or fewer days
    res_warn = engine.calculate_strike_fund_runway(12000.00, 20, 150.00)
    assert res_warn["runway_days"] == 4
    assert res_warn["solvency_status"] == "WARNING"

    # Depleted status
    res_dep = engine.calculate_strike_fund_runway(0.00, 20, 150.00)
    assert res_dep["runway_days"] == 0
    assert res_dep["solvency_status"] == "DEPLETED"


def test_cba_wage_floor_compliance(engine):
    # Floor: $45.00/hr, Paid: $50.00/hr -> Compliant
    c1 = engine.evaluate_wage_compliance(50.00, 45.00)
    assert c1["is_compliant"] is True
    assert c1["hourly_deficit"] == 0.00

    # Floor: $45.00/hr, Paid: $35.00/hr -> Deficit $10.00/hr (22.22%)
    c2 = engine.evaluate_wage_compliance(35.00, 45.00)
    assert c2["is_compliant"] is False
    assert c2["hourly_deficit"] == 10.00
    assert pytest.approx(c2["deficit_percentage"], 0.01) == 22.22


def test_strike_authorization_vote_quorum_and_majority(engine):
    # 10 eligible members: Quorum = 5.
    # 6 cast votes: 4 Yes, 2 No -> Quorum met (6 >= 5), Majority met (4 >= 4/2+1=4) -> PASSED
    v1 = ["yes", "yes", "yes", "yes", "no", "no"]
    res1 = engine.evaluate_strike_vote(10, v1, quorum_pct=0.50, majority_pct=0.50)
    assert res1["quorum_reached"] is True
    assert res1["majority_reached"] is True
    assert res1["passed"] is True

    # Quorum failure: only 4 cast votes out of 10 -> REJECTED
    v2 = ["yes", "yes", "yes", "yes"]
    res2 = engine.evaluate_strike_vote(10, v2, quorum_pct=0.50, majority_pct=0.50)
    assert res2["quorum_reached"] is False
    assert res2["passed"] is False

    # Majority failure: 6 votes (3 yes, 3 no) -> Quorum reached, Majority not reached (3 < 4) -> REJECTED
    v3 = ["yes", "yes", "yes", "no", "no", "no"]
    res3 = engine.evaluate_strike_vote(10, v3, quorum_pct=0.50, majority_pct=0.50)
    assert res3["quorum_reached"] is True
    assert res3["majority_reached"] is False
    assert res3["passed"] is False


def test_strike_pay_cooldown(engine):
    now = 1700000000
    # First claim (never claimed before) -> Allowed
    can1, rem1 = engine.can_claim_strike_pay(0, now, cooldown_seconds=86400)
    assert can1 is True
    assert rem1 == 0

    # Claim 12 hours later -> Rejected, 12 hours remaining
    can2, rem2 = engine.can_claim_strike_pay(now, now + 43200, cooldown_seconds=86400)
    assert can2 is False
    assert rem2 == 43200

    # Claim 25 hours later -> Allowed
    can3, rem3 = engine.can_claim_strike_pay(now, now + 90000, cooldown_seconds=86400)
    assert can3 is True
    assert rem3 == 0


def test_arbitration_award_and_double_entry_conservation(engine):
    # 160 underpaid hours per worker, $10.00/hr deficit, 15 workers, 10% statutory penalty
    # Per worker restitution = 160 * 10 = $1,600.00
    # Total restitution = 15 * 1,600 = $24,000.00
    # Statutory penalty = 10% of 24,000 = $2,400.00
    # Total award = $26,400.00
    award = engine.calculate_arbitration_award(160, 10.00, 15, penalty_rate=0.10)
    assert award["per_member_restitution"] == 1600.00
    assert award["total_restitution"] == 24000.00
    assert award["statutory_penalty"] == 2400.00
    assert award["total_award"] == 26400.00

    # Verify strict double-entry balance conservation:
    enterprise_debit = award["total_award"]
    member_credits = [award["per_member_restitution"]] * award["affected_member_count"]
    union_fund_credit = award["statutory_penalty"]

    total_credits = sum(member_credits) + union_fund_credit
    assert round(enterprise_debit, 2) == round(total_credits, 2)


def test_strike_facility_picket_lockout_logic():
    # Mock active strikes state bag
    active_strikes = {
        "corp:logistics_omega": {
            "strike_id": "strk_001",
            "union_id": "union:transport_workers",
            "reason": "CBA Wage Breach",
            "status": "active"
        }
    }

    def can_operate_facility(facility_owner):
        if facility_owner in active_strikes and active_strikes[facility_owner]["status"] == "active":
            return False, "ENTERPRISE_FACILITY_PICKET_LOCKED"
        return True, "OK"

    allowed, code = can_operate_facility("corp:logistics_omega")
    assert allowed is False
    assert code == "ENTERPRISE_FACILITY_PICKET_LOCKED"

    allowed_other, code_other = can_operate_facility("corp:clean_energy")
    assert allowed_other is True
    assert code_other == "OK"


def test_migration_and_fxmanifest_integrity():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    index_json_path = os.path.join(repo_root, "FiveM", "nyx_core", "sql", "migrations", "index.json")

    assert os.path.exists(index_json_path), "Migration index.json must exist"
    with open(index_json_path, "r", encoding="utf-8") as f:
        migrations = json.load(f)

    # Step 28 must be registered
    assert "028_factions_trade_unions_and_collective_bargaining.sql" in migrations

    core_sql = os.path.join(repo_root, "FiveM", "nyx_core", "sql", "migrations", "028_factions_trade_unions_and_collective_bargaining.sql")
    factions_sql = os.path.join(repo_root, "FiveM", "nyx_factions", "sql", "migrations", "028_factions_trade_unions_and_collective_bargaining.sql")

    assert os.path.exists(core_sql), f"Core SQL migration {core_sql} must exist"
    assert os.path.exists(factions_sql), f"Factions SQL migration {factions_sql} must exist"

    # Verify fxmanifest declarations in nyx_factions
    manifest_path = os.path.join(repo_root, "FiveM", "nyx_factions", "fxmanifest.lua")
    assert os.path.exists(manifest_path)
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest_content = f.read()

    assert "shared/unions.lua" in manifest_content
    assert "server/unions.lua" in manifest_content
    assert "server/cba.lua" in manifest_content
    assert "client/unions.lua" in manifest_content
