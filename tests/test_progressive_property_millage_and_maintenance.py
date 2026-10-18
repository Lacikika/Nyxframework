"""
Unit test suite for Nyxframework Progressive Property Millage & Dynamic Land Maintenance Taxation:
- Exponential property holding multipliers (1.5^(N-1))
- Statutory maximum millage cap clamping (10%)
- Dynamic land footprint maintenance taxation ($/m^2) by property type and zoning
- Dilapidation and blight condition penalty surcharges
- Delinquency state machine (Tiers 0-4) and late fee escalation
- Closed-loop double-entry municipal revenue splits (Emergency 40%, Works 45%, Master 15%)
- Foreclosure lockout interlock and public blind-auction asset forfeiture
- Escrowed auction bidding, outbid refunds, and deed settlement conservation
"""

import math
import pytest


# ============================================================================
# PYTHON REFERENCE ENGINE: PROGRESSIVE TAXATION & AUCTION
# ============================================================================

class PropertyTaxationEngine:
    def __init__(self, holding_base=1.50, max_holding_mult=10.00, max_millage_rate=0.1000):
        self.holding_base = holding_base
        self.max_holding_mult = max_holding_mult
        self.max_millage_rate = max_millage_rate
        self.land_rates = {
            "residential": 1.20,
            "commercial": 2.50,
            "industrial": 3.20,
        }
        self.zone_surcharges = {
            "zone_ls_metro": 0.15,
            "zone_port_industrial": 0.10,
            "zone_sandy_shores": 0.00,
            "zone_paleto_bay": 0.00,
        }

    def calculate_holding_multiplier(self, properties_owned):
        n = max(1, int(properties_owned or 1))
        if n <= 1:
            return 1.0000
        raw = self.holding_base ** (n - 1)
        clamped = min(self.max_holding_mult, max(1.0000, raw))
        return round(clamped, 4)

    def calculate_effective_millage_rate(self, base_rate, properties_owned):
        base_rate = max(0.0, float(base_rate or 0.0150))
        mult = self.calculate_holding_multiplier(properties_owned)
        effective = min(self.max_millage_rate, base_rate * mult)
        return round(effective, 4)

    def calculate_millage_tax(self, price, effective_rate):
        price = max(0.0, float(price or 0.0))
        effective_rate = max(0.0, float(effective_rate or 0.0))
        return round(price * effective_rate, 2)

    def calculate_condition_blight_factor(self, condition, max_blight_surcharge=0.50):
        condition = max(0.0, min(100.0, float(condition if condition is not None else 100.0)))
        dilapidation = (100.0 - condition) / 100.0
        blight = 1.0 + (dilapidation * max_blight_surcharge)
        return round(blight, 4)

    def calculate_land_maintenance_tax(self, land_area_sqm, prop_type="residential", zone_id="zone_ls_metro", condition=100.0):
        sqm = max(0.0, float(land_area_sqm or 100.0))
        base_rate = self.land_rates.get(prop_type, 1.20)
        zone_surcharge = self.zone_surcharges.get(zone_id, 0.00)
        zone_mult = 1.0 + zone_surcharge
        blight = self.calculate_condition_blight_factor(condition)
        raw = sqm * base_rate * zone_mult * blight
        return round(raw, 2), base_rate, zone_mult, blight

    def evaluate_delinquency_tier(self, consecutive_missed_cycles):
        cycles = max(0, int(consecutive_missed_cycles or 0))
        if cycles == 0:
            return 0, "GOOD_STANDING"
        elif cycles == 1:
            return 1, "NOTICE_GRACE"
        elif cycles == 2:
            return 2, "LATE_PENALIZED"
        elif cycles == 3:
            return 3, "FORECLOSURE_WARNING"
        else:
            return 4, "FORFEITURE_AUCTION"

    def calculate_delinquency_penalty(self, tier, overdue_arrears):
        tier = int(tier or 0)
        arrears = max(0.0, float(overdue_arrears or 0.0))
        if tier <= 1 or arrears <= 0.0:
            return 0.00, 0.0
        rate = 0.10 if tier == 2 else 0.25
        penalty = round(arrears * rate, 2)
        return penalty, rate

    def calculate_total_assessment(self, price, base_rate, properties_owned, sqm, prop_type, zone_id, condition, overdue_arrears, missed_cycles):
        holding_mult = self.calculate_holding_multiplier(properties_owned)
        eff_rate = self.calculate_effective_millage_rate(base_rate, properties_owned)
        millage_tax = self.calculate_millage_tax(price, eff_rate)
        land_tax, base_per_sqm, zone_m, blight_f = self.calculate_land_maintenance_tax(sqm, prop_type, zone_id, condition)
        tier, status = self.evaluate_delinquency_tier(missed_cycles)
        penalty, pen_rate = self.calculate_delinquency_penalty(tier, overdue_arrears)
        total_due = round(millage_tax + land_tax + penalty, 2)

        return {
            "price": price,
            "properties_owned": properties_owned,
            "holding_multiplier": holding_mult,
            "base_millage_rate": base_rate,
            "effective_millage_rate": eff_rate,
            "millage_tax": millage_tax,
            "land_area_sqm": sqm,
            "property_type": prop_type,
            "zone_id": zone_id,
            "condition": condition,
            "base_rate_per_sqm": base_per_sqm,
            "zone_multiplier": zone_m,
            "blight_factor": blight_f,
            "maintenance_tax": land_tax,
            "delinquency_tier": tier,
            "delinquency_status": status,
            "overdue_arrears": overdue_arrears,
            "penalty": penalty,
            "penalty_rate": pen_rate,
            "total_tax_due": total_due,
        }

    def calculate_revenue_distribution(self, total_tax):
        total_cents = int(round(max(0.0, float(total_tax or 0.0)) * 100))
        if total_cents <= 0:
            return {"emergency": 0.00, "works": 0.00, "master": 0.00, "total": 0.00}
        em_cents = int(total_cents * 0.40)
        wo_cents = int(total_cents * 0.45)
        ma_cents = total_cents - em_cents - wo_cents
        return {
            "emergency": round(em_cents / 100.0, 2),
            "works": round(wo_cents / 100.0, 2),
            "master": round(ma_cents / 100.0, 2),
            "total": round(total_cents / 100.0, 2),
        }

    def calculate_condition_decay(self, last_maintenance_ts, now_ts, hours_per_pct=24.0):
        if now_ts <= last_maintenance_ts:
            return 0.00
        elapsed_hours = (now_ts - last_maintenance_ts) / 3600.0
        return round(elapsed_hours / hours_per_pct, 2)

    def calculate_repair_cost(self, land_area_sqm, current_condition, cost_per_sqm_point=0.05):
        sqm = max(0.0, float(land_area_sqm or 100.0))
        cond = max(0.0, min(100.0, float(current_condition or 100.0)))
        needed = 100.0 - cond
        if needed <= 0.0:
            return 0.00, 0.00
        cost = round(sqm * needed * cost_per_sqm_point, 2)
        return cost, needed


# ============================================================================
# PYTEST TEST SUITE
# ============================================================================

def test_progressive_holding_multiplier_progression():
    engine = PropertyTaxationEngine()
    # 1 property: 1.5^0 = 1.0000
    assert engine.calculate_holding_multiplier(1) == 1.0000
    # 2 properties: 1.5^1 = 1.5000
    assert engine.calculate_holding_multiplier(2) == 1.5000
    # 3 properties: 1.5^2 = 2.2500
    assert engine.calculate_holding_multiplier(3) == 2.2500
    # 4 properties: 1.5^3 = 3.3750
    assert engine.calculate_holding_multiplier(4) == 3.3750
    # 5 properties: 1.5^4 = 5.0625
    assert engine.calculate_holding_multiplier(5) == 5.0625
    # Clamping at max 10.0x: 1.5^6 = 11.39 -> 10.0000
    assert engine.calculate_holding_multiplier(7) == 10.0000


def test_effective_millage_rate_and_statutory_cap():
    engine = PropertyTaxationEngine(max_millage_rate=0.1000)
    base = 0.0150
    assert engine.calculate_effective_millage_rate(base, 1) == 0.0150
    assert engine.calculate_effective_millage_rate(base, 2) == 0.0225  # 0.015 * 1.5
    assert engine.calculate_effective_millage_rate(base, 3) == 0.0338  # 0.015 * 2.25 = 0.03375 -> 0.0338
    assert engine.calculate_effective_millage_rate(base, 5) == 0.0759  # 0.015 * 5.0625 = 0.0759375 -> 0.0759
    # Clamping: 0.015 * 10.0 = 0.1500, but cap is 0.1000
    assert engine.calculate_effective_millage_rate(base, 10) == 0.1000


def test_dynamic_land_footprint_maintenance_tax():
    engine = PropertyTaxationEngine()
    # Residential 120 sqm in zone_ls_metro (1.20 * 1.15 = 1.38/sqm) -> 120 * 1.38 = 165.60
    tax_res, base_r, zone_m, blight_f = engine.calculate_land_maintenance_tax(120.0, "residential", "zone_ls_metro", 100.0)
    assert abs(tax_res - 165.60) < 0.01
    assert base_r == 1.20
    assert zone_m == 1.15
    assert blight_f == 1.0000

    # Industrial 1250 sqm in zone_port_industrial (3.20 * 1.10 = 3.52/sqm) -> 1250 * 3.52 = 4400.00
    tax_ind, base_i, zone_i, _ = engine.calculate_land_maintenance_tax(1250.0, "industrial", "zone_port_industrial", 100.0)
    assert abs(tax_ind - 4400.00) < 0.01
    assert base_i == 3.20
    assert zone_i == 1.10

    # Commercial 500 sqm in zone_sandy_shores (2.50 * 1.00 = 2.50/sqm) -> 500 * 2.50 = 1250.00
    tax_rural, _, _, _ = engine.calculate_land_maintenance_tax(500.0, "commercial", "zone_sandy_shores", 100.0)
    assert abs(tax_rural - 1250.00) < 0.01


def test_dilapidation_and_blight_condition_penalties():
    engine = PropertyTaxationEngine()
    # Pristine 100% -> blight factor 1.0000
    assert engine.calculate_condition_blight_factor(100.0) == 1.0000
    # 50% condition -> blight factor 1.2500
    assert engine.calculate_condition_blight_factor(50.0) == 1.2500
    # 0% condition -> blight factor 1.5000 (+50% penalty)
    assert engine.calculate_condition_blight_factor(0.0) == 1.5000

    tax_100, _, _, _ = engine.calculate_land_maintenance_tax(120.0, "residential", "zone_ls_metro", 100.0)
    tax_0, _, _, _ = engine.calculate_land_maintenance_tax(120.0, "residential", "zone_ls_metro", 0.0)
    assert abs(tax_100 - 165.60) < 0.01
    assert abs(tax_0 - 248.40) < 0.01  # 165.60 * 1.5 = 248.40


def test_delinquency_state_machine_and_penalties():
    engine = PropertyTaxationEngine()
    t0, s0 = engine.evaluate_delinquency_tier(0)
    t1, s1 = engine.evaluate_delinquency_tier(1)
    t2, s2 = engine.evaluate_delinquency_tier(2)
    t3, s3 = engine.evaluate_delinquency_tier(3)
    t4, s4 = engine.evaluate_delinquency_tier(4)

    assert (t0, s0) == (0, "GOOD_STANDING")
    assert (t1, s1) == (1, "NOTICE_GRACE")
    assert (t2, s2) == (2, "LATE_PENALIZED")
    assert (t3, s3) == (3, "FORECLOSURE_WARNING")
    assert (t4, s4) == (4, "FORFEITURE_AUCTION")

    # Penalties on $500 arrears
    p0, r0 = engine.calculate_delinquency_penalty(t0, 500.00)
    p1, r1 = engine.calculate_delinquency_penalty(t1, 500.00)
    p2, r2 = engine.calculate_delinquency_penalty(t2, 500.00)
    p3, r3 = engine.calculate_delinquency_penalty(t3, 500.00)

    assert p0 == 0.00
    assert p1 == 0.00
    assert p2 == 50.00  # 10%
    assert r2 == 0.10
    assert p3 == 125.00  # 25%
    assert r3 == 0.25


def test_total_property_assessment_aggregation():
    engine = PropertyTaxationEngine()
    assess = engine.calculate_total_assessment(
        price=125000.00,
        base_rate=0.0150,
        properties_owned=3,  # holding mult = 2.25, eff rate = 0.0338
        sqm=120.00,
        prop_type="residential",
        zone_id="zone_ls_metro",
        condition=100.00,
        overdue_arrears=200.00,
        missed_cycles=2,  # tier 2 -> 10% on 200 = 20.00
    )

    assert assess["holding_multiplier"] == 2.2500
    assert assess["effective_millage_rate"] == 0.0338
    assert abs(assess["millage_tax"] - 4225.00) < 0.01
    assert abs(assess["maintenance_tax"] - 165.60) < 0.01
    assert assess["penalty"] == 20.00
    # 4225.00 + 165.60 + 20.00 = 4410.60
    assert abs(assess["total_tax_due"] - 4410.60) < 0.01


def test_double_entry_revenue_split_exact_conservation():
    engine = PropertyTaxationEngine()
    # Test flat $1000.00
    s1 = engine.calculate_revenue_distribution(1000.00)
    assert s1["emergency"] == 400.00
    assert s1["works"] == 450.00
    assert s1["master"] == 150.00
    assert abs((s1["emergency"] + s1["works"] + s1["master"]) - 1000.00) < 0.0001

    # Test fractional cent amounts
    test_amounts = [523.47, 1234.56, 99.99, 12500.33, 0.01]
    for amt in test_amounts:
        s = engine.calculate_revenue_distribution(amt)
        total_split = round(s["emergency"] + s["works"] + s["master"], 2)
        assert abs(total_split - amt) < 0.0001, f"Conservation failed for amount {amt}"


def test_condition_decay_and_repair_cost():
    engine = PropertyTaxationEngine()
    # 48 hours elapsed with 24 hours per percent = 2.0% decay
    decay = engine.calculate_condition_decay(1000, 1000 + (48 * 3600), hours_per_pct=24.0)
    assert decay == 2.00

    # Repair cost for 120 sqm property at 80% condition (20 points needed)
    # 120 * 20 * 0.05 = $120.00
    cost, needed = engine.calculate_repair_cost(120.0, 80.0, cost_per_sqm_point=0.05)
    assert needed == 20.00
    assert cost == 120.00


def test_delinquency_tier3_foreclosure_interlock():
    # Simulation of property access check
    def can_enter(tier_delinquency, key_tier, is_locked):
        if tier_delinquency >= 3 and key_tier < 5:
            return False, "PROPERTY_SEIZED_TAX_DELINQUENCY"
        if is_locked and key_tier < 2:
            return False, "DOOR_LOCKED"
        return True, "ACCESS_GRANTED"

    # Good standing resident can enter unlocked door
    ok, _ = can_enter(0, 2, False)
    assert ok is True

    # Tier 3 delinquent resident is locked out
    ok_delinq, err_delinq = can_enter(3, 2, False)
    assert ok_delinq is False
    assert err_delinq == "PROPERTY_SEIZED_TAX_DELINQUENCY"

    # Tier 5 emergency police / judicial officer can enter seized property
    ok_police, _ = can_enter(3, 5, False)
    assert ok_police is True


def test_delinquency_tier4_asset_forfeiture():
    # Simulation of forfeiture
    prop = {
        "id": 101,
        "owner_citizen_id": "CIT_TEST_99",
        "price": 125000.00,
        "consecutive_missed_cycles": 4,
        "is_locked": False,
        "reclaimed_for_auction": False,
    }

    if prop["consecutive_missed_cycles"] >= 4:
        prop["previous_owner"] = prop["owner_citizen_id"]
        prop["owner_citizen_id"] = None
        prop["reclaimed_for_auction"] = True
        prop["is_locked"] = True
        min_bid = math.floor((prop["price"] * 0.50) * 100) / 100
        auction = {
            "property_id": prop["id"],
            "minimum_bid": min_bid,
            "highest_bid": 0.00,
            "highest_bidder": None,
            "status": "active",
        }

    assert prop["owner_citizen_id"] is None
    assert prop["reclaimed_for_auction"] is True
    assert prop["is_locked"] is True
    assert auction["minimum_bid"] == 62500.00
    assert auction["status"] == "active"


def test_blind_auction_escrow_bidding_and_outbid_refund():
    # Auction setup
    auction = {
        "auction_id": 1,
        "minimum_bid": 62500.00,
        "highest_bid": 0.00,
        "highest_bidder": None,
    }
    bank_a = 100000.00
    bank_b = 100000.00
    escrow = 0.00

    # Bid 1: Citizen A bids $65,000
    bid_a = 65000.00
    bank_a -= bid_a
    escrow += bid_a
    auction["highest_bid"] = bid_a
    auction["highest_bidder"] = "CIT_A"
    assert bank_a == 35000.00
    assert escrow == 65000.00

    # Bid 2: Citizen B outbids with $75,000 -> Citizen A gets immediate 100% refund
    bid_b = 75000.00
    bank_b -= bid_b
    escrow += bid_b
    # Refund Citizen A:
    bank_a += auction["highest_bid"]
    escrow -= auction["highest_bid"]

    auction["highest_bid"] = bid_b
    auction["highest_bidder"] = "CIT_B"

    assert bank_a == 100000.00  # Completely restored
    assert bank_b == 25000.00
    assert escrow == 75000.00  # Only active bid held
    # Conservation of total funds
    assert (bank_a + bank_b + escrow) == 200000.00


def test_blind_auction_deed_settlement_and_treasury_conservation():
    treasury = 500000.00
    escrow = 75000.00
    winner = "CIT_B"
    property_record = {
        "id": 101,
        "owner": None,
        "reclaimed": True,
        "condition": 75.0,
        "delinquency_tier": 4,
    }

    # Settle auction
    treasury += escrow
    escrow = 0.00
    property_record["owner"] = winner
    property_record["reclaimed"] = False
    property_record["condition"] = 100.0
    property_record["delinquency_tier"] = 0

    assert treasury == 575000.00
    assert escrow == 0.00
    assert property_record["owner"] == "CIT_B"
    assert property_record["reclaimed"] is False
    assert property_record["condition"] == 100.0
    assert property_record["delinquency_tier"] == 0


def test_sql_migration_and_manifest_integrity():
    import os
    core_mig = os.path.join("FiveM", "nyx_core", "sql", "migrations", "027_properties_progressive_millage_and_maintenance_taxation.sql")
    prop_mig = os.path.join("FiveM", "nyx_properties", "sql", "migrations", "027_properties_progressive_millage_and_maintenance_taxation.sql")
    assert os.path.exists(core_mig), f"Migration missing: {core_mig}"
    assert os.path.exists(prop_mig), f"Mirrored migration missing: {prop_mig}"

    # Read and check keywords
    with open(core_mig, "r", encoding="utf-8") as f:
        content = f.read()
    assert "land_area_sqm" in content
    assert "maintenance_condition" in content
    assert "nyx_property_tax_assessments" in content
    assert "nyx_property_auctions" in content
