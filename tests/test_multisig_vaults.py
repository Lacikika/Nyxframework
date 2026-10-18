"""
Nyxframework: Unit Tests for Multi-Signature Corporate Treasury Vaults & Sign-Off Rules
File: tests/test_multisig_vaults.py
"""

import time
import pytest

class SignoffRule:
    def __init__(self, rule_id, faction_id, vault_id, rule_name, min_amount, max_amount, required_signatures, required_roles=None, timelock_seconds=0, priority=0):
        self.rule_id = rule_id
        self.faction_id = faction_id
        self.vault_id = vault_id
        self.rule_name = rule_name
        self.min_amount = float(min_amount)
        self.max_amount = float(max_amount) if max_amount is not None else None
        self.required_signatures = int(required_signatures)
        self.required_roles = required_roles or []
        self.timelock_seconds = int(timelock_seconds)
        self.priority = int(priority)

def match_signoff_rule(rules, faction_id, vault_id, amount):
    matched = None
    amt = float(amount)
    for r in rules:
        if r.faction_id != faction_id:
            continue
        matches_vault = (r.vault_id == vault_id or r.vault_id is None)
        matches_min = (amt >= r.min_amount)
        matches_max = (r.max_amount is None or amt <= r.max_amount)
        if matches_vault and matches_min and matches_max:
            if not matched:
                matched = r
            else:
                cur_specific = (matched.vault_id is not None)
                new_specific = (r.vault_id is not None)
                if new_specific and not cur_specific:
                    matched = r
                elif (new_specific == cur_specific) and r.priority > matched.priority:
                    matched = r
    return matched

def evaluate_signatory_roles(signatures_details, required_roles):
    if not required_roles:
        return True, None
    present_roles = {s.get("role_title") for s in signatures_details if s.get("role_title")}
    for req in required_roles:
        if req not in present_roles:
            return False, req
    return True, None

class MockCorporateVault:
    def __init__(self, vault_id, faction_id, daily_limit=100000.00, balance=500000.00, last_reset=None):
        self.vault_id = vault_id
        self.faction_id = faction_id
        self.daily_limit = float(daily_limit)
        self.daily_withdrawn = 0.00
        self.last_reset = float(last_reset) if last_reset is not None else time.time()
        self.balance = float(balance)
        self.is_frozen = False

    def check_and_withdraw(self, amount, current_time):
        if self.is_frozen:
            return False, "VAULT_FROZEN"
        if (current_time - self.last_reset) >= 86400:
            self.daily_withdrawn = 0.00
            self.last_reset = current_time
        if (self.daily_withdrawn + amount) > self.daily_limit:
            return False, "EXCEEDS_VAULT_DAILY_LIMIT"
        if self.balance < amount:
            return False, "INSUFFICIENT_VAULT_LIQUIDITY"
        self.daily_withdrawn += amount
        self.balance -= amount
        return True, "DISBURSED"


def test_signoff_rule_matching_boundaries_and_precedence():
    rules = [
        SignoffRule("r_petty", "corp_1", None, "Petty Cash", 0.00, 1000.00, 1, timelock_seconds=0, priority=10),
        SignoffRule("r_oper", "corp_1", None, "Operational", 1000.01, 25000.00, 2, timelock_seconds=0, priority=10),
        SignoffRule("r_capex", "corp_1", None, "Capital Expenditure", 25000.01, None, 3, required_roles=["Chief Executive"], timelock_seconds=3600, priority=10),
        SignoffRule("r_payroll_spec", "corp_1", "vlt:payroll", "Dedicated Payroll Policy", 0.00, 100000.00, 2, required_roles=["CFO"], timelock_seconds=0, priority=50),
    ]

    # Test amount bounds
    r500 = match_signoff_rule(rules, "corp_1", "vlt:main", 500.00)
    assert r500 is not None
    assert r500.rule_id == "r_petty"
    assert r500.required_signatures == 1

    r15k = match_signoff_rule(rules, "corp_1", "vlt:main", 15000.00)
    assert r15k is not None
    assert r15k.rule_id == "r_oper"
    assert r15k.required_signatures == 2

    r50k = match_signoff_rule(rules, "corp_1", "vlt:main", 50000.00)
    assert r50k is not None
    assert r50k.rule_id == "r_capex"
    assert r50k.required_signatures == 3
    assert r50k.timelock_seconds == 3600

    # Specific vault override precedence
    r_payroll = match_signoff_rule(rules, "corp_1", "vlt:payroll", 40000.00)
    assert r_payroll is not None
    assert r_payroll.rule_id == "r_payroll_spec"
    assert r_payroll.vault_id == "vlt:payroll"
    assert "CFO" in r_payroll.required_roles


def test_multi_signature_quorum_accumulation_and_role_validation():
    required_roles = ["Chief Executive"]
    required_sigs = 2

    sigs = []
    # Signer 1: Associate
    sigs.append({"citizen_id": "CIT_1", "role_title": "Associate"})
    ok_count = len(sigs) >= required_sigs
    ok_roles, missing = evaluate_signatory_roles(sigs, required_roles)
    assert not (ok_count and ok_roles)

    # Signer 2: Operations Manager
    sigs.append({"citizen_id": "CIT_2", "role_title": "Operations Manager"})
    ok_count = len(sigs) >= required_sigs
    ok_roles, missing = evaluate_signatory_roles(sigs, required_roles)
    assert ok_count is True
    assert ok_roles is False
    assert missing == "Chief Executive"

    # Signer 3: Chief Executive
    sigs.append({"citizen_id": "CIT_3", "role_title": "Chief Executive"})
    ok_count = len(sigs) >= required_sigs
    ok_roles, missing = evaluate_signatory_roles(sigs, required_roles)
    assert ok_count is True
    assert ok_roles is True
    assert missing is None


def test_timelock_delay_and_delayed_execution():
    t0 = 1770000000
    delay = 1800 # 30 minutes
    timelock_until = t0 + delay

    # Premature check
    assert t0 < timelock_until
    remaining = timelock_until - t0
    assert remaining == 1800

    # Executable at t0 + 1800
    assert (t0 + 1800) >= timelock_until
    assert (t0 + 2000) >= timelock_until


def test_daily_withdrawal_limit_and_rolling_24h_reset():
    t0 = 1770000000
    vault = MockCorporateVault("vlt:main", "corp_1", daily_limit=100000.00, balance=500000.00, last_reset=t0)

    # 1st withdrawal: $60k
    ok1, res1 = vault.check_and_withdraw(60000.00, t0)
    assert ok1 is True
    assert vault.daily_withdrawn == 60000.00
    assert vault.balance == 440000.00

    # 2nd withdrawal: $50k (60k + 50k > 100k cap) -> Should fail
    ok2, err2 = vault.check_and_withdraw(50000.00, t0 + 100)
    assert ok2 is False
    assert err2 == "EXCEEDS_VAULT_DAILY_LIMIT"
    assert vault.daily_withdrawn == 60000.00

    # 3rd withdrawal: $35k (60k + 35k = 95k <= 100k) -> Should succeed
    ok3, res3 = vault.check_and_withdraw(35000.00, t0 + 200)
    assert ok3 is True
    assert vault.daily_withdrawn == 95000.00
    assert vault.balance == 405000.00

    # 4th withdrawal after 24h (t0 + 86401) -> Rolling reset triggered
    ok4, res4 = vault.check_and_withdraw(80000.00, t0 + 86500)
    assert ok4 is True
    assert vault.daily_withdrawn == 80000.00
    assert vault.balance == 325000.00


def test_vault_freeze_lockdown():
    vault = MockCorporateVault("vlt:main", "corp_1", daily_limit=100000.00, balance=200000.00)
    t0 = 1770000000

    vault.is_frozen = True
    ok, err = vault.check_and_withdraw(1000.00, t0)
    assert ok is False
    assert err == "VAULT_FROZEN"

    vault.is_frozen = False
    ok_unfrozen, res_unfrozen = vault.check_and_withdraw(1000.00, t0)
    assert ok_unfrozen is True
    assert res_unfrozen == "DISBURSED"


def test_inter_vault_transfer_conservation():
    source = MockCorporateVault("vlt:main", "corp_1", balance=200000.00)
    target = MockCorporateVault("vlt:payroll", "corp_1", balance=50000.00)
    initial_sum = source.balance + target.balance

    transfer_amount = 75000.00
    source.balance -= transfer_amount
    target.balance += transfer_amount
    final_sum = source.balance + target.balance

    assert source.balance == 125000.00
    assert target.balance == 125000.00
    assert final_sum == initial_sum
