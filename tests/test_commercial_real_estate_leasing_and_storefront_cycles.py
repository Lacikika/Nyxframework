#!/usr/bin/env python3
"""
Unit and Integration Tests for Commercial Real Estate Leasing & Public Storefront Cycles
(nyx_properties & nyx_factions).
Validates SQL migration 058, manifest declarations, commercial zoning taxonomy,
zero-cent economic conservation, 4-tier delinquency state machine, doorlock/register interlocks,
arrears penalty calculation, and in-engine Test 53 integration.
"""

import os
import json
import math
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")


class CommercialLeaseEngine:
    ZoningTypes = {
        "retail_storefront": {
            "label": "Kereskedelmi Kiskereskedelmi Üzlethelyiség",
            "allowedRegisterCount": 4,
            "rateMultiplier": 1.00
        },
        "corporate_office": {
            "label": "Vállalati Iroda & Adminisztrációs Központ",
            "allowedRegisterCount": 1,
            "rateMultiplier": 1.15
        },
        "industrial_warehouse": {
            "label": "Ipari Raktárbázis & Logisztikai Csarnok",
            "allowedRegisterCount": 2,
            "rateMultiplier": 0.90
        },
        "hospitality_venue": {
            "label": "Vendéglátóipari & Szórakoztató Létesítmény",
            "allowedRegisterCount": 3,
            "rateMultiplier": 1.25
        },
        "medical_clinic": {
            "label": "Közegészségügyi Rendelő & Magánklinika",
            "allowedRegisterCount": 2,
            "rateMultiplier": 1.10
        }
    }

    @staticmethod
    def round_to_cent(val):
        val = float(val or 0.0)
        return math.floor(val * 100.0 + 0.5) / 100.0

    @classmethod
    def calculate_lease_initial_costs(cls, base_rent, deposit_multiplier=1, tax_rate=0.0500):
        rent = max(100.00, cls.round_to_cent(base_rent))
        dep_mult = float(deposit_multiplier or 1)
        t_rate = max(0.00, min(0.30, float(tax_rate or 0.0500)))

        security_deposit = cls.round_to_cent(rent * dep_mult)
        municipal_tax = cls.round_to_cent(rent * t_rate)
        net_to_lessor = cls.round_to_cent(rent - municipal_tax)

        # Cent conservation assertion
        delta = cls.round_to_cent(rent - (net_to_lessor + municipal_tax))
        if abs(delta) > 0.0001:
            net_to_lessor = cls.round_to_cent(net_to_lessor + delta)

        total_upfront = cls.round_to_cent(rent + security_deposit)

        return {
            "cycleRent": rent,
            "securityDeposit": security_deposit,
            "municipalTax": municipal_tax,
            "netToLessor": net_to_lessor,
            "totalUpfrontRequired": total_upfront,
            "taxRate": t_rate
        }

    @classmethod
    def calculate_recurring_rent_split(cls, cycle_rent, tax_rate=0.0500):
        rent = max(0.00, cls.round_to_cent(cycle_rent))
        t_rate = max(0.00, min(0.30, float(tax_rate or 0.0500)))

        municipal_tax = cls.round_to_cent(rent * t_rate)
        net_to_lessor = cls.round_to_cent(rent - municipal_tax)

        delta = cls.round_to_cent(rent - (net_to_lessor + municipal_tax))
        if abs(delta) > 0.0001:
            net_to_lessor = cls.round_to_cent(net_to_lessor + delta)

        return {
            "grossRent": rent,
            "municipalTax": municipal_tax,
            "netToLessor": net_to_lessor,
            "taxRate": t_rate
        }

    @classmethod
    def calculate_arrears_settlement(cls, arrears_balance, late_penalty_rate=0.1000):
        arrears = max(0.00, cls.round_to_cent(arrears_balance))
        p_rate = float(late_penalty_rate or 0.1000)

        penalty = cls.round_to_cent(arrears * p_rate)
        total_due = cls.round_to_cent(arrears + penalty)

        return {
            "arrearsBalance": arrears,
            "penaltyAmount": penalty,
            "penaltyRate": p_rate,
            "totalSettlementDue": total_due
        }

    @classmethod
    def evaluate_delinquency_state(cls, missed_cycles, arrears, grace_expires_at=None, eviction_deadline_at=None, now=1000000):
        missed = max(0, int(missed_cycles or 0))
        arrears = max(0.00, cls.round_to_cent(arrears or 0.00))

        if missed == 0 and arrears <= 0.00:
            return {
                "tier": 0,
                "status": "active",
                "isLockedOut": False,
                "isRegistersDisabled": False,
                "isEvictionDue": False
            }

        if missed >= 4 or (eviction_deadline_at and now >= eviction_deadline_at):
            return {
                "tier": 4,
                "status": "evicted",
                "isLockedOut": True,
                "isRegistersDisabled": True,
                "isEvictionDue": True
            }

        if missed >= 2 or (grace_expires_at and now >= grace_expires_at):
            tier = 3 if missed >= 3 else 2
            return {
                "tier": tier,
                "status": "lapsed",
                "isLockedOut": True,
                "isRegistersDisabled": True,
                "isEvictionDue": False
            }

        return {
            "tier": 1,
            "status": "grace_period",
            "isLockedOut": False,
            "isRegistersDisabled": False,
            "isEvictionDue": False
        }

    @classmethod
    def evaluate_doorlock_authorization(cls, prop, lease, citizen_id, job="unemployed", faction_id=None, permissions=None, has_warrant=False):
        if not prop:
            return False, "PROPERTY_NOT_FOUND"

        if job in ("police", "sheriff") and has_warrant:
            return True, "AUTHORIZED_POLICE_WARRANT"

        if not lease or not lease.get("lease_status") or lease.get("lease_status") == "not_leased":
            return None, "USE_STANDARD_PROPERTY_LOCKS"

        status = lease.get("lease_status")
        tier = lease.get("delinquency_tier", 0)
        if status in ("lapsed", "evicted") or tier >= 2:
            return False, "LOCK_OFFLINE_LEASE_LAPSED"

        lessee_type = lease.get("lessee_type")
        if lessee_type == "citizen":
            if citizen_id and (citizen_id == lease.get("lessee_id") or citizen_id == lease.get("authorized_signer_citizen_id")):
                return True, "AUTHORIZED_CITIZEN_LESSEE"
        elif lessee_type == "faction":
            if faction_id and faction_id == lease.get("lessee_id"):
                perms = permissions or {}
                if perms.get("*") or perms.get("property:manage") or perms.get("warehouse:access") or (citizen_id == lease.get("authorized_signer_citizen_id")):
                    return True, "AUTHORIZED_FACTION_MEMBER"

        if prop.get("ownerCitizenId") and prop.get("ownerCitizenId") == citizen_id:
            return True, "AUTHORIZED_LANDLORD_INSPECTION"

        return False, "UNAUTHORIZED_NO_LEASE_KEY"

    @classmethod
    def evaluate_register_operation(cls, lease):
        if not lease:
            return False, "NO_ACTIVE_LEASE"
        status = lease.get("lease_status")
        if status not in ("active", "grace_period"):
            return False, "REGISTER_DISABLED_LEASE_LAPSED"
        if lease.get("delinquency_tier", 0) >= 2:
            return False, "REGISTER_DISABLED_DELINQUENT"
        return True, "REGISTER_OPERATIONAL"

    @classmethod
    def validate_lease_proposal(cls, payload):
        if not isinstance(payload, dict):
            return False, "INVALID_PAYLOAD"

        prop_id = payload.get("propertyId")
        if not prop_id or int(prop_id) <= 0:
            return False, "INVALID_PROPERTY_ID"

        lessee_type = payload.get("lesseeType", "faction")
        if lessee_type not in ("faction", "citizen"):
            return False, "INVALID_LESSEE_TYPE"

        lessee_id = str(payload.get("lesseeId", "")).strip()
        if len(lessee_id) < 2 or len(lessee_id) > 64:
            return False, "INVALID_LESSEE_ID"

        signer = str(payload.get("authorizedSignerCitizenId", "")).strip()
        if len(signer) < 2 or len(signer) > 16:
            return False, "INVALID_SIGNER_CITIZEN_ID"

        zoning = payload.get("zoningUsage", "retail_storefront")
        if zoning not in cls.ZoningTypes:
            return False, "INVALID_ZONING_TYPE"

        rent = payload.get("cycleRent")
        if rent is None or float(rent) < 100.0 or float(rent) > 1000000.0:
            return False, "INVALID_CYCLE_RENT"

        term_cycles = int(payload.get("leaseTermCycles", 4))
        if term_cycles < 1 or term_cycles > 52:
            return False, "INVALID_TERM_CYCLES"

        return True, {
            "propertyId": int(prop_id),
            "lesseeType": lessee_type,
            "lesseeId": lessee_id,
            "authorizedSignerCitizenId": signer,
            "zoningUsage": zoning,
            "cycleRent": cls.round_to_cent(rent),
            "leaseTermCycles": term_cycles
        }


# ==============================================================================
# PYTEST TEST SUITE
# ==============================================================================

def test_migration_058_and_index_registration():
    """Verify migration 058 exists in core, properties, and factions, and is registered in index.json."""
    core_mig = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "058_commercial_real_estate_leasing_and_storefront_cycles.sql")
    prop_mig = os.path.join(FIVEM_DIR, "nyx_properties", "sql", "migrations", "058_commercial_real_estate_leasing_and_storefront_cycles.sql")
    fact_mig = os.path.join(FIVEM_DIR, "nyx_factions", "sql", "migrations", "058_commercial_real_estate_leasing_and_storefront_cycles.sql")
    index_file = os.path.join(FIVEM_DIR, "nyx_core", "sql", "migrations", "index.json")

    assert os.path.isfile(core_mig), "058 migration missing from nyx_core"
    assert os.path.isfile(prop_mig), "058 migration missing from nyx_properties"
    assert os.path.isfile(fact_mig), "058 migration missing from nyx_factions"

    with open(index_file, "r", encoding="utf-8") as f:
        index_data = json.load(f)
    assert "058_commercial_real_estate_leasing_and_storefront_cycles.sql" in index_data

    with open(core_mig, "r", encoding="utf-8") as f:
        sql = f.read()

    assert "CREATE TABLE IF NOT EXISTS `nyx_property_commercial_leases`" in sql
    assert "CREATE TABLE IF NOT EXISTS `nyx_property_lease_audits`" in sql
    assert "pool:property:lease_escrow" in sql
    assert "ADD COLUMN IF NOT EXISTS `is_leased`" in sql
    assert "ADD COLUMN IF NOT EXISTS `commercial_zoning`" in sql


def test_fxmanifest_declarations():
    """Verify shared, server, and client scripts are properly registered in manifests."""
    prop_manifest = os.path.join(FIVEM_DIR, "nyx_properties", "fxmanifest.lua")
    with open(prop_manifest, "r", encoding="utf-8") as f:
        prop_content = f.read()

    assert "'shared/commercial_leases.lua'" in prop_content
    assert "'server/leases.lua'" in prop_content
    assert "'client/leases.lua'" in prop_content

    fact_manifest = os.path.join(FIVEM_DIR, "nyx_factions", "fxmanifest.lua")
    with open(fact_manifest, "r", encoding="utf-8") as f:
        fact_content = f.read()

    assert "'@nyx_properties/shared/commercial_leases.lua'" in fact_content


def test_commercial_zoning_taxonomy():
    """Verify commercial zoning types and statutory properties."""
    zonings = CommercialLeaseEngine.ZoningTypes
    assert "retail_storefront" in zonings
    assert "corporate_office" in zonings
    assert "industrial_warehouse" in zonings
    assert "hospitality_venue" in zonings
    assert "medical_clinic" in zonings

    assert zonings["retail_storefront"]["allowedRegisterCount"] == 4
    assert zonings["corporate_office"]["rateMultiplier"] == 1.15
    assert zonings["industrial_warehouse"]["rateMultiplier"] == 0.90


def test_initial_lease_costs_exact_cent_conservation():
    """Verify zero-cent economic conservation in upfront lease cost calculations."""
    costs1 = CommercialLeaseEngine.calculate_lease_initial_costs(3500.00, deposit_multiplier=1, tax_rate=0.0500)
    assert costs1["cycleRent"] == 3500.00
    assert costs1["securityDeposit"] == 3500.00
    assert costs1["municipalTax"] == 175.00
    assert costs1["netToLessor"] == 3325.00
    assert costs1["totalUpfrontRequired"] == 7000.00
    assert math.isclose(costs1["netToLessor"] + costs1["municipalTax"], costs1["cycleRent"], abs_tol=0.001)

    # Test uneven cents
    costs2 = CommercialLeaseEngine.calculate_lease_initial_costs(1234.57, deposit_multiplier=2, tax_rate=0.0500)
    assert math.isclose(costs2["netToLessor"] + costs2["municipalTax"], costs2["cycleRent"], abs_tol=0.001)
    assert costs2["totalUpfrontRequired"] == round(costs2["cycleRent"] + costs2["securityDeposit"], 2)


def test_recurring_rent_split_conservation():
    """Verify closed-loop double-entry rent split to lessor and municipal tax."""
    split = CommercialLeaseEngine.calculate_recurring_rent_split(6500.00, tax_rate=0.0500)
    assert split["grossRent"] == 6500.00
    assert split["municipalTax"] == 325.00
    assert split["netToLessor"] == 6175.00
    assert math.isclose(split["netToLessor"] + split["municipalTax"], split["grossRent"], abs_tol=0.001)


def test_arrears_settlement_calculation():
    """Verify 10% statutory late penalty computation on overdue lease arrears."""
    settlement = CommercialLeaseEngine.calculate_arrears_settlement(5000.00, late_penalty_rate=0.1000)
    assert settlement["arrearsBalance"] == 5000.00
    assert settlement["penaltyAmount"] == 500.00
    assert settlement["totalSettlementDue"] == 5500.00


def test_delinquency_state_machine_and_eviction_triggers():
    """Verify 4-tier delinquency progression from active to grace, lapsed, and eviction."""
    now = 1000000

    # Tier 0: Solvent
    s0 = CommercialLeaseEngine.evaluate_delinquency_state(0, 0.00, None, None, now)
    assert s0["tier"] == 0
    assert s0["status"] == "active"
    assert s0["isLockedOut"] is False
    assert s0["isRegistersDisabled"] is False

    # Tier 1: Grace Period
    s1 = CommercialLeaseEngine.evaluate_delinquency_state(1, 3500.00, now + 172800, now + 259200, now)
    assert s1["tier"] == 1
    assert s1["status"] == "grace_period"
    assert s1["isLockedOut"] is False

    # Tier 2: Lapsed & Lockout
    s2 = CommercialLeaseEngine.evaluate_delinquency_state(2, 7000.00, now - 100, now + 100000, now)
    assert s2["tier"] == 2
    assert s2["status"] == "lapsed"
    assert s2["isLockedOut"] is True
    assert s2["isRegistersDisabled"] is True

    # Tier 4: Eviction Due (4 missed cycles)
    s4_cycles = CommercialLeaseEngine.evaluate_delinquency_state(4, 14000.00, now - 200, now + 100, now)
    assert s4_cycles["tier"] == 4
    assert s4_cycles["status"] == "evicted"
    assert s4_cycles["isEvictionDue"] is True

    # Tier 4: Eviction Due (Expired eviction deadline)
    s4_deadline = CommercialLeaseEngine.evaluate_delinquency_state(2, 7000.00, now - 200, now - 10, now)
    assert s4_deadline["tier"] == 4
    assert s4_deadline["status"] == "evicted"
    assert s4_deadline["isEvictionDue"] is True


def test_doorlock_authorization_and_delinquency_lockout():
    """Verify multi-tier doorlock permissions and lockout interlock when lapsed."""
    prop = {"id": 101, "ownerCitizenId": "LANDLORD_CIT_01", "type": "commercial"}
    active_lease = {
        "lease_status": "active",
        "delinquency_tier": 0,
        "lessee_type": "faction",
        "lessee_id": "corp_vanilla_unicorn",
        "authorized_signer_citizen_id": "CIT_SIGNER_01"
    }
    lapsed_lease = {
        "lease_status": "lapsed",
        "delinquency_tier": 2,
        "lessee_type": "faction",
        "lessee_id": "corp_vanilla_unicorn",
        "authorized_signer_citizen_id": "CIT_SIGNER_01"
    }

    # Active tenant member: Allowed
    ok_act, _ = CommercialLeaseEngine.evaluate_doorlock_authorization(
        prop, active_lease, "CIT_MEMBER", "unemployed", "corp_vanilla_unicorn", {"warehouse:access": True}
    )
    assert ok_act is True

    # Lapsed lease: Denied with LOCK_OFFLINE_LEASE_LAPSED
    ok_lapsed, reason_lapsed = CommercialLeaseEngine.evaluate_doorlock_authorization(
        prop, lapsed_lease, "CIT_MEMBER", "unemployed", "corp_vanilla_unicorn", {"warehouse:access": True}
    )
    assert ok_lapsed is False
    assert reason_lapsed == "LOCK_OFFLINE_LEASE_LAPSED"

    # Police warrant override on lapsed property: Allowed
    ok_police, _ = CommercialLeaseEngine.evaluate_doorlock_authorization(
        prop, lapsed_lease, "COP_01", "police", None, None, has_warrant=True
    )
    assert ok_police is True

    # Landlord inspection on active lease: Allowed
    ok_landlord, _ = CommercialLeaseEngine.evaluate_doorlock_authorization(
        prop, active_lease, "LANDLORD_CIT_01", "unemployed", None, None, False
    )
    assert ok_landlord is True


def test_register_operation_delinquency_interlock():
    """Verify commercial register point-of-sale functionality is disabled upon lease lapse."""
    active_lease = {"lease_status": "active", "delinquency_tier": 0}
    lapsed_lease = {"lease_status": "lapsed", "delinquency_tier": 2}

    ok_act, _ = CommercialLeaseEngine.evaluate_register_operation(active_lease)
    assert ok_act is True

    ok_lap, reason = CommercialLeaseEngine.evaluate_register_operation(lapsed_lease)
    assert ok_lap is False
    assert reason == "REGISTER_DISABLED_LEASE_LAPSED"


def test_lease_proposal_validation():
    """Verify validation and sanitization of commercial lease proposals."""
    valid_payload = {
        "propertyId": 2,
        "lesseeType": "faction",
        "lesseeId": "corp_vanilla_unicorn",
        "authorizedSignerCitizenId": "CIT_SIGNER_01",
        "zoningUsage": "retail_storefront",
        "cycleRent": 3500.00,
        "leaseTermCycles": 8
    }
    ok, clean = CommercialLeaseEngine.validate_lease_proposal(valid_payload)
    assert ok is True
    assert clean["propertyId"] == 2
    assert clean["cycleRent"] == 3500.00

    # Invalid cycle rent (< 100)
    bad_rent = dict(valid_payload, cycleRent=50.00)
    ok_bad_rent, err = CommercialLeaseEngine.validate_lease_proposal(bad_rent)
    assert ok_bad_rent is False
    assert err == "INVALID_CYCLE_RENT"

    # Invalid zoning
    bad_zoning = dict(valid_payload, zoningUsage="residential_slum")
    ok_bad_zoning, err = CommercialLeaseEngine.validate_lease_proposal(bad_zoning)
    assert ok_bad_zoning is False
    assert err == "INVALID_ZONING_TYPE"


def test_in_engine_test_53_registered():
    """Verify TestCommercialRealEstateLeasingAndStorefrontCycles is registered in server/tests.lua."""
    tests_lua = os.path.join(FIVEM_DIR, "nyx_core", "server", "tests.lua")
    with open(tests_lua, "r", encoding="utf-8") as f:
        content = f.read()

    assert "function Nyx.Tests.TestCommercialRealEstateLeasingAndStorefrontCycles()" in content
    assert "local t53 = Nyx.Tests.TestCommercialRealEstateLeasingAndStorefrontCycles()" in content
    assert "suites1to50Passed and t51 and t52 and t53" in content
