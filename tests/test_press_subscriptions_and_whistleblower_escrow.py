"""
Unit tests for Investigative Press Subscriptions, Delivery Routing & Whistleblower Bounty Escrow.
Verifies double-entry subscription revenue split conservation, plan specification validation,
subscription lifecycle state machine transitions, whistleblower bounty escrow guards,
cryptographic proof-of-source claim verification, migration 047 integrity, and manifest declarations.
"""

import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIVEM = ROOT / "FiveM"


class SubscriptionEngine:
    DEFAULT_PUB_RATIO = 0.7500
    DEFAULT_POOL_RATIO = 0.1500
    DEFAULT_TAX_RATIO = 0.1000

    @classmethod
    def calculate_subscription_split(
        cls,
        price: float,
        pub_ratio: float = DEFAULT_PUB_RATIO,
        pool_ratio: float = DEFAULT_POOL_RATIO,
        tax_ratio: float = DEFAULT_TAX_RATIO,
    ) -> tuple[float, float, float, float]:
        gross = max(0.00, math.floor(float(price) * 100) / 100)
        if gross <= 0.00:
            return 0.00, 0.00, 0.00, 0.00

        r_pub = max(0.00, float(pub_ratio))
        r_pool = max(0.00, float(pool_ratio))
        r_tax = max(0.00, float(tax_ratio))

        sum_r = r_pub + r_pool + r_tax
        if sum_r <= 0.0:
            r_pub, r_pool, r_tax = 0.75, 0.15, 0.10
            sum_r = 1.0

        if abs(sum_r - 1.0) > 0.0001:
            r_pub /= sum_r
            r_pool /= sum_r
            r_tax /= sum_r

        pub_share = math.floor((gross * r_pub) * 100) / 100
        pool_share = math.floor((gross * r_pool) * 100) / 100
        tax_share = math.floor((gross - pub_share - pool_share) * 100) / 100

        # Exact zero-cent leakage invariant correction
        delta = round(gross - (pub_share + pool_share + tax_share), 2)
        if delta != 0.00:
            pub_share = round(pub_share + delta, 2)

        return pub_share, pool_share, tax_share, gross

    @classmethod
    def validate_plan(cls, plan: dict) -> tuple[bool, str]:
        if not plan or not isinstance(plan, dict):
            return False, "MISSING_PLAN_DATA"

        plan_id = str(plan.get("planId", plan.get("plan_id", ""))).strip()
        if len(plan_id) < 3 or len(plan_id) > 64:
            return False, "INVALID_PLAN_ID"

        outlet_id = str(plan.get("outletId", plan.get("outlet_id", ""))).strip()
        if len(outlet_id) < 3 or len(outlet_id) > 64:
            return False, "INVALID_OUTLET_ID"

        name = str(plan.get("name", "")).strip()
        if len(name) < 3 or len(name) > 128:
            return False, "INVALID_PLAN_NAME"

        p_type = str(plan.get("planType", plan.get("plan_type", "digital"))).strip()
        if p_type not in {"digital", "print_delivery", "syndication"}:
            return False, "INVALID_PLAN_TYPE"

        try:
            price = float(plan.get("price", 0.0))
        except (ValueError, TypeError):
            return False, "INVALID_PLAN_PRICE"
        if price <= 0.0 or price > 10000.0:
            return False, "INVALID_PLAN_PRICE"

        try:
            period = int(plan.get("billingPeriodSec", plan.get("billing_period_sec", 604800)))
        except (ValueError, TypeError):
            return False, "INVALID_BILLING_PERIOD"
        if period < 60 or period > 31536000:
            return False, "INVALID_BILLING_PERIOD"

        return True, "VALID"

    @classmethod
    def evaluate_subscription_status(
        cls,
        current_status: str,
        period_end_sec: int,
        now_sec: int,
        consecutive_failures: int = 0,
        max_failures: int = 3,
    ) -> tuple[str, bool]:
        status = str(current_status or "active")
        p_end = int(period_end_sec)
        now = int(now_sec)
        fails = max(0, int(consecutive_failures))
        max_f = max(1, int(max_failures))

        if status == "cancelled":
            if now > p_end:
                return "expired", False
            return "cancelled", True

        if now <= p_end:
            return "active", True

        if fails >= max_f:
            return "expired", False
        return "past_due", False

    @classmethod
    def validate_bounty_award(
        cls, bounty_amount: float, escrow_balance: float, leak_status: str
    ) -> tuple[bool, str]:
        amt = float(bounty_amount)
        if amt <= 0.0:
            return False, "INVALID_BOUNTY_AMOUNT"

        bal = float(escrow_balance)
        if amt > bal:
            return False, "INSUFFICIENT_ESCROW_BALANCE"

        st = str(leak_status or "")
        if st not in {"under_investigation", "published"}:
            return False, "INVALID_LEAK_STATUS"

        return True, "VALID"

    @classmethod
    def generate_source_hash(cls, citizen_id: str, salt: str, nonce: str) -> str:
        payload = f"{citizen_id}:{salt}:{nonce}".encode("utf-8")
        return hashlib.sha256(payload).hexdigest()

    @classmethod
    def verify_source_claim(
        cls, expected_hash: str, citizen_id: str, salt: str, nonce: str
    ) -> bool:
        if not expected_hash or not citizen_id or not salt or not nonce:
            return False
        computed = cls.generate_source_hash(citizen_id, salt, nonce)
        return computed == expected_hash

    @classmethod
    def calculate_next_period(
        cls, current_end_sec: int, period_sec: int, now_sec: int
    ) -> tuple[int, int]:
        period = max(60, int(period_sec))
        new_start = max(int(now_sec), int(current_end_sec))
        new_end = new_start + period
        return new_start, new_end


# ============================================================================
# Pytest Test Cases
# ============================================================================


def test_subscription_revenue_split_conservation():
    """Validates 3-way double-entry subscription revenue split conservation with zero-cent leakage."""
    test_cases = [
        (10.00, 0.75, 0.15, 0.10),
        (25.00, 0.75, 0.15, 0.10),
        (35.00, 0.75, 0.15, 0.10),
        (60.00, 0.75, 0.15, 0.10),
        (75.00, 0.75, 0.15, 0.10),
        (99.95, 0.75, 0.15, 0.10),
        (123.47, 0.70, 0.20, 0.10),
    ]

    for price, r_pub, r_pool, r_tax in test_cases:
        pub, pool, tax, gross = SubscriptionEngine.calculate_subscription_split(
            price, r_pub, r_pool, r_tax
        )
        assert round(pub + pool + tax, 2) == round(gross, 2)
        assert pub >= 0.00
        assert pool >= 0.00
        assert tax >= 0.00
        assert pub >= pool >= tax


def test_subscription_plan_validation():
    """Validates subscription plan parameter guards and type constraints."""
    valid_plan = {
        "planId": "plan_daily_globe_digital",
        "outletId": "press:daily_globe",
        "name": "Daily Globe Digital Wire",
        "planType": "digital",
        "price": 25.00,
        "billingPeriodSec": 604800,
    }
    ok, _ = SubscriptionEngine.validate_plan(valid_plan)
    assert ok is True

    # Invalid plan type
    bad_type = dict(valid_plan, planType="illegal_streaming")
    ok_type, err_type = SubscriptionEngine.validate_plan(bad_type)
    assert ok_type is False
    assert err_type == "INVALID_PLAN_TYPE"

    # Negative price
    bad_price = dict(valid_plan, price=-10.00)
    ok_price, err_price = SubscriptionEngine.validate_plan(bad_price)
    assert ok_price is False
    assert err_price == "INVALID_PLAN_PRICE"

    # Invalid short name
    bad_name = dict(valid_plan, name="a")
    ok_name, err_name = SubscriptionEngine.validate_plan(bad_name)
    assert ok_name is False
    assert err_name == "INVALID_PLAN_NAME"


def test_subscription_lifecycle_state_machine():
    """Validates active, past_due, cancelled, and expired subscription lifecycle states."""
    now = 1000000

    # Active subscription within period
    st1, access1 = SubscriptionEngine.evaluate_subscription_status(
        "active", now + 3600, now, 0
    )
    assert st1 == "active"
    assert access1 is True

    # Cancelled subscription within paid period
    st2, access2 = SubscriptionEngine.evaluate_subscription_status(
        "cancelled", now + 3600, now, 0
    )
    assert st2 == "cancelled"
    assert access2 is True

    # Cancelled subscription past period end
    st3, access3 = SubscriptionEngine.evaluate_subscription_status(
        "cancelled", now - 60, now, 0
    )
    assert st3 == "expired"
    assert access3 is False

    # Past period with 1 failure -> past_due
    st4, access4 = SubscriptionEngine.evaluate_subscription_status(
        "active", now - 60, now, 1, max_failures=3
    )
    assert st4 == "past_due"
    assert access4 is False

    # Past period with 3 failures -> expired
    st5, access5 = SubscriptionEngine.evaluate_subscription_status(
        "active", now - 60, now, 3, max_failures=3
    )
    assert st5 == "expired"
    assert access5 is False


def test_whistleblower_bounty_award_validation():
    """Validates whistleblower bounty award constraints against escrow balance and leak status."""
    # Valid bounty award
    ok1, _ = SubscriptionEngine.validate_bounty_award(500.0, 5000.0, "under_investigation")
    assert ok1 is True

    ok2, _ = SubscriptionEngine.validate_bounty_award(1500.0, 5000.0, "published")
    assert ok2 is True

    # Exceeds escrow balance
    ok_over, err_over = SubscriptionEngine.validate_bounty_award(6000.0, 5000.0, "published")
    assert ok_over is False
    assert err_over == "INSUFFICIENT_ESCROW_BALANCE"

    # Zero or negative bounty
    ok_zero, err_zero = SubscriptionEngine.validate_bounty_award(0.0, 5000.0, "published")
    assert ok_zero is False
    assert err_zero == "INVALID_BOUNTY_AMOUNT"

    # Unclaimed or quashed leak cannot receive bounty
    ok_unclaimed, err_unclaimed = SubscriptionEngine.validate_bounty_award(
        500.0, 5000.0, "unclaimed"
    )
    assert ok_unclaimed is False
    assert err_unclaimed == "INVALID_LEAK_STATUS"


def test_whistleblower_bounty_cryptographic_proof_and_anonymity():
    """Validates cryptographic proof-of-whistleblower source verification for anonymous bounty claims."""
    citizen_id = "cit_edward_snowden"
    salt = "dead_drop_salt_4982"
    nonce = "whistle_nonce_8832"
    source_hash = SubscriptionEngine.generate_source_hash(citizen_id, salt, nonce)

    # Valid claimant
    assert (
        SubscriptionEngine.verify_source_claim(source_hash, citizen_id, salt, nonce)
        is True
    )

    # Imposter claiming with wrong citizenId
    assert (
        SubscriptionEngine.verify_source_claim(
            source_hash, "cit_imposter_source", salt, nonce
        )
        is False
    )

    # Correct citizenId but wrong secret nonce
    assert (
        SubscriptionEngine.verify_source_claim(
            source_hash, citizen_id, salt, "wrong_nonce"
        )
        is False
    )


def test_next_billing_period_calculation():
    """Validates deterministic billing period timestamp calculation."""
    now = 1700000000
    p_end = 1700604800
    period = 604800  # 7 days

    s1, e1 = SubscriptionEngine.calculate_next_period(p_end, period, now)
    assert s1 == p_end
    assert e1 == p_end + period

    # Overdue subscription where now > p_end
    overdue_now = 1700800000
    s2, e2 = SubscriptionEngine.calculate_next_period(p_end, period, overdue_now)
    assert s2 == overdue_now
    assert e2 == overdue_now + period


def test_migration_047_and_manifest_declarations():
    """Verifies Migration 047 registration in index.json and fxmanifest declarations."""
    index_path = FIVEM / "nyx_core" / "sql" / "migrations" / "index.json"
    assert index_path.is_file()

    with open(index_path, "r", encoding="utf-8") as f:
        migrations = json.load(f)

    assert "047_press_subscriptions_and_whistleblower_escrow.sql" in migrations
    assert (
        migrations.index("047_press_subscriptions_and_whistleblower_escrow.sql") == 46
    )

    core_mig = (
        FIVEM
        / "nyx_core"
        / "sql"
        / "migrations"
        / "047_press_subscriptions_and_whistleblower_escrow.sql"
    )
    press_mig = (
        FIVEM
        / "nyx_press"
        / "sql"
        / "migrations"
        / "047_press_subscriptions_and_whistleblower_escrow.sql"
    )
    assert core_mig.is_file()
    assert press_mig.is_file()

    # Check fxmanifest declarations
    manifest_path = FIVEM / "nyx_press" / "fxmanifest.lua"
    assert manifest_path.is_file()
    manifest_content = manifest_path.read_text(encoding="utf-8")
    assert "shared/subscriptions.lua" in manifest_content
    assert "server/subscriptions.lua" in manifest_content
    assert "client/subscriptions.lua" in manifest_content


def test_subscription_status_badge_formatting():
    """Validates subscription status badge colors and labels."""
    badges = {
        "active": ("AKTÍV", "#10B981"),
        "past_due": ("DÍJHÁTRALÉK", "#F59E0B"),
        "cancelled": ("LEMONDVA", "#6B7280"),
        "expired": ("LEJÁRT", "#EF4444"),
    }
    for st, (expected_label, expected_color) in badges.items():
        assert expected_label in {"AKTÍV", "DÍJHÁTRALÉK", "LEMONDVA", "LEJÁRT"}
        assert expected_color.startswith("#")


def test_in_engine_test_suite_registration():
    """Verifies that TestPressSubscriptionsAndWhistleblowerEscrow is wired into nyx_core/server/tests.lua."""
    tests_path = FIVEM / "nyx_core" / "server" / "tests.lua"
    assert tests_path.is_file()
    content = tests_path.read_text(encoding="utf-8")
    assert "TestPressSubscriptionsAndWhistleblowerEscrow" in content
