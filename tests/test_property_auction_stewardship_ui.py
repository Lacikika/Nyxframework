"""
Unit tests for Property Blind-Auction & Stewardship Portal UI
(nyx_ui & nyx_properties).
Tests shared UI logic, sealed-bid validation, blind auction data masking,
proxy stewardship delegation, catalog filtering, delinquency badges,
countdown timer calculations, SQL migration 037 integrity, and CEF SPA compliance.
"""

import os
import json
import re
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class PropertyPortalUIEngine:
    @staticmethod
    def format_currency(amount):
        try:
            amt = float(amount or 0)
        except (ValueError, TypeError):
            return "$0"

        int_part = int(abs(amt))
        formatted_int = f"{int_part:,}"

        cents = round((abs(amt) - int_part) * 100)
        sign = "-" if amt < 0 else ""
        if cents > 0:
            return f"{sign}${formatted_int}.{cents:02d}"
        return f"{sign}${formatted_int}"

    @staticmethod
    def validate_bid_payload(payload, minimum_bid=None, player_bank_balance=None):
        if not isinstance(payload, dict):
            return False, None, "INVALID_BID_PAYLOAD"

        auction_id = payload.get("auctionId") or payload.get("auction_id")
        try:
            auction_id = int(auction_id)
            if auction_id <= 0:
                return False, None, "INVALID_AUCTION_ID"
        except (TypeError, ValueError):
            return False, None, "INVALID_AUCTION_ID"

        bid_amount = payload.get("bidAmount") or payload.get("bid_amount") or payload.get("amount")
        try:
            bid_amount = float(bid_amount)
            if bid_amount <= 0:
                return False, None, "INVALID_BID_AMOUNT"
        except (TypeError, ValueError):
            return False, None, "INVALID_BID_AMOUNT"

        bid_amount = round(bid_amount, 2)

        if minimum_bid is not None and bid_amount < float(minimum_bid):
            return False, None, "BID_BELOW_MINIMUM_FLOOR"

        if player_bank_balance is not None and bid_amount > float(player_bank_balance):
            return False, None, "INSUFFICIENT_FUNDS"

        return True, {
            "auctionId": auction_id,
            "bidAmount": bid_amount
        }, None

    @staticmethod
    def mask_blind_auction(auction, viewer_citizen_id=None):
        if not isinstance(auction, dict):
            return {}

        is_blind = bool(auction.get("is_blind") or auction.get("isBlind"))
        highest_bidder = auction.get("highest_bidder") or auction.get("highestBidder")
        highest_bid = float(auction.get("highest_bid") or auction.get("highestBid") or 0.0)
        is_my_lead = bool(viewer_citizen_id and highest_bidder and viewer_citizen_id == highest_bidder)

        masked = {
            "auction_id": auction.get("auction_id") or auction.get("auctionId"),
            "property_id": auction.get("property_id") or auction.get("propertyId"),
            "property_title": auction.get("property_title") or auction.get("propertyTitle") or "Ingatlan",
            "property_address": auction.get("property_address") or auction.get("propertyAddress") or "",
            "property_type": auction.get("property_type") or auction.get("propertyType") or "residential",
            "minimum_bid": float(auction.get("minimum_bid") or auction.get("minimumBid") or 0.0),
            "is_blind": is_blind,
            "total_bids_placed": int(auction.get("total_bids_placed") or auction.get("totalBidsPlaced") or 0),
            "end_time": int(auction.get("end_time") or auction.get("endTime") or 0),
            "isMyLead": is_my_lead,
            "status": auction.get("status", "active")
        }

        if is_blind:
            if is_my_lead:
                masked["highest_bid"] = highest_bid
                masked["highest_bidder"] = highest_bidder
                masked["mySealedBid"] = highest_bid
                masked["isSealed"] = False
            else:
                masked["highest_bid"] = None
                masked["highest_bidder"] = None
                masked["mySealedBid"] = None
                masked["isSealed"] = True
        else:
            masked["highest_bid"] = highest_bid
            masked["highest_bidder"] = highest_bidder
            masked["mySealedBid"] = highest_bid if is_my_lead else None
            masked["isSealed"] = False

        return masked

    @staticmethod
    def validate_delegation_payload(payload, owner_citizen_id=None):
        if not isinstance(payload, dict):
            return False, None, "INVALID_DELEGATION_PAYLOAD"

        property_id = payload.get("propertyId") or payload.get("property_id")
        try:
            property_id = int(property_id)
            if property_id <= 0:
                return False, None, "INVALID_PROPERTY_ID"
        except (TypeError, ValueError):
            return False, None, "INVALID_PROPERTY_ID"

        delegate_citizen_id = payload.get("delegateCitizenId") or payload.get("delegate_citizen_id")
        if not isinstance(delegate_citizen_id, str) or len(delegate_citizen_id.strip()) < 3:
            return False, None, "INVALID_DELEGATE_CITIZEN_ID"

        delegate_citizen_id = delegate_citizen_id.strip()
        if owner_citizen_id and delegate_citizen_id == owner_citizen_id:
            return False, None, "CANNOT_DELEGATE_TO_SELF"

        scope = str(payload.get("scope") or "maintenance").lower().strip()
        valid_scopes = {"maintenance", "sublease", "full"}
        if scope not in valid_scopes:
            return False, None, "INVALID_DELEGATION_SCOPE"

        notes = str(payload.get("notes") or "").strip()
        if len(notes) > 255:
            notes = notes[:255]

        return True, {
            "propertyId": property_id,
            "delegateCitizenId": delegate_citizen_id,
            "scope": scope,
            "notes": notes
        }, None

    @staticmethod
    def validate_steward_assignment_payload(payload, admin_citizen_id=None):
        if not isinstance(payload, dict):
            return False, None, "INVALID_ASSIGNMENT_PAYLOAD"

        property_id = payload.get("propertyId") or payload.get("property_id")
        try:
            property_id = int(property_id)
            if property_id <= 0:
                return False, None, "INVALID_PROPERTY_ID"
        except (TypeError, ValueError):
            return False, None, "INVALID_PROPERTY_ID"

        steward_citizen_id = payload.get("stewardCitizenId") or payload.get("steward_citizen_id")
        if not isinstance(steward_citizen_id, str) or len(steward_citizen_id.strip()) < 3:
            return False, None, "INVALID_STEWARD_CITIZEN_ID"

        steward_citizen_id = steward_citizen_id.strip()

        tax_cap = payload.get("taxSettlementCap") or payload.get("tax_settlement_cap") or 50000.0
        try:
            tax_cap = float(tax_cap)
            if tax_cap < 0:
                return False, None, "INVALID_TAX_CAP"
        except (TypeError, ValueError):
            return False, None, "INVALID_TAX_CAP"

        authority_basis = str(payload.get("authorityBasis") or "MUNICIPAL_DELINQUENCY_SEIZURE").strip()
        if len(authority_basis) < 3 or len(authority_basis) > 64:
            return False, None, "INVALID_AUTHORITY_BASIS"

        return True, {
            "propertyId": property_id,
            "stewardCitizenId": steward_citizen_id,
            "taxSettlementCap": tax_cap,
            "authorityBasis": authority_basis
        }, None

    @staticmethod
    def filter_properties_catalog(catalog, search_query=None, type_filter=None, status_filter=None):
        if not isinstance(catalog, list):
            return []

        q = (search_query or "").lower().strip()
        t_filter = (type_filter or "all").lower().strip()
        s_filter = (status_filter or "all").lower().strip()

        filtered = []
        for p in catalog:
            if not isinstance(p, dict):
                continue

            matches_query = True
            if q:
                title = str(p.get("title") or p.get("property_title") or "").lower()
                addr = str(p.get("address") or p.get("property_address") or "").lower()
                pid = str(p.get("property_id") or p.get("propertyId") or "").lower()
                matches_query = (q in title) or (q in addr) or (q in pid)

            matches_type = True
            if t_filter and t_filter != "all":
                p_type = str(p.get("property_type") or p.get("propertyType") or "residential").lower()
                matches_type = (p_type == t_filter)

            matches_status = True
            if s_filter and s_filter != "all":
                p_status = str(p.get("status") or p.get("delinquencyStatus") or "current").lower()
                matches_status = (p_status == s_filter)

            if matches_query and matches_type and matches_status:
                filtered.append(p)

        return filtered

    @staticmethod
    def format_delinquency_badge(delinquent_tax_amount):
        try:
            tax = float(delinquent_tax_amount or 0.0)
        except (TypeError, ValueError):
            tax = 0.0

        if tax <= 0:
            return {"badgeClass": "badge-success", "label": "NAPRAKÉSZ", "tier": "current", "icon": "fa-circle-check"}
        elif tax < 5000:
            return {"badgeClass": "badge-warning", "label": "FIGYELMEZTETÉS", "tier": "warning", "icon": "fa-triangle-exclamation"}
        elif tax < 10000:
            return {"badgeClass": "badge-danger", "label": "ADÓZÁLOG", "tier": "lien", "icon": "fa-file-invoice-dollar"}
        else:
            return {"badgeClass": "badge-danger", "label": "LEFOGLALVA", "tier": "foreclosure", "icon": "fa-gavel"}

    @staticmethod
    def calculate_remaining_time(end_time, current_time=None):
        try:
            target = int(end_time or 0)
        except (TypeError, ValueError):
            target = 0

        now = int(current_time) if current_time is not None else 1770000000
        diff = target - now

        if diff <= 0:
            return {"remainingSeconds": 0, "isExpired": True, "formatted": "LEJÁRT"}

        hours = diff // 3600
        minutes = (diff % 3600) // 60
        seconds = diff % 60

        return {
            "remainingSeconds": diff,
            "isExpired": False,
            "formatted": f"{hours:02d}h {minutes:02d}m {seconds:02d}s"
        }


# =========================================================================
# TEST SUITE: Core Logic, Confidentiality, Validation & Invariants
# =========================================================================

def test_sealed_bid_validation():
    engine = PropertyPortalUIEngine()

    # 1. Valid bid above minimum floor and within balance
    ok, data, err = engine.validate_bid_payload({"auctionId": 12, "bidAmount": 85000.50}, minimum_bid=50000, player_bank_balance=100000)
    assert ok is True
    assert data["auctionId"] == 12
    assert data["bidAmount"] == 85000.50
    assert err is None

    # 2. Sub-floor bid rejection
    ok, data, err = engine.validate_bid_payload({"auctionId": 12, "bidAmount": 49999.00}, minimum_bid=50000, player_bank_balance=100000)
    assert ok is False
    assert err == "BID_BELOW_MINIMUM_FLOOR"

    # 3. Insufficient bank balance
    ok, data, err = engine.validate_bid_payload({"auctionId": 12, "bidAmount": 150000}, minimum_bid=50000, player_bank_balance=100000)
    assert ok is False
    assert err == "INSUFFICIENT_FUNDS"

    # 4. Negative and zero bid amounts
    ok, _, err = engine.validate_bid_payload({"auctionId": 12, "bidAmount": 0})
    assert ok is False
    assert err == "INVALID_BID_AMOUNT"

    ok, _, err = engine.validate_bid_payload({"auctionId": 12, "bidAmount": -500})
    assert ok is False
    assert err == "INVALID_BID_AMOUNT"

    # 5. Invalid auction ID
    ok, _, err = engine.validate_bid_payload({"auctionId": 0, "bidAmount": 50000})
    assert ok is False
    assert err == "INVALID_AUCTION_ID"


def test_blind_auction_data_confidentiality_masking():
    engine = PropertyPortalUIEngine()

    raw_auction = {
        "auction_id": 101,
        "property_id": 45,
        "property_title": "Rockford Hills Mansion",
        "minimum_bid": 500000.0,
        "highest_bid": 750000.0,
        "highest_bidder": "CIT_LEAD_WHALE",
        "is_blind": 1,
        "total_bids_placed": 7,
        "end_time": 1779999999
    }

    # 1. Competitor view (must be masked and sealed)
    masked_competitor = engine.mask_blind_auction(raw_auction, viewer_citizen_id="CIT_COMPETITOR")
    assert masked_competitor["is_blind"] is True
    assert masked_competitor["highest_bid"] is None, "Highest bid must be hidden from competitor"
    assert masked_competitor["highest_bidder"] is None, "Highest bidder must be hidden from competitor"
    assert masked_competitor["isSealed"] is True
    assert masked_competitor["mySealedBid"] is None
    assert masked_competitor["isMyLead"] is False
    assert masked_competitor["total_bids_placed"] == 7
    assert masked_competitor["minimum_bid"] == 500000.0

    # 2. Leading bidder view (reveals their own bid)
    masked_leader = engine.mask_blind_auction(raw_auction, viewer_citizen_id="CIT_LEAD_WHALE")
    assert masked_leader["is_blind"] is True
    assert masked_leader["highest_bid"] == 750000.0
    assert masked_leader["highest_bidder"] == "CIT_LEAD_WHALE"
    assert masked_leader["isMyLead"] is True
    assert masked_leader["mySealedBid"] == 750000.0
    assert masked_leader["isSealed"] is False

    # 3. Non-blind auction transparency
    open_auction = dict(raw_auction)
    open_auction["is_blind"] = 0
    masked_open = engine.mask_blind_auction(open_auction, viewer_citizen_id="CIT_COMPETITOR")
    assert masked_open["is_blind"] is False
    assert masked_open["highest_bid"] == 750000.0
    assert masked_open["highest_bidder"] == "CIT_LEAD_WHALE"
    assert masked_open["isSealed"] is False


def test_proxy_stewardship_delegation_validation():
    engine = PropertyPortalUIEngine()

    # 1. Valid delegation payload
    ok, data, err = engine.validate_delegation_payload({
        "propertyId": 22,
        "delegateCitizenId": "CIT_TRUSTEE_99",
        "scope": "full",
        "notes": "Renovation and tenant management authorization"
    }, owner_citizen_id="CIT_OWNER_01")
    assert ok is True
    assert data["propertyId"] == 22
    assert data["delegateCitizenId"] == "CIT_TRUSTEE_99"
    assert data["scope"] == "full"
    assert err is None

    # 2. Self-delegation guard
    ok, data, err = engine.validate_delegation_payload({
        "propertyId": 22,
        "delegateCitizenId": "CIT_OWNER_01",
        "scope": "maintenance"
    }, owner_citizen_id="CIT_OWNER_01")
    assert ok is False
    assert err == "CANNOT_DELEGATE_TO_SELF"

    # 3. Invalid delegate citizen id
    ok, _, err = engine.validate_delegation_payload({"propertyId": 22, "delegateCitizenId": "  "})
    assert ok is False
    assert err == "INVALID_DELEGATE_CITIZEN_ID"

    # 4. Invalid scope
    ok, _, err = engine.validate_delegation_payload({
        "propertyId": 22,
        "delegateCitizenId": "CIT_PROXY",
        "scope": "root_superadmin"
    })
    assert ok is False
    assert err == "INVALID_DELEGATION_SCOPE"

    # 5. Invalid property id
    ok, _, err = engine.validate_delegation_payload({"propertyId": -5, "delegateCitizenId": "CIT_PROXY"})
    assert ok is False
    assert err == "INVALID_PROPERTY_ID"


def test_steward_assignment_validation():
    engine = PropertyPortalUIEngine()

    ok, data, err = engine.validate_steward_assignment_payload({
        "propertyId": 8,
        "stewardCitizenId": "CIT_STEWARD_CORP",
        "taxSettlementCap": 45000.0,
        "authorityBasis": "MUNICIPAL_DELINQUENCY_RECEIVERSHIP"
    })
    assert ok is True
    assert data["propertyId"] == 8
    assert data["stewardCitizenId"] == "CIT_STEWARD_CORP"
    assert data["taxSettlementCap"] == 45000.0
    assert data["authorityBasis"] == "MUNICIPAL_DELINQUENCY_RECEIVERSHIP"

    # Invalid tax cap
    ok, _, err = engine.validate_steward_assignment_payload({
        "propertyId": 8,
        "stewardCitizenId": "CIT_STEWARD_CORP",
        "taxSettlementCap": -100
    })
    assert ok is False
    assert err == "INVALID_TAX_CAP"


def test_property_catalog_multi_dimensional_filtering():
    engine = PropertyPortalUIEngine()

    sample_catalog = [
        {"property_id": 1, "title": "Del Perro Penthouse", "address": "110 Del Perro Heights", "property_type": "residential", "status": "current"},
        {"property_id": 2, "title": "Paleto Bay Warehouse", "address": "44 Industrial Way", "property_type": "industrial", "status": "lien"},
        {"property_id": 3, "title": "Legion Square Retail", "address": "200 Vinewood Blvd", "property_type": "commercial", "status": "warning"},
        {"property_id": 4, "title": "Mirror Park Townhome", "address": "12 Nikola Ave", "property_type": "residential", "status": "foreclosure"}
    ]

    # Search query
    res_search = engine.filter_properties_catalog(sample_catalog, search_query="del perro")
    assert len(res_search) == 1
    assert res_search[0]["property_id"] == 1

    # Type filter
    res_type = engine.filter_properties_catalog(sample_catalog, type_filter="industrial")
    assert len(res_type) == 1
    assert res_type[0]["property_id"] == 2

    # Status filter
    res_status = engine.filter_properties_catalog(sample_catalog, status_filter="foreclosure")
    assert len(res_status) == 1
    assert res_status[0]["property_id"] == 4

    # Combined filter
    res_combined = engine.filter_properties_catalog(sample_catalog, search_query="nikola", type_filter="residential", status_filter="foreclosure")
    assert len(res_combined) == 1
    assert res_combined[0]["property_id"] == 4

    # No match
    res_none = engine.filter_properties_catalog(sample_catalog, search_query="nonexistent")
    assert len(res_none) == 0


def test_delinquency_badge_taxonomy_and_currency_format():
    engine = PropertyPortalUIEngine()

    # Badges
    b0 = engine.format_delinquency_badge(0)
    assert b0["tier"] == "current"
    assert b0["badgeClass"] == "badge-success"
    assert b0["label"] == "NAPRAKÉSZ"

    b1 = engine.format_delinquency_badge(3200)
    assert b1["tier"] == "warning"
    assert b1["badgeClass"] == "badge-warning"
    assert b1["label"] == "FIGYELMEZTETÉS"

    b2 = engine.format_delinquency_badge(7500)
    assert b2["tier"] == "lien"
    assert b2["badgeClass"] == "badge-danger"
    assert b2["label"] == "ADÓZÁLOG"

    b3 = engine.format_delinquency_badge(18000)
    assert b3["tier"] == "foreclosure"
    assert b3["badgeClass"] == "badge-danger"
    assert b3["label"] == "LEFOGLALVA"

    # Currency format
    assert engine.format_currency(0) == "$0"
    assert engine.format_currency(1250000) == "$1,250,000"
    assert engine.format_currency(450.75) == "$450.75"
    assert engine.format_currency(-500) == "-$500"


def test_countdown_timer_calculation():
    engine = PropertyPortalUIEngine()
    cur_time = 1770000000

    # 1 hour, 1 min, 5 sec in future
    res_future = engine.calculate_remaining_time(cur_time + 3665, current_time=cur_time)
    assert res_future["isExpired"] is False
    assert res_future["remainingSeconds"] == 3665
    assert res_future["formatted"] == "01h 01m 05s"

    # Expired
    res_expired = engine.calculate_remaining_time(cur_time - 100, current_time=cur_time)
    assert res_expired["isExpired"] is True
    assert res_expired["remainingSeconds"] == 0
    assert res_expired["formatted"] == "LEJÁRT"


# =========================================================================
# TEST SUITE: Schema, Migration 037, Manifest & CEF SPA Integrity
# =========================================================================

def test_sql_migration_037_registration_and_content():
    # 1. Registered in index.json
    index_path = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "index.json")
    with open(index_path, "r", encoding="utf-8") as f:
        migrations = json.load(f)

    assert "037_property_blind_auction_and_stewardship_portal.sql" in migrations, "Migration 037 must be in index.json"

    # 2. Migration files exist in nyx_core and nyx_properties
    core_sql_path = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "037_property_blind_auction_and_stewardship_portal.sql")
    props_sql_path = os.path.join(ROOT_DIR, "FiveM", "nyx_properties", "sql", "migrations", "037_property_blind_auction_and_stewardship_portal.sql")

    assert os.path.isfile(core_sql_path), "037 migration must exist in nyx_core"
    assert os.path.isfile(props_sql_path), "037 migration must exist in nyx_properties"

    with open(core_sql_path, "r", encoding="utf-8") as f:
        sql = f.read()

    assert "CREATE TABLE IF NOT EXISTS `nyx_property_auction_bids`" in sql
    assert "`bid_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY" in sql
    assert "`auction_id` INT UNSIGNED NOT NULL" in sql
    assert "`bidder_citizen_id` VARCHAR(16) NOT NULL" in sql
    assert "`bid_amount` DECIMAL(15, 2) NOT NULL" in sql
    assert "`is_refunded` TINYINT(1) NOT NULL DEFAULT 0" in sql
    assert "`is_sealed` TINYINT(1) NOT NULL DEFAULT 1" in sql
    assert "ALTER TABLE `nyx_property_auctions`" in sql
    assert "ADD COLUMN IF NOT EXISTS `is_blind`" in sql
    assert "ADD COLUMN IF NOT EXISTS `total_bids_placed`" in sql
    assert "ALTER TABLE `nyx_stewardship_delegates`" in sql
    assert "ADD COLUMN IF NOT EXISTS `revocation_reason`" in sql


def test_fxmanifest_declarations():
    props_manifest_path = os.path.join(ROOT_DIR, "FiveM", "nyx_properties", "fxmanifest.lua")
    with open(props_manifest_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "shared/portal_ui.lua" in content, "shared/portal_ui.lua must be declared in nyx_properties fxmanifest"
    assert "client/portal_ui.lua" in content, "client/portal_ui.lua must be declared in nyx_properties fxmanifest"


def test_nui_bridge_endpoints_and_sanitization():
    bridge_path = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "client", "bridge.lua")
    with open(bridge_path, "r", encoding="utf-8") as f:
        content = f.read()

    expected_callbacks = [
        "closePropertyPortal",
        "property:getOverview",
        "property:getActiveAuctions",
        "property:placeBid",
        "property:getAuctionBids",
        "property:payArrears",
        "property:repairCondition",
        "property:getTaxAssessment",
        "property:registerDelegate",
        "property:revokeDelegate",
        "property:assignSteward",
        "property:getMyStewardship",
        "property:getInactivityAuditLogs"
    ]

    for cb in expected_callbacks:
        assert f'SafeNUICallback("{cb}"' in content or f"SafeNUICallback('{cb}'" in content, f"Callback {cb} must be registered in bridge.lua"

    # Sanitizer whitelist check
    assert "auctionId" in content
    assert "bidAmount" in content
    assert "delegateCitizenId" in content
    assert "scope" in content


def test_cef_spa_budget_and_dom_elements():
    html_path = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "web", "index.html")
    css_path = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "web", "css", "app.css")
    js_path = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "web", "js", "app.js")

    with open(html_path, "r", encoding="utf-8") as f:
        html = f.read()
    with open(css_path, "r", encoding="utf-8") as f:
        css = f.read()
    with open(js_path, "r", encoding="utf-8") as f:
        js = f.read()

    # 1. Strict CEF Budget
    assert "backdrop-filter" not in css, "Strict CEF render budget prohibits backdrop-filter"
    assert "blur(" not in css, "Strict CEF render budget prohibits blur() shaders"

    # 2. HTML elements
    expected_html_ids = [
        "property-portal-overlay",
        "property-portal-close-btn",
        "prop-tab-btn-auctions",
        "prop-tab-btn-taxation",
        "prop-tab-btn-stewardship",
        "prop-tab-auctions",
        "prop-tab-taxation",
        "prop-tab-stewardship",
        "prop-auctions-grid",
        "prop-owned-list",
        "prop-delegates-list",
        "prop-managed-properties-list",
        "prop-reclamation-logs-list",
        "property-submodal-bid",
        "property-submodal-assign",
        "dev-btn-property"
    ]
    for el_id in expected_html_ids:
        assert f'id="{el_id}"' in html, f"Element #{el_id} must exist in index.html"

    # 3. JS State and Handlers
    assert "openPropertyPortal" in js
    assert "closePropertyPortal" in js
    assert "PROPERTY_PORTAL_OPEN" in js
    assert "PROPERTY_PORTAL_CLOSE" in js
    assert "NyxState.property" in js
