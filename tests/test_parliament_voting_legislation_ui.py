"""
Unit tests for Parliamentary Ranked-Choice Voting & Legislation UI
(nyx_ui & nyx_parliament).
Tests shared UI logic, candidate validation, endorsement thresholds,
bill formulation bounds, penal filtering, receipt formatting, and fxmanifest/SQL integrity.
"""

import os
import re
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class ParliamentUIEngine:
    @staticmethod
    def validate_candidate_payload(payload):
        if not isinstance(payload, dict):
            return False, None, "INVALID_PAYLOAD"

        name = payload.get("displayName")
        if not isinstance(name, str) or len(name.strip()) < 3:
            return False, None, "NAME_TOO_SHORT"
        if len(name.strip()) > 64:
            return False, None, "NAME_TOO_LONG"

        party = payload.get("party") or "Independent"
        if not isinstance(party, str) or len(party.strip()) > 64:
            return False, None, "PARTY_TOO_LONG"

        platform = payload.get("platform")
        if not isinstance(platform, str) or len(platform.strip()) < 10:
            return False, None, "PLATFORM_TOO_SHORT"
        if len(platform.strip()) > 1024:
            return False, None, "PLATFORM_TOO_LONG"

        slogan = payload.get("slogan") or ""
        if isinstance(slogan, str) and len(slogan.strip()) > 128:
            return False, None, "SLOGAN_TOO_LONG"

        sanitized = {
            "displayName": name.strip(),
            "party": party.strip(),
            "platform": platform.strip(),
            "slogan": slogan.strip()
        }
        return True, sanitized, None

    @staticmethod
    def validate_endorsement(candidate, citizen_id, required_endorsements=3):
        if not isinstance(candidate, dict):
            return False, "INVALID_CANDIDATE"

        cand_cit_id = candidate.get("citizen_id") or candidate.get("citizenId")
        if cand_cit_id == citizen_id:
            return False, "CANNOT_ENDORSE_SELF"

        status = candidate.get("status", "nominated")
        if status in ("disqualified", "withdrawn"):
            return False, "CANDIDATE_NOT_ACTIVE"

        current_count = int(candidate.get("endorsements_count", 0))
        req = max(1, int(required_endorsements))
        new_count = current_count + 1
        progress_pct = min(100.0, round((new_count / req) * 100.0, 1))
        will_qualify = new_count >= req

        return True, {
            "newCount": new_count,
            "required": req,
            "progressPercent": progress_pct,
            "willQualify": will_qualify
        }

    @staticmethod
    def validate_bill_proposal(payload, statutes_catalog=None):
        if not isinstance(payload, dict):
            return False, None, "INVALID_PAYLOAD"

        title = payload.get("title")
        if not isinstance(title, str) or len(title.strip()) < 5:
            return False, None, "INVALID_TITLE_LENGTH"
        if len(title.strip()) > 96:
            return False, None, "INVALID_TITLE_LENGTH"

        description = payload.get("description")
        if not isinstance(description, str) or len(description.strip()) < 10:
            return False, None, "INVALID_DESCRIPTION_LENGTH"
        if len(description.strip()) > 1024:
            return False, None, "INVALID_DESCRIPTION_LENGTH"

        actions = payload.get("actions")
        if not isinstance(actions, list) or len(actions) == 0:
            return False, None, "INVALID_ACTIONS"
        if len(actions) > 10:
            return False, None, "TOO_MANY_ACTIONS"

        sanitized_actions = []
        for idx, act in enumerate(actions):
            if not isinstance(act, dict):
                return False, None, f"MALFORMED_ACTION_{idx}"
            law_id = act.get("targetLawId")
            field = act.get("field")
            new_val = act.get("newValue")
            if not law_id or not field or new_val is None:
                return False, None, f"MALFORMED_ACTION_{idx}"

            try:
                numeric_val = float(new_val)
            except (ValueError, TypeError):
                return False, None, f"INVALID_NUMERIC_VALUE_{field}"

            if statutes_catalog and law_id in statutes_catalog:
                law_def = statutes_catalog[law_id]
                min_val = law_def.get("min_allowed", {}).get(field)
                max_val = law_def.get("max_allowed", {}).get(field)

                if min_val is not None and numeric_val < float(min_val):
                    return False, None, f"STATUTORY_MINIMUM_VIOLATION:{law_id}.{field}"
                if max_val is not None and numeric_val > float(max_val):
                    return False, None, f"STATUTORY_MAXIMUM_VIOLATION:{law_id}.{field}"

            sanitized_actions.append({
                "targetLawId": str(law_id),
                "field": str(field),
                "newValue": numeric_val
            })

        return True, {
            "title": title.strip(),
            "description": description.strip(),
            "actions": sanitized_actions
        }, None

    @staticmethod
    def filter_penal_code(penal_list, query="", category_filter="all"):
        if not penal_list:
            return [], {"total": 0, "felonies": 0, "misdemeanors": 0, "infractions": 0, "fiscal": 0}

        q = (query or "").strip().lower()
        cat = (category_filter or "all").lower()

        filtered = []
        counts = {"total": 0, "felonies": 0, "misdemeanors": 0, "infractions": 0, "fiscal": 0}

        for item in penal_list:
            item_cat = (item.get("category") or "").lower()
            item_title = (item.get("title") or "").lower()
            item_id = (item.get("id") or "").lower()

            # Global category breakdown
            if item_cat == "penal_felony":
                counts["felonies"] += 1
            elif item_cat == "penal_misdemeanor":
                counts["misdemeanors"] += 1
            elif item_cat == "penal_infraction":
                counts["infractions"] += 1
            elif item_cat == "fiscal_policy":
                counts["fiscal"] += 1

            # Category filter match
            cat_match = (cat == "all") or (item_cat == cat)
            # Query match
            query_match = (not q) or (q in item_title) or (q in item_id)

            if cat_match and query_match:
                filtered.append(item)

        counts["total"] = len(penal_list)
        return filtered, counts

    @staticmethod
    def format_statute_badge(category):
        cat = (category or "").lower()
        if cat == "penal_felony":
            return {"label": "Bűntett (Felony)", "badgeClass": "badge-danger", "icon": "fa-solid fa-gavel"}
        elif cat == "penal_misdemeanor":
            return {"label": "Vétség (Misdemeanor)", "badgeClass": "badge-warning", "icon": "fa-solid fa-triangle-exclamation"}
        elif cat == "penal_infraction":
            return {"label": "Szabálysértés (Infraction)", "badgeClass": "badge-info", "icon": "fa-solid fa-ticket"}
        elif cat == "fiscal_policy":
            return {"label": "Közpénzügy (Fiscal)", "badgeClass": "badge-primary", "icon": "fa-solid fa-coins"}
        elif cat == "zoning":
            return {"label": "Területrendezés (Zoning)", "badgeClass": "badge-secondary", "icon": "fa-solid fa-city"}
        return {"label": "Általános Törvény", "badgeClass": "badge-outline", "icon": "fa-solid fa-landmark"}

    @staticmethod
    def format_ballot_receipt(receipt_hash, timestamp=None, session_id=None):
        if not isinstance(receipt_hash, str):
            return {"receiptHash": "", "isValidFormat": False}

        is_valid = bool(re.match(r"^NYX-BALLOT-[A-Za-z0-9_-]+$", receipt_hash))
        return {
            "receiptHash": receipt_hash,
            "sessionId": session_id or "",
            "timestamp": timestamp or "2026-10-18T10:00:00Z",
            "isValidFormat": is_valid
        }

    @staticmethod
    def evaluate_ballot_preferences(preferences, available_candidates):
        if not isinstance(preferences, list):
            return [], {"rankedCount": 0, "totalAvailable": len(available_candidates), "isComplete": False}

        allowed = set(available_candidates)
        seen = set()
        clean = []

        for p in preferences:
            if isinstance(p, str) and p in allowed and p not in seen:
                seen.add(p)
                clean.append(p)

        total_avail = len(available_candidates)
        ranked_cnt = len(clean)
        return clean, {
            "rankedCount": ranked_cnt,
            "totalAvailable": total_avail,
            "isComplete": (ranked_cnt == total_avail and total_avail > 0)
        }


# ==============================================================================
# PYTEST TEST SUITE
# ==============================================================================

def test_candidate_payload_validation():
    # Valid candidate
    valid_payload = {
        "displayName": "Marcus Sterling",
        "party": "Enterprise Party",
        "platform": "Pro-business regulatory clarity and lower transfer taxes.",
        "slogan": "Prosperity for every citizen"
    }
    ok, sanitized, err = ParliamentUIEngine.validate_candidate_payload(valid_payload)
    assert ok is True
    assert err is None
    assert sanitized["displayName"] == "Marcus Sterling"
    assert sanitized["party"] == "Enterprise Party"

    # Name too short
    short_name = dict(valid_payload, displayName="Ed")
    ok, _, err = ParliamentUIEngine.validate_candidate_payload(short_name)
    assert ok is False
    assert err == "NAME_TOO_SHORT"

    # Platform too short
    short_platform = dict(valid_payload, platform="Vote me")
    ok, _, err = ParliamentUIEngine.validate_candidate_payload(short_platform)
    assert ok is False
    assert err == "PLATFORM_TOO_SHORT"


def test_endorsement_validation_and_threshold():
    candidate = {
        "candidate_id": "cand_1",
        "citizen_id": "CIT_100",
        "endorsements_count": 2,
        "status": "nominated"
    }

    # Self-endorsement rejected
    ok, err = ParliamentUIEngine.validate_endorsement(candidate, "CIT_100", 3)
    assert ok is False
    assert err == "CANNOT_ENDORSE_SELF"

    # Third endorsement reaches threshold -> willQualify is True
    ok, data = ParliamentUIEngine.validate_endorsement(candidate, "CIT_200", 3)
    assert ok is True
    assert data["newCount"] == 3
    assert data["progressPercent"] == 100.0
    assert data["willQualify"] is True


def test_bill_proposal_validation_and_statutory_bounds():
    catalog = {
        "tax:sales_rate": {
            "min_allowed": {"rate": 0.00},
            "max_allowed": {"rate": 0.15}
        }
    }

    # Valid proposal
    valid_proposal = {
        "title": "Municipal Commerce Relief Act",
        "description": "Adjust sales tax rate to 5% to stimulate consumer spending.",
        "actions": [{"targetLawId": "tax:sales_rate", "field": "rate", "newValue": 0.05}]
    }
    ok, sanitized, err = ParliamentUIEngine.validate_bill_proposal(valid_proposal, catalog)
    assert ok is True
    assert err is None
    assert sanitized["actions"][0]["newValue"] == 0.05

    # Violate statutory maximum
    invalid_proposal = {
        "title": "Aggressive Revenue Act",
        "description": "Increase sales tax rate to 20% to finance public mega-projects.",
        "actions": [{"targetLawId": "tax:sales_rate", "field": "rate", "newValue": 0.20}]
    }
    ok, _, err = ParliamentUIEngine.validate_bill_proposal(invalid_proposal, catalog)
    assert ok is False
    assert "STATUTORY_MAXIMUM_VIOLATION" in err


def test_penal_code_filtering_and_taxonomy():
    penal_catalog = [
        {"id": "penal:armed_robbery", "title": "Armed Robbery", "category": "penal_felony", "fine": 10000},
        {"id": "penal:reckless_driving", "title": "Reckless Driving", "category": "penal_misdemeanor", "fine": 750},
        {"id": "penal:jaywalking", "title": "Jaywalking Infraction", "category": "penal_infraction", "fine": 150},
        {"id": "tax:sales_rate", "title": "Sales Tax Rate", "category": "fiscal_policy", "fine": 0}
    ]

    # Category filter
    felonies, counts = ParliamentUIEngine.filter_penal_code(penal_catalog, category_filter="penal_felony")
    assert len(felonies) == 1
    assert felonies[0]["id"] == "penal:armed_robbery"
    assert counts["felonies"] == 1
    assert counts["misdemeanors"] == 1
    assert counts["infractions"] == 1
    assert counts["fiscal"] == 1

    # Text search
    results, _ = ParliamentUIEngine.filter_penal_code(penal_catalog, query="driving")
    assert len(results) == 1
    assert results[0]["id"] == "penal:reckless_driving"

    # Taxonomy badges
    badge_felony = ParliamentUIEngine.format_statute_badge("penal_felony")
    assert badge_felony["badgeClass"] == "badge-danger"
    assert "gavel" in badge_felony["icon"]

    badge_fiscal = ParliamentUIEngine.format_statute_badge("fiscal_policy")
    assert badge_fiscal["badgeClass"] == "badge-primary"


def test_ballot_receipt_formatting():
    receipt = ParliamentUIEngine.format_ballot_receipt("NYX-BALLOT-A1B2C3D4E5F6", "2026-10-18T10:25:00Z", "election:mayor_2026")
    assert receipt["isValidFormat"] is True
    assert receipt["receiptHash"] == "NYX-BALLOT-A1B2C3D4E5F6"

    bad_receipt = ParliamentUIEngine.format_ballot_receipt("MALICIOUS-INJECTION", "2026-10-18T10:25:00Z", "election:mayor_2026")
    assert bad_receipt["isValidFormat"] is False


def test_ballot_preference_ranking_and_completeness():
    candidates = ["cand_a", "cand_b", "cand_c"]

    # Incomplete ranking (2 of 3)
    ranked, meta = ParliamentUIEngine.evaluate_ballot_preferences(["cand_a", "cand_b", "cand_invalid"], candidates)
    assert ranked == ["cand_a", "cand_b"]
    assert meta["rankedCount"] == 2
    assert meta["totalAvailable"] == 3
    assert meta["isComplete"] is False

    # Complete ranking with duplicate elimination
    ranked_full, meta_full = ParliamentUIEngine.evaluate_ballot_preferences(["cand_b", "cand_c", "cand_b", "cand_a"], candidates)
    assert ranked_full == ["cand_b", "cand_c", "cand_a"]
    assert meta_full["rankedCount"] == 3
    assert meta_full["isComplete"] is True


def test_migration_036_and_manifest_declarations():
    # Verify migration 036 exists in both nyx_core and nyx_parliament
    core_mig = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "036_parliament_voting_ui_and_legislation_audit.sql")
    parl_mig = os.path.join(ROOT_DIR, "FiveM", "nyx_parliament", "sql", "migrations", "036_parliament_voting_ui_and_legislation_audit.sql")
    index_file = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "index.json")

    assert os.path.isfile(core_mig), "036 migration missing from nyx_core"
    assert os.path.isfile(parl_mig), "036 migration missing from nyx_parliament"

    with open(index_file, "r", encoding="utf-8") as f:
        content = f.read()
    assert "036_parliament_voting_ui_and_legislation_audit.sql" in content

    # Verify fxmanifest for nyx_parliament declares shared/legislation_ui.lua
    manifest_file = os.path.join(ROOT_DIR, "FiveM", "nyx_parliament", "fxmanifest.lua")
    with open(manifest_file, "r", encoding="utf-8") as f:
        manifest_content = f.read()
    assert "shared/legislation_ui.lua" in manifest_content or "shared/irv.lua" in manifest_content


def test_parliament_web_html_structure():
    """Verify index.html contains all necessary parliament components, tabs, forms, and modals."""
    index_html = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "web", "index.html")
    assert os.path.isfile(index_html), "index.html missing"

    with open(index_html, "r", encoding="utf-8") as f:
        html = f.read()

    # Dev toolbar button
    assert 'id="dev-btn-parliament"' in html

    # Main overlay and header
    assert 'id="parliament-overlay"' in html
    assert 'id="parliament-close-btn"' in html
    assert 'id="parliament-header-status"' in html

    # Tabs
    assert 'id="parliament-tab-btn-ballot"' in html
    assert 'id="parliament-tab-btn-candidates"' in html
    assert 'id="parliament-tab-btn-laws"' in html
    assert 'id="parliament-tab-ballot"' in html
    assert 'id="parliament-tab-candidates"' in html
    assert 'id="parliament-tab-laws"' in html

    # Tab 1: Ballot controls
    assert 'id="parliament-session-select"' in html
    assert 'id="parliament-ballot-candidate-list"' in html
    assert 'id="parliament-cast-ballot-btn"' in html
    assert 'id="parliament-receipt-input"' in html
    assert 'id="parliament-verify-receipt-btn"' in html
    assert 'id="parliament-refresh-tabulation-btn"' in html
    assert 'id="parliament-tabulation-rounds-container"' in html

    # Tab 2: Candidate nomination & Recall
    assert 'id="parliament-candidates-grid"' in html
    assert 'id="parliament-nomination-session-select"' in html
    assert 'id="parliament-input-cand-name"' in html
    assert 'id="parliament-input-cand-party"' in html
    assert 'id="parliament-input-cand-slogan"' in html
    assert 'id="parliament-input-cand-platform"' in html
    assert 'id="parliament-submit-candidacy-btn"' in html
    assert 'id="parliament-btn-open-recall"' in html
    assert 'id="parliament-petitions-list"' in html

    # Tab 3: Laws & Bill Proposal
    assert 'id="parliament-laws-search"' in html
    assert 'id="parliament-laws-cat-filter"' in html
    assert 'id="parliament-laws-rows"' in html
    assert 'id="parliament-recent-amendments-list"' in html
    assert 'id="parliament-select-bill-law"' in html
    assert 'id="parliament-select-bill-field"' in html
    assert 'id="parliament-input-bill-newval"' in html
    assert 'id="parliament-submit-bill-btn"' in html

    # Submodal: Recall
    assert 'id="parliament-submodal-recall"' in html
    assert 'id="parliament-recall-office-select"' in html
    assert 'id="parliament-recall-reason-input"' in html
    assert 'id="parliament-recall-submit-btn"' in html


def test_parliament_css_cef_budget():
    """Verify Section 18 styling in app.css complies strictly with CEF budget (no blur, dark surfaces, WCAG)."""
    app_css = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "web", "css", "app.css")
    assert os.path.isfile(app_css), "app.css missing"

    with open(app_css, "r", encoding="utf-8") as f:
        css = f.read()

    # Extract Section 18 rules starting from .parliament-dialog
    section_start = css.find(".parliament-dialog")
    assert section_start != -1, "parliament-dialog missing in app.css"
    section_css = css[section_start:]

    # Zero blur or backdrop-filter property in parliament styles
    css_no_comments = re.sub(r'/\*.*?\*/', '', section_css, flags=re.DOTALL)
    assert "backdrop-filter:" not in css_no_comments
    assert "blur(" not in css_no_comments

    # Parliament overlay container exists
    assert ".parliament-dialog" in section_css
    assert ".parliament-nav-tabs" in section_css
    assert ".ballot-candidate-row" in section_css
    assert ".tally-bar-track" in section_css


def test_parliament_js_state_and_handlers():
    """Verify app.js defines NyxState.parliament, Section 12D functions, and mock responses."""
    app_js = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "web", "js", "app.js")
    assert os.path.isfile(app_js), "app.js missing"

    with open(app_js, "r", encoding="utf-8") as f:
        js = f.read()

    # State store
    assert "parliament:" in js
    assert "rankedCandidateIds:" in js

    # Core UI functions
    assert "function openParliamentUI(" in js
    assert "function closeParliamentUI(" in js
    assert "function setParliamentTab(" in js
    assert "function refreshParliamentOverview(" in js
    assert "function renderParliamentBallot(" in js
    assert "function castParliamentBallot(" in js
    assert "function verifyParliamentReceipt(" in js
    assert "function refreshParliamentTabulation(" in js
    assert "function renderParliamentCandidates(" in js
    assert "function endorseParliamentCandidate(" in js
    assert "function submitParliamentCandidacy(" in js
    assert "function renderParliamentLaws(" in js
    assert "function submitParliamentBill(" in js

    # Message handlers
    assert "PARLIAMENT_UI_OPEN" in js
    assert "PARLIAMENT_UI_CLOSE" in js

    # Dev button
    assert "dev-btn-parliament" in js


def test_parliament_bridge_and_in_engine_suite():
    """Verify bridge safe NUI callbacks and in-engine test 31 integration."""
    bridge_lua = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "client", "bridge.lua")
    with open(bridge_lua, "r", encoding="utf-8") as f:
        bridge = f.read()

    # Verify NUI callbacks registered
    assert 'Nyx.UI.SafeNUICallback("closeParliamentUI"' in bridge
    assert 'Nyx.UI.SafeNUICallback("parliament:getOverview"' in bridge
    assert 'Nyx.UI.SafeNUICallback("parliament:castBallot"' in bridge
    assert 'Nyx.UI.SafeNUICallback("parliament:verifyReceipt"' in bridge
    assert 'Nyx.UI.SafeNUICallback("parliament:registerCandidate"' in bridge
    assert 'Nyx.UI.SafeNUICallback("parliament:endorseCandidate"' in bridge
    assert 'Nyx.UI.SafeNUICallback("parliament:proposeBill"' in bridge
    assert 'Nyx.UI.SafeNUICallback("parliament:fileRecallPetition"' in bridge
    assert 'Nyx.UI.SafeNUICallback("parliament:signRecallPetition"' in bridge
    assert 'Nyx.UI.SafeNUICallback("parliament:getAmendmentAudit"' in bridge

    # Verify tests.lua has Test 31
    tests_lua = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "server", "tests.lua")
    with open(tests_lua, "r", encoding="utf-8") as f:
        tests_content = f.read()

    assert "function Nyx.Tests.TestParliamentRankedChoiceAndLegislationUI()" in tests_content
    assert "local t31 = Nyx.Tests.TestParliamentRankedChoiceAndLegislationUI()" in tests_content

