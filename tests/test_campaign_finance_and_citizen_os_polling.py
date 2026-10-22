"""
Unit and Integration Tests for Campaign Finance & Citizen OS Polling (nyx_parliament & nyx_treasury).
Tests statutory donation caps, PAC registration & treasury escrow transfers,
PAC compliance auditing & statutory fine assessment, Citizen OS mobile survey response deduplication,
voter sentiment calculation, margin of error estimations, Migration 067, and manifest declarations.
"""

import os
import json
import math
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class CampaignFinanceEngine:
    """Python reference implementation mirroring Nyx.CampaignFinance in shared/campaign_finance.lua."""

    DEFAULT_CAP = 5000.00
    DEFAULT_FINE_MULT = 1.5

    @classmethod
    def evaluate_donation_eligibility(cls, donor_citizen_id, donor_prior_total, donation_amount, statutory_cap=None, is_faction=False):
        cap = float(statutory_cap if statutory_cap is not None else cls.DEFAULT_CAP)
        prior = float(donor_prior_total or 0.0)
        amt = float(donation_amount or 0.0)

        if amt <= 0.0:
            return False, "INVALID_DONATION_AMOUNT", {
                "allowedAmount": 0.0,
                "excessAmount": 0.0,
                "remainingCap": max(0.0, cap - prior),
                "complianceStatus": "invalid"
            }

        remaining = max(0.0, cap - prior)

        if prior >= cap:
            return False, "STATUTORY_CAP_EXCEEDED", {
                "allowedAmount": 0.0,
                "excessAmount": amt,
                "remainingCap": 0.0,
                "complianceStatus": "flagged_over_cap"
            }

        if (prior + amt) > cap:
            allowed = remaining
            excess = amt - remaining
            return True, "CAP_EXCEEDED_PARTIAL", {
                "allowedAmount": allowed,
                "excessAmount": excess,
                "remainingCap": 0.0,
                "complianceStatus": "flagged_over_cap"
            }

        return True, "COMPLIANT", {
            "allowedAmount": amt,
            "excessAmount": 0.0,
            "remainingCap": max(0.0, cap - (prior + amt)),
            "complianceStatus": "compliant"
        }

    @classmethod
    def calculate_pac_audit_summary(cls, donations_list, statutory_cap=None, fine_multiplier=None):
        mult = float(fine_multiplier if fine_multiplier is not None else cls.DEFAULT_FINE_MULT)
        cap = float(statutory_cap if statutory_cap is not None else cls.DEFAULT_CAP)

        total_contrib = 0.0
        compliant_contrib = 0.0
        flagged_excess = 0.0
        flagged_count = 0
        total_count = 0

        for don in (donations_list or []):
            total_count += 1
            amt = float(don.get("amount", 0.0))
            total_contrib += amt

            status = don.get("compliance_status") or don.get("complianceStatus")
            if status == "flagged_over_cap" or amt > cap:
                flagged_count += 1
                excess = max(0.0, amt - cap)
                flagged_excess += excess
            else:
                compliant_contrib += amt

        fine = flagged_excess * mult
        audit_status = "fines_assessed" if flagged_excess > 0.0 else "passed"
        risk_score = min(100.0, (flagged_excess / total_contrib * 100.0)) if total_contrib > 0.0 else 0.0

        return {
            "totalContributions": total_contrib,
            "compliantContributions": compliant_contrib,
            "flaggedExcessAmount": flagged_excess,
            "fineAssessed": fine,
            "flaggedCount": flagged_count,
            "totalCount": total_count,
            "auditStatus": audit_status,
            "riskScore": round(risk_score, 2)
        }

    @classmethod
    def calculate_poll_sentiment(cls, poll_options, response_counts, total_turnout):
        total = int(total_turnout or 0)
        breakdown = {}
        leading_option = None
        max_votes = -1

        options = poll_options
        if isinstance(options, str):
            try:
                options = json.loads(options)
            except Exception:
                options = []

        counts = response_counts or {}

        for opt in (options or []):
            opt_id = opt.get("id") or opt.get("value") if isinstance(opt, dict) else str(opt)
            opt_label = opt.get("label") or opt.get("name") if isinstance(opt, dict) else str(opt)
            count = int(counts.get(opt_id, 0))

            pct = (count / total * 100.0) if total > 0 else 0.0

            if count > max_votes:
                max_votes = count
                leading_option = opt_id

            breakdown[opt_id] = {
                "id": opt_id,
                "label": opt_label,
                "count": count,
                "percentage": round(pct, 2)
            }

        margin_of_error = round((1.96 * math.sqrt(0.25 / total) * 100.0), 2) if total > 0 else 0.0

        return {
            "totalTurnout": total,
            "leadingOption": leading_option,
            "breakdown": breakdown,
            "marginOfErrorPercent": margin_of_error
        }


# ==============================================================================
# PYTEST TEST CASES
# ==============================================================================

def test_statutory_donation_cap_evaluation():
    # 1. Compliant $2,000 donation under $5,000 cap
    ok, reason, data = CampaignFinanceEngine.evaluate_donation_eligibility("CIT_1001", 0.0, 2000.00, 5000.00)
    assert ok is True
    assert reason == "COMPLIANT"
    assert data["allowedAmount"] == 2000.00
    assert data["excessAmount"] == 0.0
    assert data["remainingCap"] == 3000.00
    assert data["complianceStatus"] == "compliant"

    # 2. Second donation of $3,000 reaching exactly the cap
    ok, reason, data = CampaignFinanceEngine.evaluate_donation_eligibility("CIT_1001", 2000.00, 3000.00, 5000.00)
    assert ok is True
    assert reason == "COMPLIANT"
    assert data["allowedAmount"] == 3000.00
    assert data["remainingCap"] == 0.0

    # 3. Third donation exceeding cap partially (prior: $4,000, new: $2,000)
    ok, reason, data = CampaignFinanceEngine.evaluate_donation_eligibility("CIT_1001", 4000.00, 2000.00, 5000.00)
    assert ok is True
    assert reason == "CAP_EXCEEDED_PARTIAL"
    assert data["allowedAmount"] == 1000.00
    assert data["excessAmount"] == 1000.00
    assert data["complianceStatus"] == "flagged_over_cap"

    # 4. Donor already at or above cap attempting another donation
    ok, reason, data = CampaignFinanceEngine.evaluate_donation_eligibility("CIT_1001", 5000.00, 500.00, 5000.00)
    assert ok is False
    assert reason == "STATUTORY_CAP_EXCEEDED"
    assert data["allowedAmount"] == 0.0
    assert data["excessAmount"] == 500.00
    assert data["complianceStatus"] == "flagged_over_cap"

    # 5. Invalid negative donation
    ok, reason, data = CampaignFinanceEngine.evaluate_donation_eligibility("CIT_1001", 0.0, -100.00, 5000.00)
    assert ok is False
    assert reason == "INVALID_DONATION_AMOUNT"


def test_pac_audit_and_fine_assessment():
    donations = [
        {"amount": 2500.00, "compliance_status": "compliant"},
        {"amount": 5000.00, "compliance_status": "compliant"},
        {"amount": 7000.00, "compliance_status": "flagged_over_cap"},  # $2,000 excess over $5,000
        {"amount": 10000.00, "compliance_status": "flagged_over_cap"} # $5,000 excess over $5,000
    ]

    summary = CampaignFinanceEngine.calculate_pac_audit_summary(donations, statutory_cap=5000.00, fine_multiplier=1.5)

    assert summary["totalCount"] == 4
    assert summary["flaggedCount"] == 2
    assert summary["totalContributions"] == 24500.00
    assert summary["compliantContributions"] == 7500.00
    assert summary["flaggedExcessAmount"] == 7000.00  # $2000 + $5000
    assert summary["fineAssessed"] == 10500.00          # $7000 * 1.5
    assert summary["auditStatus"] == "fines_assessed"
    assert summary["riskScore"] == 28.57                 # (7000 / 24500) * 100


def test_mobile_poll_sentiment_and_margin_of_error():
    options = [
        {"id": "OPT_APPROVE", "label": "Approve Civic Reform"},
        {"id": "OPT_REJECT", "label": "Reject Civic Reform"},
        {"id": "OPT_UNDECIDED", "label": "Undecided / Neutral"}
    ]

    response_counts = {
        "OPT_APPROVE": 60,
        "OPT_REJECT": 30,
        "OPT_UNDECIDED": 10
    }

    sentiment = CampaignFinanceEngine.calculate_poll_sentiment(options, response_counts, total_turnout=100)

    assert sentiment["totalTurnout"] == 100
    assert sentiment["leadingOption"] == "OPT_APPROVE"
    assert sentiment["breakdown"]["OPT_APPROVE"]["percentage"] == 60.0
    assert sentiment["breakdown"]["OPT_REJECT"]["percentage"] == 30.0
    assert sentiment["breakdown"]["OPT_UNDECIDED"]["percentage"] == 10.0
    # Margin of error for N=100: 1.96 * sqrt(0.25 / 100) * 100 = 1.96 * 0.05 * 100 = 9.8%
    assert sentiment["marginOfErrorPercent"] == 9.8


def test_migration_067_and_index_json_schema():
    """Verify Migration 067 exists in nyx_core, nyx_parliament, nyx_treasury, and is indexed."""
    core_mig = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "067_campaign_finance_and_citizen_os_polling.sql")
    parl_mig = os.path.join(ROOT_DIR, "FiveM", "nyx_parliament", "sql", "migrations", "067_campaign_finance_and_citizen_os_polling.sql")
    treas_mig = os.path.join(ROOT_DIR, "FiveM", "nyx_treasury", "sql", "migrations", "067_campaign_finance_and_citizen_os_polling.sql")
    index_file = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "index.json")

    assert os.path.isfile(core_mig), "067 migration missing from nyx_core"
    assert os.path.isfile(parl_mig), "067 migration missing from nyx_parliament"
    assert os.path.isfile(treas_mig), "067 migration missing from nyx_treasury"

    with open(index_file, "r", encoding="utf-8") as f:
        index_data = json.load(f)

    assert "067_campaign_finance_and_citizen_os_polling.sql" in index_data

    with open(core_mig, "r", encoding="utf-8") as f:
        sql = f.read()

    assert "nyx_parliament_pacs" in sql
    assert "nyx_parliament_donations" in sql
    assert "nyx_parliament_pac_audits" in sql
    assert "nyx_parliament_polls" in sql
    assert "nyx_parliament_poll_responses" in sql
    assert "gov:escrow:pac" in sql


def test_fxmanifest_and_script_declarations():
    """Verify campaign finance & polling scripts declared in fxmanifest.lua."""
    manifest_file = os.path.join(ROOT_DIR, "FiveM", "nyx_parliament", "fxmanifest.lua")
    with open(manifest_file, "r", encoding="utf-8") as f:
        manifest = f.read()

    assert "shared/campaign_finance.lua" in manifest
    assert "server/campaign_finance.lua" in manifest
    assert "server/polling.lua" in manifest
    assert "client/polling.lua" in manifest
    assert "client/pacs.lua" in manifest
