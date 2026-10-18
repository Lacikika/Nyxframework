"""
Unit test suite for Nyxframework RPC Security:
Token Bucket Rate Limiting (50 req/s, capacity 50) and 64KB Payload Cap.
"""

import json
import pytest
import time
import math


class TokenBucket:
    """Python reference mirror of Lua Nyx.RPC Token Bucket Rate Limiter."""

    def __init__(self, capacity=50, refill_rate=50, default_cost=1.0, action_on_exceed="throttle",
                 max_violations=10, violation_window_ms=5000, kick_on_sustained=True):
        self.capacity = float(capacity)
        self.refill_rate = float(refill_rate)
        self.default_cost = float(default_cost)
        self.action_on_exceed = action_on_exceed
        self.max_violations = max_violations
        self.violation_window_ms = violation_window_ms
        self.kick_on_sustained = kick_on_sustained
        self.limiters = {}
        self.total_processed = 0
        self.total_blocked = 0
        self.total_kicks = 0

    def get_or_create(self, src, now_ms):
        if src not in self.limiters:
            self.limiters[src] = {
                "tokens": self.capacity,
                "last_refill": now_ms,
                "violations": 0,
                "last_violation": 0,
                "total_requests": 0,
                "blocked_requests": 0,
                "kicked": False,
            }
        return self.limiters[src]

    def check(self, src, now_ms, cost=None, route="test:route"):
        cost = self.default_cost if cost is None else float(cost)
        entry = self.get_or_create(src, now_ms)

        if entry["kicked"]:
            return False, 0.0, "KICKED"

        # Calculate token refill based on elapsed time
        delta_sec = max(0.0, (now_ms - entry["last_refill"]) / 1000.0)
        entry["tokens"] = min(self.capacity, entry["tokens"] + (delta_sec * self.refill_rate))
        entry["last_refill"] = now_ms

        entry["total_requests"] += 1
        self.total_processed += 1

        if entry["tokens"] < cost:
            # Rate limit exceeded
            entry["blocked_requests"] += 1
            self.total_blocked += 1

            # Violation tracking in rolling window
            if (now_ms - entry["last_violation"]) > self.violation_window_ms:
                entry["violations"] = 1
            else:
                entry["violations"] += 1
            entry["last_violation"] = now_ms

            if self.action_on_exceed == "kick" or (self.kick_on_sustained and entry["violations"] >= self.max_violations):
                entry["kicked"] = True
                self.total_kicks += 1
                return False, entry["tokens"], "KICKED"

            return False, entry["tokens"], "RATE_LIMITED"

        # Consume tokens
        entry["tokens"] -= cost
        return True, entry["tokens"], "OK"

    def reset(self, src):
        if src in self.limiters:
            del self.limiters[src]


def is_payload_within_bounds(payload, max_size=65536):
    """Python reference mirror of Lua Nyx.RPC.IsPayloadWithinBounds."""
    if payload is None:
        return True
    if isinstance(payload, str):
        raw_size = len(payload.encode("utf-8"))
    elif isinstance(payload, (int, float, bool)):
        raw_size = len(str(payload).encode("utf-8"))
    else:
        try:
            encoded = json.dumps(payload, separators=(",", ":"))
            raw_size = len(encoded.encode("utf-8"))
        except (TypeError, ValueError):
            return False
    return raw_size <= max_size


def is_valid_route(route):
    """Validate route naming conventions: alphanumeric with ':', '.', '_', '-' up to 128 chars."""
    if not isinstance(route, str):
        return False
    if len(route) == 0 or len(route) > 128:
        return False
    import re
    return bool(re.match(r"^[\w.:_-]+$", route))


def is_valid_nonce(nonce):
    """Validate nonce: non-empty string, length <= 64."""
    if not isinstance(nonce, str):
        return False
    if len(nonce) == 0 or len(nonce) > 64:
        return False
    return True


# ============================================================================
# PYTEST SUITE
# ============================================================================

def test_token_bucket_burst_and_depletion():
    """Verify bucket starts at capacity (50) and exactly 50 requests succeed in a burst."""
    bucket = TokenBucket(capacity=50, refill_rate=50)
    now = 1000.0

    # 50 requests in the same millisecond should all succeed
    for i in range(50):
        allowed, rem, status = bucket.check(src=1, now_ms=now)
        assert allowed is True, f"Request {i+1} should succeed"
        assert math.isclose(rem, 50 - (i + 1), abs_tol=1e-5)
        assert status == "OK"

    # 51st request in same millisecond must fail with RATE_LIMITED
    allowed, rem, status = bucket.check(src=1, now_ms=now)
    assert allowed is False
    assert status == "RATE_LIMITED"


def test_token_bucket_refill_over_time():
    """Verify tokens refill at 50 tokens/sec (0.05 tokens/ms)."""
    bucket = TokenBucket(capacity=50, refill_rate=50)
    now = 1000.0

    # Exhaust all 50 tokens
    for _ in range(50):
        bucket.check(src=1, now_ms=now)

    assert bucket.check(src=1, now_ms=now)[0] is False

    # Advance time by 200 ms -> should refill 200ms * 0.05 = 10 tokens
    now += 200.0
    for i in range(10):
        allowed, rem, status = bucket.check(src=1, now_ms=now)
        assert allowed is True, f"Refilled request {i+1} should succeed"

    # 11th request after 200ms should fail
    allowed, _, status = bucket.check(src=1, now_ms=now)
    assert allowed is False
    assert status == "RATE_LIMITED"

    # Advance time by 2000 ms (2 sec) -> should refill up to capacity clamp (50)
    now += 2000.0
    allowed, rem, status = bucket.check(src=1, now_ms=now)
    assert allowed is True
    assert math.isclose(rem, 49.0, abs_tol=1e-5)  # 50 cap - 1 consumed


def test_token_bucket_multi_source_isolation():
    """Verify that exhausting player 1 does not affect player 2."""
    bucket = TokenBucket(capacity=50, refill_rate=50)
    now = 1000.0

    # Exhaust player 1
    for _ in range(50):
        bucket.check(src=1, now_ms=now)

    assert bucket.check(src=1, now_ms=now)[0] is False

    # Player 2 should still have full 50 tokens
    for i in range(50):
        allowed, _, _ = bucket.check(src=2, now_ms=now)
        assert allowed is True, f"Player 2 request {i+1} should succeed independently"


def test_token_bucket_custom_cost():
    """Verify routes with higher token cost consume the correct amount."""
    bucket = TokenBucket(capacity=50, refill_rate=50)
    now = 1000.0

    # Heavy request costing 25 tokens
    allowed, rem, _ = bucket.check(src=1, now_ms=now, cost=25.0)
    assert allowed is True
    assert math.isclose(rem, 25.0, abs_tol=1e-5)

    # Another heavy request costing 25 tokens
    allowed, rem, _ = bucket.check(src=1, now_ms=now, cost=25.0)
    assert allowed is True
    assert math.isclose(rem, 0.0, abs_tol=1e-5)

    # 3rd request should fail
    allowed, _, status = bucket.check(src=1, now_ms=now, cost=1.0)
    assert allowed is False
    assert status == "RATE_LIMITED"


def test_token_bucket_sustained_flooding_kick():
    """Verify that sustained flooding exceeding max_violations results in kick."""
    bucket = TokenBucket(capacity=50, refill_rate=50, max_violations=5, kick_on_sustained=True)
    now = 1000.0

    # Exhaust bucket
    for _ in range(50):
        bucket.check(src=1, now_ms=now)

    # 4 violations
    for _ in range(4):
        allowed, _, status = bucket.check(src=1, now_ms=now)
        assert status == "RATE_LIMITED"

    # 5th violation triggers KICKED
    allowed, _, status = bucket.check(src=1, now_ms=now)
    assert allowed is False
    assert status == "KICKED"

    # Subsequent requests are dropped immediately
    allowed, _, status = bucket.check(src=1, now_ms=now + 500)
    assert allowed is False
    assert status == "KICKED"


def test_payload_bounds_exact_limits():
    """Verify payload size enforcement at exact 64KB (65536 bytes) boundary."""
    max_cap = 65536

    # 65535 bytes: PASS
    payload_65535 = "A" * 65535
    assert is_payload_within_bounds(payload_65535, max_cap) is True

    # 65536 bytes: PASS
    payload_65536 = "A" * 65536
    assert is_payload_within_bounds(payload_65536, max_cap) is True

    # 65537 bytes: FAIL
    payload_65537 = "A" * 65537
    assert is_payload_within_bounds(payload_65537, max_cap) is False

    # None / Nil: PASS
    assert is_payload_within_bounds(None, max_cap) is True

    # Small table: PASS
    assert is_payload_within_bounds({"action": "buy", "amount": 10}, max_cap) is True


def test_payload_bounds_complex_table():
    """Verify complex nested table serialization obeys 64KB cap."""
    max_cap = 65536

    # Table whose JSON representation is slightly under 64KB
    item_str = "x" * 100
    under_table = [{"id": i, "data": item_str} for i in range(500)]
    encoded_under = json.dumps(under_table, separators=(",", ":"))
    assert len(encoded_under.encode("utf-8")) < max_cap
    assert is_payload_within_bounds(under_table, max_cap) is True

    # Table whose JSON representation is over 64KB
    over_table = [{"id": i, "data": item_str} for i in range(700)]
    encoded_over = json.dumps(over_table, separators=(",", ":"))
    assert len(encoded_over.encode("utf-8")) > max_cap
    assert is_payload_within_bounds(over_table, max_cap) is False


def test_route_and_nonce_validation():
    """Verify security validation for routes and nonces."""
    assert is_valid_route("core:playerLoaded") is True
    assert is_valid_route("treasury:ledger.entry-1_test") is True
    assert is_valid_route("") is False
    assert is_valid_route("invalid route with spaces") is False
    assert is_valid_route("a" * 129) is False

    assert is_valid_nonce("550e8400-e29b-41d4-a716-446655440000") is True
    assert is_valid_nonce("") is False
    assert is_valid_nonce("n" * 65) is False
    assert is_valid_nonce(12345) is False
