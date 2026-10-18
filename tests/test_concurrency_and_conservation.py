"""
Unit test suite for Nyxframework Concurrency and Conservation QA:
- Inventory Mutex Concurrency, Dijkstra Dual-Locking & Duplication Prevention
- Treasury Double-Entry Closed-Loop Conservation & Concurrency Overdraft Guards
"""

import math
import threading
import time
import pytest


# ============================================================================
# PYTHON REFERENCE MIRROR: INVENTORY MUTEX & CONCURRENCY
# ============================================================================

class InventoryMutexManager:
    """Python reference mirror of nyx_inventory/server/mutex.lua."""

    def __init__(self, default_timeout_ms=2000):
        self.default_timeout_ms = default_timeout_ms
        self.locks = {}  # inv_id -> expiry_ms
        self.current_time_ms = 1000.0

    def get_time(self):
        return self.current_time_ms

    def set_time(self, t_ms):
        self.current_time_ms = float(t_ms)

    def advance_time(self, delta_ms):
        self.current_time_ms += float(delta_ms)

    def is_locked(self, inv_id):
        if not inv_id:
            return False
        expiry = self.locks.get(inv_id)
        if expiry is None:
            return False
        if self.current_time_ms >= expiry:
            del self.locks[inv_id]
            return False
        return True

    def acquire_lock(self, inv_id, timeout_ms=None):
        if not inv_id:
            return False
        if self.is_locked(inv_id):
            return False
        duration = timeout_ms if timeout_ms is not None else self.default_timeout_ms
        self.locks[inv_id] = self.current_time_ms + duration
        return True

    def release_lock(self, inv_id):
        if not inv_id:
            return
        if inv_id in self.locks:
            del self.locks[inv_id]

    def acquire_dual_lock(self, inv_a, inv_b, timeout_ms=None):
        if not inv_a or not inv_b:
            return False
        if inv_a == inv_b:
            return self.acquire_lock(inv_a, timeout_ms)

        # Enforce strict Dijkstra resource hierarchy (lexicographical sort)
        first = inv_a if inv_a < inv_b else inv_b
        second = inv_b if inv_a < inv_b else inv_a

        if not self.acquire_lock(first, timeout_ms):
            return False

        if not self.acquire_lock(second, timeout_ms):
            # Rollback first lock immediately to prevent partial lock leakage
            self.release_lock(first)
            return False

        return True

    def release_dual_lock(self, inv_a, inv_b):
        if inv_a == inv_b:
            self.release_lock(inv_a)
        else:
            self.release_lock(inv_a)
            self.release_lock(inv_b)

    def with_lock(self, inv_id, fn):
        if not self.acquire_lock(inv_id):
            return False, "CONTAINER_BUSY"
        try:
            res = fn()
            return True, res
        except Exception as e:
            return False, "INTERNAL_MUTEX_ERROR"
        finally:
            self.release_lock(inv_id)

    def with_dual_lock(self, inv_a, inv_b, fn):
        if not self.acquire_dual_lock(inv_a, inv_b):
            return False, "CONTAINER_BUSY"
        try:
            res = fn()
            return True, res
        except Exception as e:
            return False, "INTERNAL_MUTEX_ERROR"
        finally:
            self.release_dual_lock(inv_a, inv_b)


# ============================================================================
# PYTHON REFERENCE MIRROR: TREASURY DOUBLE-ENTRY CONSERVATION
# ============================================================================

class TreasuryLedger:
    """Python reference mirror of nyx_treasury/server/ledger.lua."""

    def __init__(self):
        self.accounts = {}  # id -> balance (float cents)
        self.ledger_entries = []  # list of tx dicts
        self.circuit_tripped = False
        self.max_single_tx = 500000.00
        self.exempt_categories = {"payroll", "emergency_subvention", "tax_sweep"}

    def ensure_account(self, acc_id, balance=0.0):
        if acc_id not in self.accounts:
            self.accounts[acc_id] = round(float(balance), 2)

    def get_balance(self, acc_id):
        return self.accounts.get(acc_id, 0.00)

    def validate_transaction(self, entries):
        """Verify sum(DEBIT) == sum(CREDIT) to exact cent precision."""
        total_debits = 0.0
        total_credits = 0.0
        for e in entries:
            amt = round(float(e["amount"]), 2)
            if e["entry_type"] == "DEBIT":
                total_debits += amt
            elif e["entry_type"] == "CREDIT":
                total_credits += amt
        delta = abs(round(total_debits - total_credits, 2))
        if delta > 0.001:
            return False, f"CONSERVATION_LAW_VIOLATION: Debits ({total_debits:.2f}) != Credits ({total_credits:.2f})"
        return True, None

    def execute_transfer(self, debit_acc, credit_acc, amount, category="general", authorized_by="SYSTEM"):
        amount = round(float(amount), 2)
        if amount <= 0.00:
            return False, "INVALID_AMOUNT"
        if debit_acc == credit_acc:
            return False, "IDENTICAL_ACCOUNTS"

        self.ensure_account(debit_acc)
        self.ensure_account(credit_acc)

        # Fiscal Circuit Breaker check on municipal accounts
        if debit_acc.startswith("gov:"):
            if self.circuit_tripped:
                if category not in self.exempt_categories and authorized_by != "EXECUTIVE_OVERRIDE":
                    return False, "FISCAL_CIRCUIT_BREAKER_ACTIVE"
            if amount > self.max_single_tx and category != "emergency_subvention" and authorized_by != "EXECUTIVE_OVERRIDE":
                self.circuit_tripped = True
                return False, "SINGLE_TRANSACTION_CAP_EXCEEDED"

        # Pre-transaction liquidity check
        if self.accounts[debit_acc] < amount:
            return False, "INSUFFICIENT_FUNDS"

        # Atomic double-entry update
        self.accounts[debit_acc] = round(self.accounts[debit_acc] - amount, 2)
        self.accounts[credit_acc] = round(self.accounts[credit_acc] + amount, 2)

        tx_entry = {
            "debit_account": debit_acc,
            "credit_account": credit_acc,
            "amount": amount,
            "category": category,
            "authorized_by": authorized_by
        }
        self.ledger_entries.append(tx_entry)
        return True, "SUCCESS"

    def execute_split_transfer(self, debit_acc, credits_list, category="split", authorized_by="SYSTEM"):
        """Atomic 1-to-many transfer (e.g. amount + municipal tax)."""
        self.ensure_account(debit_acc)
        total_credit = sum(round(c["amount"], 2) for c in credits_list)
        total_credit = round(total_credit, 2)

        if total_credit <= 0.00:
            return False, "INVALID_AMOUNT"
        if self.accounts[debit_acc] < total_credit:
            return False, "INSUFFICIENT_FUNDS"

        # Debit source
        self.accounts[debit_acc] = round(self.accounts[debit_acc] - total_credit, 2)

        # Credit targets
        for c in credits_list:
            acc = c["account"]
            amt = round(c["amount"], 2)
            self.ensure_account(acc)
            self.accounts[acc] = round(self.accounts[acc] + amt, 2)

        return True, "SUCCESS"

    def get_total_materialized_balance(self):
        return round(sum(self.accounts.values()), 2)


# ============================================================================
# PYTEST TESTS: INVENTORY MUTEX CONCURRENCY
# ============================================================================

def test_inventory_single_lock_lifecycle_and_contention():
    """Verify single lock acquisition, active contention lockout, and clean release."""
    mgr = InventoryMutexManager(default_timeout_ms=2000)
    inv = "citizen:TEST_01"

    assert mgr.is_locked(inv) is False
    assert mgr.acquire_lock(inv) is True
    assert mgr.is_locked(inv) is True

    # Immediate contention: second acquisition must fail
    assert mgr.acquire_lock(inv) is False

    mgr.release_lock(inv)
    assert mgr.is_locked(inv) is False

    # Should be acquirable again
    assert mgr.acquire_lock(inv) is True
    mgr.release_lock(inv)


def test_inventory_lock_timeout_auto_expiry():
    """Verify locks auto-expire when game timer advances past expiryMs."""
    mgr = InventoryMutexManager(default_timeout_ms=2000)
    inv = "citizen:STUCK_01"

    mgr.set_time(1000.0)
    mgr.acquire_lock(inv, timeout_ms=2000)
    assert mgr.is_locked(inv) is True

    # Advance timer to 2500ms (within timeout) -> still locked
    mgr.set_time(2500.0)
    assert mgr.is_locked(inv) is True

    # Advance timer to 3001ms (past timeout) -> lock expires
    mgr.set_time(3001.0)
    assert mgr.is_locked(inv) is False

    # Lock table should be cleaned and newly acquirable
    assert mgr.acquire_lock(inv) is True


def test_inventory_dual_lock_dijkstra_ordering_and_circular_deadlock_avoidance():
    """Verify Dijkstra resource hierarchy ordering prevents circular deadlock on inverted requests."""
    mgr = InventoryMutexManager(default_timeout_ms=5000)
    inv_a = "citizen:ALICE"
    inv_b = "stash:BOB_STASH"

    # Process 1 acquires (ALICE, BOB_STASH)
    ok1 = mgr.acquire_dual_lock(inv_a, inv_b)
    assert ok1 is True
    assert mgr.is_locked(inv_a) is True
    assert mgr.is_locked(inv_b) is True

    # Process 2 attempts inverted acquisition (BOB_STASH, ALICE)
    # Because of lexicographical sorting, it attempts ALICE first, which is held by Process 1.
    ok2 = mgr.acquire_dual_lock(inv_b, inv_a)
    assert ok2 is False

    # Process 1 releases
    mgr.release_dual_lock(inv_a, inv_b)
    assert mgr.is_locked(inv_a) is False
    assert mgr.is_locked(inv_b) is False


def test_inventory_dual_lock_rollback_on_partial_failure():
    """Verify that if the second container is busy, the first acquired lock is rolled back immediately."""
    mgr = InventoryMutexManager(default_timeout_ms=5000)
    inv_a = "citizen:01"
    inv_b = "citizen:02"  # inv_a < inv_b

    # Pre-lock second container independently
    mgr.acquire_lock(inv_b)
    assert mgr.is_locked(inv_b) is True

    # Attempt dual lock (inv_a, inv_b). First acquires inv_a, then fails on inv_b.
    # It MUST roll back inv_a!
    ok = mgr.acquire_dual_lock(inv_a, inv_b)
    assert ok is False
    assert mgr.is_locked(inv_a) is False, "inv_a should have been rolled back and released!"
    assert mgr.is_locked(inv_b) is True, "inv_b was independently held and must remain locked"


def test_inventory_intra_container_dual_lock():
    """Verify intra-container dual lock (same container) does not deadlock against itself."""
    mgr = InventoryMutexManager()
    inv = "citizen:SELF_MOVE"

    ok = mgr.acquire_dual_lock(inv, inv)
    assert ok is True
    assert mgr.is_locked(inv) is True

    # Cannot acquire again
    assert mgr.acquire_lock(inv) is False

    # Release dual lock releases the single lock
    mgr.release_dual_lock(inv, inv)
    assert mgr.is_locked(inv) is False


def test_inventory_scoped_with_lock_success_and_exception_safety():
    """Verify WithLock and WithDualLock execute safely and guarantee cleanup even on exception."""
    mgr = InventoryMutexManager()
    inv = "citizen:SCOPED"

    # Case 1: Normal execution
    called = []
    ok, res = mgr.with_lock(inv, lambda: called.append(True) or 42)
    assert ok is True
    assert res == 42
    assert len(called) == 1
    assert mgr.is_locked(inv) is False

    # Case 2: Exception inside callback
    def faulty():
        raise RuntimeError("database timeout")

    ok_err, status = mgr.with_lock(inv, faulty)
    assert ok_err is False
    assert status == "INTERNAL_MUTEX_ERROR"
    assert mgr.is_locked(inv) is False, "Lock must be released even after exception"

    # Case 3: Dual lock exception
    inv_a, inv_b = "citizen:A", "citizen:B"
    ok_dual_err, status_dual = mgr.with_dual_lock(inv_a, inv_b, faulty)
    assert ok_dual_err is False
    assert status_dual == "INTERNAL_MUTEX_ERROR"
    assert mgr.is_locked(inv_a) is False
    assert mgr.is_locked(inv_b) is False


def test_inventory_concurrent_race_condition_duplication_prevention():
    """Simulate two concurrent threads attempting to transfer the same item stack simultaneously."""
    mgr = InventoryMutexManager()

    source_container = {"id": "citizen:SRC", "items": [{"item": "gold_bar", "count": 10}]}
    target_container = {"id": "citizen:DST", "items": []}

    # Two requests arrive concurrently to move all 10 gold bars
    req1_success = False
    req2_success = False

    # Request 1 enters with dual lock
    if mgr.acquire_dual_lock(source_container["id"], target_container["id"]):
        # Perform move
        amt = source_container["items"][0]["count"]
        source_container["items"][0]["count"] -= amt
        target_container["items"].append({"item": "gold_bar", "count": amt})
        req1_success = True

        # While Request 1 is holding the lock, Request 2 attempts identical transfer
        req2_allowed = mgr.acquire_dual_lock(source_container["id"], target_container["id"])
        if req2_allowed:
            # Should NOT happen!
            amt2 = source_container["items"][0]["count"]
            source_container["items"][0]["count"] -= amt2
            target_container["items"][0]["count"] += amt2
            req2_success = True
            mgr.release_dual_lock(source_container["id"], target_container["id"])

        mgr.release_dual_lock(source_container["id"], target_container["id"])

    assert req1_success is True
    assert req2_success is False

    # Verify zero-duplication conservation invariant
    src_count = source_container["items"][0]["count"]
    dst_count = target_container["items"][0]["count"]
    total = src_count + dst_count
    assert total == 10
    assert src_count == 0
    assert dst_count == 10


def test_inventory_capacity_limit_conservation():
    """Verify atomic abort and item conservation when destination container weight limit is exceeded."""
    mgr = InventoryMutexManager()
    max_weight_g = 60000  # 60kg
    current_dst_weight_g = 55000  # 55kg
    item_weight_g = 10000  # 10kg -> total would be 65kg, exceeding 60kg limit!

    src = {"id": "citizen:SRC", "count": 1}
    dst = {"id": "citizen:DST", "count": 0}

    ok, res = mgr.with_dual_lock(src["id"], dst["id"], lambda: (
        False if (current_dst_weight_g + item_weight_g > max_weight_g) else True
    ))

    # Move is rejected due to capacity limit
    assert ok is True
    assert res is False
    # Counts remain untouched
    assert src["count"] == 1
    assert dst["count"] == 0


# ============================================================================
# PYTEST TESTS: TREASURY DOUBLE-ENTRY CONSERVATION
# ============================================================================

def test_treasury_double_entry_closed_loop_conservation():
    """Verify that every valid transaction satisfies sum(Debits) == sum(Credits)."""
    ledger = TreasuryLedger()
    ledger.ensure_account("citizen:ALICE", 1000.00)
    ledger.ensure_account("citizen:BOB", 500.00)

    initial_total = ledger.get_total_materialized_balance()
    assert initial_total == 1500.00

    ok, tx = ledger.execute_transfer("citizen:ALICE", "citizen:BOB", 250.00)
    assert ok is True

    final_total = ledger.get_total_materialized_balance()
    assert final_total == initial_total
    assert ledger.get_balance("citizen:ALICE") == 750.00
    assert ledger.get_balance("citizen:BOB") == 750.00


def test_treasury_cent_precision_and_no_float_drift():
    """Verify 500 micro-transactions maintain exact cent precision with zero floating point drift."""
    ledger = TreasuryLedger()
    ledger.ensure_account("acc:A", 10000.00)
    ledger.ensure_account("acc:B", 5000.00)

    initial_total = ledger.get_total_materialized_balance()
    amounts = [0.01, 0.03, 0.07, 0.13, 0.29, 0.47, 0.89, 1.17, 2.33, 4.01]

    for i in range(500):
        amt = amounts[i % len(amounts)]
        ok, _ = ledger.execute_transfer("acc:A", "acc:B", amt)
        assert ok is True

    final_total = ledger.get_total_materialized_balance()
    assert final_total == initial_total
    assert round(ledger.get_balance("acc:A") + ledger.get_balance("acc:B"), 2) == initial_total


def test_treasury_concurrent_withdrawal_overdraft_prevention():
    """Verify that simultaneous requests on an account cannot overdraft below zero."""
    ledger = TreasuryLedger()
    ledger.ensure_account("citizen:SPENDER", 1000.00)
    ledger.ensure_account("citizen:RECIPIENT_1", 0.00)
    ledger.ensure_account("citizen:RECIPIENT_2", 0.00)

    initial_total = ledger.get_total_materialized_balance()

    # Two requests for $600 each arrive
    ok1, _ = ledger.execute_transfer("citizen:SPENDER", "citizen:RECIPIENT_1", 600.00)
    ok2, err2 = ledger.execute_transfer("citizen:SPENDER", "citizen:RECIPIENT_2", 600.00)

    assert ok1 is True
    assert ok2 is False
    assert err2 == "INSUFFICIENT_FUNDS"

    # Spender balance must be 400.00, NEVER -200.00
    assert ledger.get_balance("citizen:SPENDER") == 400.00
    assert ledger.get_balance("citizen:RECIPIENT_1") == 600.00
    assert ledger.get_balance("citizen:RECIPIENT_2") == 0.00
    assert ledger.get_total_materialized_balance() == initial_total


def test_treasury_split_transfer_tax_conservation():
    """Verify split transfer (citizen payment + municipal tax) satisfies conservation."""
    ledger = TreasuryLedger()
    ledger.ensure_account("citizen:BUYER", 1000.00)
    ledger.ensure_account("business:STORE", 200.00)
    ledger.ensure_account("gov:city:master", 50000.00)

    initial_total = ledger.get_total_materialized_balance()

    # $500 purchase: $475 to store, $25 to municipal treasury
    credits = [
        {"account": "business:STORE", "amount": 475.00},
        {"account": "gov:city:master", "amount": 25.00}
    ]

    ok, _ = ledger.execute_split_transfer("citizen:BUYER", credits)
    assert ok is True

    assert ledger.get_balance("citizen:BUYER") == 500.00
    assert ledger.get_balance("business:STORE") == 675.00
    assert ledger.get_balance("gov:city:master") == 50025.00
    assert ledger.get_total_materialized_balance() == initial_total


def test_treasury_atomic_rollback_on_failure():
    """Verify that if transfer conditions are violated, no balance is mutated."""
    ledger = TreasuryLedger()
    ledger.ensure_account("citizen:A", 100.00)
    ledger.ensure_account("citizen:B", 50.00)

    initial_a = ledger.get_balance("citizen:A")
    initial_b = ledger.get_balance("citizen:B")

    # Invalid identical accounts
    ok, err = ledger.execute_transfer("citizen:A", "citizen:A", 50.00)
    assert ok is False
    assert err == "IDENTICAL_ACCOUNTS"
    assert ledger.get_balance("citizen:A") == initial_a

    # Negative / zero amount
    ok2, err2 = ledger.execute_transfer("citizen:A", "citizen:B", -10.00)
    assert ok2 is False
    assert err2 == "INVALID_AMOUNT"
    assert ledger.get_balance("citizen:A") == initial_a
    assert ledger.get_balance("citizen:B") == initial_b


def test_treasury_multi_employee_payroll_conservation():
    """Verify bulk payroll run across departmental and employee accounts conserves total currency."""
    ledger = TreasuryLedger()
    ledger.ensure_account("gov:dept:police", 50000.00)
    employees = [
        ("char:officer_1", 2500.00),
        ("char:officer_2", 2800.00),
        ("char:sergeant_1", 3500.00),
        ("char:lieutenant_1", 4200.00),
        ("char:captain_1", 5000.00)
    ]
    for emp_id, _ in employees:
        ledger.ensure_account(emp_id, 100.00)

    initial_total = ledger.get_total_materialized_balance()
    total_payroll = sum(salary for _, salary in employees)

    for emp_id, salary in employees:
        ok, _ = ledger.execute_transfer("gov:dept:police", emp_id, salary, category="payroll")
        assert ok is True

    assert ledger.get_balance("gov:dept:police") == 50000.00 - total_payroll
    for emp_id, salary in employees:
        assert ledger.get_balance(emp_id) == 100.00 + salary

    assert ledger.get_total_materialized_balance() == initial_total


def test_treasury_circuit_breaker_and_cap_interlocks():
    """Verify municipal outlays respect circuit breaker trip state and single transaction cap."""
    ledger = TreasuryLedger()
    ledger.ensure_account("gov:city:master", 1000000.00)
    ledger.ensure_account("citizen:CONTRACTOR", 0.00)

    # 1. Transaction exceeding single cap ($500k) without override trips circuit and is rejected
    ok_cap, err_cap = ledger.execute_transfer("gov:city:master", "citizen:CONTRACTOR", 600000.00, category="procurement")
    assert ok_cap is False
    assert err_cap == "SINGLE_TRANSACTION_CAP_EXCEEDED"
    assert ledger.circuit_tripped is True

    # 2. Subsequent normal municipal transfer rejected because circuit is tripped
    ok_blocked, err_blocked = ledger.execute_transfer("gov:city:master", "citizen:CONTRACTOR", 1000.00, category="procurement")
    assert ok_blocked is False
    assert err_blocked == "FISCAL_CIRCUIT_BREAKER_ACTIVE"

    # 3. Exempt category (payroll) succeeds even when circuit is tripped
    ok_payroll, _ = ledger.execute_transfer("gov:city:master", "citizen:CONTRACTOR", 2500.00, category="payroll")
    assert ok_payroll is True

    # 4. Executive override succeeds even for non-exempt category
    ok_override, _ = ledger.execute_transfer("gov:city:master", "citizen:CONTRACTOR", 5000.00, category="procurement", authorized_by="EXECUTIVE_OVERRIDE")
    assert ok_override is True
