"""
Unit tests for Fiscal Circuit Protection & Logarithmic Public Payroll Scaling
(nyx_treasury).
"""

import math
import pytest


class MockCircuitEngine:
    def __init__(self, config=None):
        self.config = config or {
            "TargetReserve": 5000000.00,
            "CautionReserve": 2500000.00,
            "RecoveryReserve": 1000000.00,
            "CriticalReserve": 500000.00,
            "RollingWindowSeconds": 600,
            "MaxRollingOutflow": 750000.00,
            "MaxSingleTransaction": 500000.00,
            "AusterityWageFloor": 0.10,
            "CriticalWageMultiplier": 0.00,
            "AutoResetCooldown": 300,
            "HysteresisRecoveryMargin": 0.75,
            "ExemptCategories": {
                "payroll": True,
                "emergency_subvention": True,
                "tax_sweep": True
            }
        }
        self.master_reserve = self.config["TargetReserve"]
        self.tripped = False
        self.tripped_at = 0
        self.trip_reason = None
        self.rolling_outflows = []
        self.circuit_logs = []
        self.payroll_runs = []

    def calculate_wage_multiplier(self, current_reserve=None):
        r = current_reserve if current_reserve is not None else self.master_reserve
        target = self.config["TargetReserve"]
        crit = self.config["CriticalReserve"]
        caution = self.config["CautionReserve"]
        floor = self.config["AusterityWageFloor"]
        crit_mult = self.config["CriticalWageMultiplier"]

        if self.tripped:
            if r <= crit:
                return crit_mult, "CIRCUIT_TRIPPED_FROZEN", r
            return floor, "CIRCUIT_TRIPPED_AUSTERITY", r

        if r >= target:
            return 1.00, "SOLVENT", r

        if r <= crit:
            return crit_mult, "CRITICAL_FREEZE", r

        log_ratio = math.log(r / crit)
        log_max = math.log(target / crit)
        norm = log_ratio / log_max if log_max > 0 else 0.00
        scaled = floor + ((1.00 - floor) * norm)
        clamped = max(floor, min(1.00, scaled))
        multiplier = math.floor(clamped * 100) / 100.0

        status = "AUSTERITY" if r < caution else "THROTTLED"
        return multiplier, status, r

    def determine_fiscal_state(self, current_reserve=None):
        r = current_reserve if current_reserve is not None else self.master_reserve
        if self.tripped:
            return "CIRCUIT_TRIPPED"
        if r <= self.config["CriticalReserve"]:
            return "CRITICAL_DEFICIT"
        if r < self.config["CautionReserve"]:
            return "AUSTERITY"
        if r < self.config["TargetReserve"]:
            return "THROTTLED"
        return "SOLVENT"

    def calculate_drain_velocity(self, now):
        window_sec = self.config["RollingWindowSeconds"]
        cutoff = now - window_sec
        active = [e for e in self.rolling_outflows if e["timestamp"] >= cutoff]
        self.rolling_outflows = active
        total_outflow = sum(e["amount"] for e in active)
        vel_sec = total_outflow / window_sec if window_sec > 0 else 0.0
        vel_hour = vel_sec * 3600.0
        return {
            "total_outflow": round(total_outflow, 2),
            "velocity_per_sec": round(vel_sec, 2),
            "velocity_per_hour": round(vel_hour, 2),
            "count": len(active)
        }

    def trip_circuit(self, reason, authorized_by="SYSTEM", now=1000):
        prev = self.determine_fiscal_state()
        self.tripped = True
        self.tripped_at = now
        self.trip_reason = reason
        self.circuit_logs.append({
            "event_type": "CIRCUIT_TRIPPED",
            "previous_state": prev,
            "new_state": "CIRCUIT_TRIPPED",
            "trigger_reason": reason,
            "authorized_by": authorized_by
        })

    def reset_circuit(self, authorized_by="SYSTEM", reason="MANUAL_RESET"):
        if not self.tripped:
            return False, "NOT_TRIPPED"
        prev = "CIRCUIT_TRIPPED"
        self.tripped = False
        self.tripped_at = 0
        self.trip_reason = None
        new_state = self.determine_fiscal_state()
        self.circuit_logs.append({
            "event_type": "CIRCUIT_RESET",
            "previous_state": prev,
            "new_state": new_state,
            "trigger_reason": reason,
            "authorized_by": authorized_by
        })
        return True, new_state

    def record_outflow(self, amount, category, authorized_by="SYSTEM", now=1000):
        self.rolling_outflows.append({
            "amount": amount,
            "timestamp": now,
            "category": category,
            "authorized_by": authorized_by
        })
        vel = self.calculate_drain_velocity(now)
        if not self.tripped and vel["total_outflow"] > self.config["MaxRollingOutflow"]:
            self.trip_circuit("BURST_DRAIN_VELOCITY_EXCEEDED", authorized_by, now)

    def can_auto_reset(self, now):
        if not self.tripped:
            return False, "NOT_TRIPPED"
        if self.master_reserve < self.config["RecoveryReserve"]:
            return False, "INSUFFICIENT_RESERVE_FOR_RESET"
        vel = self.calculate_drain_velocity(now)
        allowed = self.config["MaxRollingOutflow"] * self.config["HysteresisRecoveryMargin"]
        if vel["total_outflow"] > allowed:
            return False, "DRAIN_VELOCITY_STILL_ELEVATED"
        if (now - self.tripped_at) < self.config["AutoResetCooldown"]:
            return False, "COOLDOWN_ACTIVE"
        return True, "RECOVERY_CONDITIONS_MET"

    def calculate_subvention(self, dept_balance, required_payroll):
        deficit = max(0.0, required_payroll - dept_balance)
        if deficit <= 0.0:
            return 0.0, "DEPARTMENT_SOLVENT"
        surplus = max(0.0, self.master_reserve - self.config["CriticalReserve"])
        if surplus <= 0.0:
            return 0.0, "INSUFFICIENT_MASTER_SURPLUS"
        grant = min(deficit, surplus)
        return round(grant, 2), "FULL_SUBVENTION" if grant >= deficit else "PARTIAL_SUBVENTION"

    def execute_municipal_transfer(self, amount, category, authorized_by="SYSTEM", now=1000):
        if self.tripped:
            is_exempt = self.config["ExemptCategories"].get(category, False)
            if not is_exempt and authorized_by != "EXECUTIVE_OVERRIDE":
                return False, "FISCAL_CIRCUIT_BREAKER_ACTIVE"

        if (amount > self.config["MaxSingleTransaction"] and
                category != "emergency_subvention" and
                authorized_by != "EXECUTIVE_OVERRIDE"):
            self.trip_circuit("SINGLE_TRANSACTION_CAP_EXCEEDED", authorized_by, now)
            return False, "SINGLE_TRANSACTION_CAP_EXCEEDED"

        if self.master_reserve < amount:
            return False, "INSUFFICIENT_FUNDS"

        self.master_reserve -= amount
        self.record_outflow(amount, category, authorized_by, now)

        if self.master_reserve <= self.config["CriticalReserve"] and not self.tripped:
            self.trip_circuit("CRITICAL_RESERVE_DEPLETED", authorized_by, now)

        return True, "TRANSFERRED"


# ============================================================================
# PYTEST TEST SUITE
# ============================================================================

def test_logarithmic_wage_multiplier_scaling():
    engine = MockCircuitEngine()

    # 1. Full Solvency (100% payout)
    m, status, _ = engine.calculate_wage_multiplier(5000000.00)
    assert m == 1.00
    assert status == "SOLVENT"

    m_surplus, _, _ = engine.calculate_wage_multiplier(8000000.00)
    assert m_surplus == 1.00

    # 2. Critical Reserve Depletion (0% freeze)
    m_crit, status_crit, _ = engine.calculate_wage_multiplier(500000.00)
    assert m_crit == 0.00
    assert status_crit == "CRITICAL_FREEZE"

    m_subcrit, _, _ = engine.calculate_wage_multiplier(200000.00)
    assert m_subcrit == 0.00

    # 3. Intermediate Logarithmic Scaling
    # At 50% target ($2,500,000), wage multiplier scales smoothly (~72%)
    m_half, status_half, _ = engine.calculate_wage_multiplier(2500000.00)
    assert 0.70 <= m_half <= 0.75
    assert status_half == "THROTTLED"

    # At $1,000,000, wage multiplier is around 37% and in Austerity
    m_low, status_low, _ = engine.calculate_wage_multiplier(1000000.00)
    assert 0.35 <= m_low <= 0.40
    assert status_low == "AUSTERITY"

    # At $510,000, floor constraint applies (>= 10%)
    m_floor, status_floor, _ = engine.calculate_wage_multiplier(510000.00)
    assert m_floor >= 0.10
    assert status_floor == "AUSTERITY"


def test_fiscal_state_machine_transitions():
    engine = MockCircuitEngine()

    assert engine.determine_fiscal_state(5500000.00) == "SOLVENT"
    assert engine.determine_fiscal_state(3500000.00) == "THROTTLED"
    assert engine.determine_fiscal_state(1500000.00) == "AUSTERITY"
    assert engine.determine_fiscal_state(450000.00) == "CRITICAL_DEFICIT"

    engine.trip_circuit("MANUAL_TEST")
    assert engine.determine_fiscal_state(6000000.00) == "CIRCUIT_TRIPPED"


def test_rolling_drain_velocity_and_window_expiry():
    engine = MockCircuitEngine()
    now = 10000

    # Add 3 transactions in window, 1 outside window (700s ago > 600s window)
    engine.record_outflow(100000.00, "procurement", now=now - 50)
    engine.record_outflow(150000.00, "fleet", now=now - 200)
    engine.record_outflow(50000.00, "grants", now=now - 400)
    engine.record_outflow(200000.00, "old_expense", now=now - 700)

    vel = engine.calculate_drain_velocity(now)
    assert vel["count"] == 3
    assert vel["total_outflow"] == 300000.00
    assert vel["velocity_per_sec"] == 500.00
    assert vel["velocity_per_hour"] == 1800000.00


def test_circuit_breaker_trips_on_velocity_burst():
    engine = MockCircuitEngine()
    now = 5000

    # Record transactions pushing total within window to $800,000 (> $750k cap)
    engine.record_outflow(400000.00, "infrastructure", now=now - 100)
    assert not engine.tripped

    engine.record_outflow(400000.00, "bailout", now=now)
    assert engine.tripped
    assert engine.trip_reason == "BURST_DRAIN_VELOCITY_EXCEEDED"
    assert engine.determine_fiscal_state() == "CIRCUIT_TRIPPED"


def test_single_transaction_cap_enforcement():
    engine = MockCircuitEngine()
    now = 1000

    # Transfer of $600,000 exceeds max single transaction cap ($500,000)
    ok, err = engine.execute_municipal_transfer(600000.00, "discretionary", "DIRECTOR", now=now)
    assert not ok
    assert err == "SINGLE_TRANSACTION_CAP_EXCEEDED"
    assert engine.tripped
    assert engine.trip_reason == "SINGLE_TRANSACTION_CAP_EXCEEDED"

    # Executive override allows transaction through cap
    engine.tripped = False
    ok_ov, err_ov = engine.execute_municipal_transfer(600000.00, "discretionary", "EXECUTIVE_OVERRIDE", now=now)
    assert ok_ov
    assert err_ov == "TRANSFERRED"


def test_circuit_gating_and_exempt_categories():
    engine = MockCircuitEngine()
    now = 2000
    engine.trip_circuit("TEST_LOCKDOWN", now=now)

    # Discretionary transfer blocked
    ok1, err1 = engine.execute_municipal_transfer(50000.00, "grant", "SYSTEM", now=now)
    assert not ok1
    assert err1 == "FISCAL_CIRCUIT_BREAKER_ACTIVE"

    # Exempt transfers allowed
    ok_pay, _ = engine.execute_municipal_transfer(30000.00, "payroll", "SYSTEM", now=now)
    assert ok_pay

    ok_sub, _ = engine.execute_municipal_transfer(15000.00, "emergency_subvention", "SYSTEM", now=now)
    assert ok_sub

    ok_sweep, _ = engine.execute_municipal_transfer(10000.00, "tax_sweep", "SYSTEM", now=now)
    assert ok_sweep


def test_auto_reset_hysteresis_and_cooldown():
    engine = MockCircuitEngine()
    tripped_time = 5000
    engine.trip_circuit("BURST_DRAIN_VELOCITY_EXCEEDED", now=tripped_time)

    # 1. Under recovery reserve ($800k < $1M) -> rejected
    engine.master_reserve = 800000.00
    can1, r1 = engine.can_auto_reset(tripped_time + 400)
    assert not can1
    assert r1 == "INSUFFICIENT_RESERVE_FOR_RESET"

    # 2. Reserve recovered ($1.5M >= $1M), but outflow still elevated -> rejected
    engine.master_reserve = 1500000.00
    # Add $600k outflow (allowed threshold = $750k * 0.75 = $562.5k)
    engine.record_outflow(600000.00, "emergency", now=tripped_time + 200)
    can2, r2 = engine.can_auto_reset(tripped_time + 400)
    assert not can2
    assert r2 == "DRAIN_VELOCITY_STILL_ELEVATED"

    # 3. Outflow normalized, but cooldown (< 300s) active -> rejected
    engine.rolling_outflows = []  # clear outflows
    can3, r3 = engine.can_auto_reset(tripped_time + 150)
    assert not can3
    assert r3 == "COOLDOWN_ACTIVE"

    # 4. All conditions satisfied -> approved
    can4, r4 = engine.can_auto_reset(tripped_time + 350)
    assert can4
    assert r4 == "RECOVERY_CONDITIONS_MET"

    ok_reset, new_state = engine.reset_circuit("AUTO_RECOVERY", "Stabilized")
    assert ok_reset
    assert not engine.tripped
    assert new_state == "AUSTERITY"


def test_emergency_subvention_math_and_closed_loop_conservation():
    engine = MockCircuitEngine()
    engine.master_reserve = 2000000.00  # $2M master reserve ($1.5M surplus above $500k critical)
    crit_reserve = engine.config["CriticalReserve"]

    # 1. Department deficit of $15,000 -> full subvention
    grant1, status1 = engine.calculate_subvention(dept_balance=5000.00, required_payroll=20000.00)
    assert grant1 == 15000.00
    assert status1 == "FULL_SUBVENTION"

    # 2. Master reserve low ($508,000 -> only $8,000 surplus) -> partial subvention
    engine.master_reserve = 508000.00
    grant2, status2 = engine.calculate_subvention(dept_balance=5000.00, required_payroll=20000.00)
    assert grant2 == 8000.00
    assert status2 == "PARTIAL_SUBVENTION"

    # 3. Master reserve below critical ($450,000 -> 0 surplus) -> zero subvention
    engine.master_reserve = 450000.00
    grant3, status3 = engine.calculate_subvention(dept_balance=5000.00, required_payroll=20000.00)
    assert grant3 == 0.00
    assert status3 == "INSUFFICIENT_MASTER_SURPLUS"

    # 4. Department solvent (balance >= required) -> 0 subvention
    engine.master_reserve = 3000000.00
    grant4, status4 = engine.calculate_subvention(dept_balance=25000.00, required_payroll=20000.00)
    assert grant4 == 0.00
    assert status4 == "DEPARTMENT_SOLVENT"

    # 5. Closed-loop double-entry conservation
    master_start = 3000000.00
    dept_start = 2000.00
    worker_start = 100.00
    initial_total = master_start + dept_start + worker_start

    # Subvention grant of $10,000 from master to dept
    subvention_amount = 10000.00
    master_mid = master_start - subvention_amount
    dept_mid = dept_start + subvention_amount
    assert (master_start + dept_start) == (master_mid + dept_mid)

    # Payroll payout of $8,000 from dept to worker
    payroll_amount = 8000.00
    dept_final = dept_mid - payroll_amount
    worker_final = worker_start + payroll_amount
    assert (dept_mid + worker_start) == (dept_final + worker_final)

    final_total = master_mid + dept_final + worker_final
    assert initial_total == final_total
    assert dept_final == 4000.00
    assert worker_final == 8100.00
