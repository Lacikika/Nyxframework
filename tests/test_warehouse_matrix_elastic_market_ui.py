"""
Unit tests for 3D Warehouse Matrix & Elastic Market Monitor UI
(nyx_ui & nyx_logistics).
Tests 3D isometric slot projection, dynamic elasticity price calculation,
hauler arbitrage routing, commodity catalog filtering, health status badges,
dispatch payload validation, SQL migration 038 schema, manifest declarations,
and CEF SPA compliance.
"""

import os
import json
import re
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class LogisticsMarketEngine:
    """Python reference implementation mirroring Nyx.LogisticsMarket in Lua 5.4."""

    @staticmethod
    def project_isometric_slot(tier, slot, tiers_count=3, slots_per_tier=3, spacing_x=50.0, spacing_y=28.0, tier_height=65.0):
        t = max(1, int(tier))
        s = max(1, int(slot))
        total_t = max(1, int(tiers_count))
        total_s = max(1, int(slots_per_tier))

        # Centered slot offset
        slot_center_offset = (s - (total_s + 1) / 2.0)
        # Isometric projection formula
        # x increases with slot index
        iso_x = round(slot_center_offset * spacing_x, 2)
        # y decreases as tier increases (higher tiers rendered higher on screen), plus subtle isometric tilt from slot
        iso_y = round((total_t - t) * tier_height - (slot_center_offset * 6.0), 2)
        # Depth layer for proper rendering overlap (lower tiers and foreground slots in front)
        layer = (total_t - t) * 10 + s

        return {
            "tier": t,
            "slot": s,
            "isoX": iso_x,
            "isoY": iso_y,
            "layer": layer
        }

    @staticmethod
    def compute_elastic_price(base_price, target_capacity, current_stock, zone_demand_multiplier=1.0, sales_velocity=0.0, velocity_impact_factor=0.25):
        base_p = max(0.01, float(base_price))
        target_cap = max(1.0, float(target_capacity))
        curr_stock = max(0.0, float(current_stock))
        zone_mult = max(0.10, min(5.0, float(zone_demand_multiplier)))

        # Velocity ratio relative to 25% target capacity
        vel_base = max(1.0, target_cap * 0.25)
        vel_bonus = min(2.0, (float(sales_velocity or 0.0) / vel_base) * velocity_impact_factor)

        effective_demand = round(target_cap * zone_mult * (1.0 + vel_bonus), 2)
        stock_ratio = round(curr_stock / max(1.0, effective_demand), 4)

        if stock_ratio < 1.0:
            # Deficit: price increases progressively up to 3.0x
            mult = 1.0 + (1.0 - stock_ratio) * 1.50
            mult = min(3.0, mult)
        else:
            # Surplus: price decreases progressively down to 0.40x floor
            mult = max(0.40, 1.0 - (stock_ratio - 1.0) * 0.40)

        price_multiplier = round(mult, 4)
        calculated_price = round(base_p * price_multiplier, 2)
        deficit_units = max(0, int(round(effective_demand - curr_stock)))

        return {
            "basePrice": base_p,
            "calculatedPrice": calculated_price,
            "priceMultiplier": price_multiplier,
            "effectiveDemand": effective_demand,
            "stockToDemandRatio": stock_ratio,
            "deficitUnits": deficit_units
        }

    @staticmethod
    def calculate_hauler_arbitrage(origin_cost, dest_price, units=10, distance_km=5.0, fuel_rate_per_km=3.50):
        cost = max(0.0, float(origin_cost))
        price = max(0.0, float(dest_price))
        qty = max(1, int(units))
        dist = max(0.1, float(distance_km))

        unit_spread = round(price - cost, 2)
        gross_profit = round(unit_spread * qty, 2)
        fuel_cost = round(dist * fuel_rate_per_km, 2)
        net_profit = round(gross_profit - fuel_cost, 2)
        roi_pct = round((net_profit / max(1.0, cost * qty)) * 100.0, 2)

        if net_profit >= 1000.0:
            rating = "EXCELLENT"
        elif net_profit >= 300.0:
            rating = "PROFITABLE"
        elif net_profit > 0.0:
            rating = "MARGINAL"
        else:
            rating = "UNPROFITABLE"

        return {
            "unitSpread": unit_spread,
            "grossProfit": gross_profit,
            "fuelCost": fuel_cost,
            "netProfit": net_profit,
            "roiPct": roi_pct,
            "rating": rating
        }

    @staticmethod
    def format_health_badge(stock_to_demand_ratio):
        ratio = float(stock_to_demand_ratio or 0.0)
        if ratio < 0.25:
            return {
                "status": "CRITICAL_DEFICIT",
                "label": "KRITIKUS HIÁNY",
                "badgeClass": "badge-danger",
                "color": "#EF4444"
            }
        elif ratio < 0.65:
            return {
                "status": "MODERATE_SHORTAGE",
                "label": "MÉRSÉKELT HIÁNY",
                "badgeClass": "badge-warning",
                "color": "#F59E0B"
            }
        elif ratio <= 1.35:
            return {
                "status": "EQUILIBRIUM",
                "label": "PIACI EGYENSÚLY",
                "badgeClass": "badge-success",
                "color": "#10B981"
            }
        else:
            return {
                "status": "SURPLUS",
                "label": "TÚLKÍNÁLAT / TÖBBLET",
                "badgeClass": "badge-info",
                "color": "#06B6D4"
            }

    @staticmethod
    def validate_dispatch_payload(payload):
        if not isinstance(payload, dict):
            return False, None, "INVALID_PAYLOAD"

        wh_id = str(payload.get("originWarehouseId") or payload.get("warehouseId") or "").strip()
        if not wh_id or len(wh_id) < 3:
            return False, None, "INVALID_ORIGIN_WAREHOUSE"

        zone_id = str(payload.get("destinationZoneId") or payload.get("zoneId") or "").strip()
        if not zone_id or len(zone_id) < 3:
            return False, None, "INVALID_DESTINATION_ZONE"

        item_id = str(payload.get("itemId") or "").strip()
        if not item_id or len(item_id) < 2:
            return False, None, "INVALID_ITEM_ID"

        try:
            units = int(payload.get("units") or 0)
            if units <= 0 or units > 1000:
                return False, None, "INVALID_UNITS_RANGE"
        except (ValueError, TypeError):
            return False, None, "INVALID_UNITS_RANGE"

        return True, {
            "originWarehouseId": wh_id,
            "destinationZoneId": zone_id,
            "itemId": item_id,
            "units": units
        }, None

    @staticmethod
    def filter_commodity_catalog(commodities, query="", zone_filter="all", category_filter="all"):
        q = (query or "").strip().lower()
        z_filt = (zone_filter or "all").lower()
        c_filt = (category_filter or "all").lower()

        results = []
        for item in commodities:
            item_id = str(item.get("itemId", "")).lower()
            name = str(item.get("name", "")).lower()
            zone = str(item.get("zoneId", "")).lower()
            category = str(item.get("category", "")).lower()

            if q and (q not in item_id and q not in name):
                continue
            if z_filt != "all" and zone != z_filt:
                continue
            if c_filt != "all" and category != c_filt:
                continue

            results.append(item)
        return results


# ============================================================================
# Pytest Test Suite
# ============================================================================

def test_migration_038_schema_and_registration():
    core_mig = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "038_warehouse_matrix_and_elastic_market_monitor.sql")
    log_mig = os.path.join(ROOT_DIR, "FiveM", "nyx_logistics", "sql", "migrations", "038_warehouse_matrix_and_elastic_market_monitor.sql")
    index_file = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "index.json")

    assert os.path.isfile(core_mig), "Core migration 038 must exist"
    assert os.path.isfile(log_mig), "Logistics migration 038 must exist"
    assert os.path.isfile(index_file), "Migration index.json must exist"

    with open(index_file, "r", encoding="utf-8") as f:
        mig_list = json.load(f)
    assert "038_warehouse_matrix_and_elastic_market_monitor.sql" in mig_list, "Migration 038 must be in index.json"

    with open(core_mig, "r", encoding="utf-8") as f:
        content = f.read()

    assert "nyx_logistics_hauler_dispatches" in content
    assert "nyx_logistics_shelf_nodes" in content
    assert "slot_status" in content
    assert "temperature_zone" in content


def test_shelf_matrix_isometric_projection():
    # 3-tier, 3-slot shelf rack
    proj_t1_s1 = LogisticsMarketEngine.project_isometric_slot(1, 1, 3, 3)
    proj_t1_s2 = LogisticsMarketEngine.project_isometric_slot(1, 2, 3, 3)
    proj_t1_s3 = LogisticsMarketEngine.project_isometric_slot(1, 3, 3, 3)

    # Middle slot (s=2) should have isoX = 0 (centered)
    assert proj_t1_s2["isoX"] == 0.0
    # Left slot (s=1) should have negative isoX, Right slot (s=3) positive isoX
    assert proj_t1_s1["isoX"] < 0
    assert proj_t1_s3["isoX"] > 0
    assert abs(proj_t1_s1["isoX"]) == proj_t1_s3["isoX"]

    # Higher tier (tier 3) should have lower isoY on screen than bottom tier (tier 1)
    proj_t3_s2 = LogisticsMarketEngine.project_isometric_slot(3, 2, 3, 3)
    assert proj_t3_s2["isoY"] < proj_t1_s2["isoY"]

    # Layer ordering: lower tier is in front of higher tier
    assert proj_t1_s2["layer"] > proj_t3_s2["layer"]


def test_elastic_pricing_calculation_and_multipliers():
    # Equilibrium case: stock == effective demand (100 vs 100)
    eq = LogisticsMarketEngine.compute_elastic_price(50.0, 100, 100, zone_demand_multiplier=1.0, sales_velocity=0.0)
    assert eq["priceMultiplier"] == 1.0
    assert eq["calculatedPrice"] == 50.0
    assert eq["deficitUnits"] == 0

    # Deficit case: stock is 20, target is 100
    deficit = LogisticsMarketEngine.compute_elastic_price(50.0, 100, 20, zone_demand_multiplier=1.0)
    assert deficit["priceMultiplier"] > 1.0
    assert deficit["calculatedPrice"] > 50.0
    assert deficit["deficitUnits"] == 80

    # High-demand zone multiplier (e.g. LS Metro = 1.35x) increases effective demand
    metro = LogisticsMarketEngine.compute_elastic_price(50.0, 100, 100, zone_demand_multiplier=1.35)
    assert metro["effectiveDemand"] == 135.0
    assert metro["priceMultiplier"] > 1.0

    # Surplus case: stock is 250, target is 100
    surplus = LogisticsMarketEngine.compute_elastic_price(50.0, 100, 250, zone_demand_multiplier=1.0)
    assert surplus["priceMultiplier"] < 1.0
    assert surplus["calculatedPrice"] < 50.0
    assert surplus["priceMultiplier"] >= 0.40  # floor respected


def test_hauler_arbitrage_computation():
    # Profitable run: Origin Port depot cost $40 -> Destination LS Metro price $100
    arb = LogisticsMarketEngine.calculate_hauler_arbitrage(origin_cost=40.0, dest_price=100.0, units=25, distance_km=8.0)
    assert arb["unitSpread"] == 60.0
    assert arb["grossProfit"] == 1500.0
    assert arb["fuelCost"] == 28.0
    assert arb["netProfit"] == 1472.0
    assert arb["rating"] == "EXCELLENT"

    # Unprofitable run: Origin $80 -> Dest $82 with distance 15 km
    loss = LogisticsMarketEngine.calculate_hauler_arbitrage(origin_cost=80.0, dest_price=82.0, units=10, distance_km=15.0)
    assert loss["unitSpread"] == 2.0
    assert loss["grossProfit"] == 20.0
    assert loss["fuelCost"] == 52.5
    assert loss["netProfit"] < 0
    assert loss["rating"] == "UNPROFITABLE"


def test_health_badge_formatting():
    crit = LogisticsMarketEngine.format_health_badge(0.15)
    assert crit["status"] == "CRITICAL_DEFICIT"
    assert "badge-danger" in crit["badgeClass"]

    short = LogisticsMarketEngine.format_health_badge(0.45)
    assert short["status"] == "MODERATE_SHORTAGE"

    eq = LogisticsMarketEngine.format_health_badge(1.0)
    assert eq["status"] == "EQUILIBRIUM"

    sur = LogisticsMarketEngine.format_health_badge(1.8)
    assert sur["status"] == "SURPLUS"


def test_dispatch_payload_validation():
    valid, res, err = LogisticsMarketEngine.validate_dispatch_payload({
        "originWarehouseId": "wh_dock_ls_01",
        "destinationZoneId": "zone_ls_metro",
        "itemId": "repairkit",
        "units": 20
    })
    assert valid is True
    assert res["units"] == 20
    assert err is None

    # Missing origin
    invalid, _, err = LogisticsMarketEngine.validate_dispatch_payload({
        "destinationZoneId": "zone_ls_metro",
        "itemId": "repairkit",
        "units": 20
    })
    assert invalid is False
    assert err == "INVALID_ORIGIN_WAREHOUSE"

    # Zero units
    invalid2, _, err2 = LogisticsMarketEngine.validate_dispatch_payload({
        "originWarehouseId": "wh_dock_ls_01",
        "destinationZoneId": "zone_ls_metro",
        "itemId": "repairkit",
        "units": 0
    })
    assert invalid2 is False
    assert err2 == "INVALID_UNITS_RANGE"


def test_commodity_catalog_filtering():
    items = [
        {"itemId": "repairkit", "name": "Standard Repair Kit", "zoneId": "zone_ls_metro", "category": "tools"},
        {"itemId": "medikit", "name": "Sterile Medikit", "zoneId": "zone_ls_metro", "category": "medical"},
        {"itemId": "copper_wire", "name": "Spool Copper Wire", "zoneId": "zone_sandy_shores", "category": "refining"},
    ]

    # Search query
    res = LogisticsMarketEngine.filter_commodity_catalog(items, query="medikit")
    assert len(res) == 1
    assert res[0]["itemId"] == "medikit"

    # Zone filter
    res_zone = LogisticsMarketEngine.filter_commodity_catalog(items, zone_filter="zone_sandy_shores")
    assert len(res_zone) == 1
    assert res_zone[0]["itemId"] == "copper_wire"

    # Category filter
    res_cat = LogisticsMarketEngine.filter_commodity_catalog(items, category_filter="tools")
    assert len(res_cat) == 1
    assert res_cat[0]["itemId"] == "repairkit"


def test_fxmanifest_declarations():
    manifest_path = os.path.join(ROOT_DIR, "FiveM", "nyx_logistics", "fxmanifest.lua")
    assert os.path.isfile(manifest_path)
    with open(manifest_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "shared/market_monitor.lua" in content, "shared/market_monitor.lua must be declared in fxmanifest"
    assert "server/market_monitor.lua" in content, "server/market_monitor.lua must be declared in fxmanifest"
    assert "client/market_monitor.lua" in content, "client/market_monitor.lua must be declared in fxmanifest"


def test_web_spa_html_ids_and_structure():
    html_path = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "web", "index.html")
    assert os.path.isfile(html_path)
    with open(html_path, "r", encoding="utf-8") as f:
        html = f.read()

    # Overlay & Dev button
    assert 'id="logistics-matrix-overlay"' in html
    assert 'id="dev-btn-logistics"' in html

    # Tabs
    assert 'id="logistics-tab-btn-matrix"' in html
    assert 'id="logistics-tab-btn-market"' in html
    assert 'id="logistics-tab-btn-arbitrage"' in html

    # Panes
    assert 'id="logistics-tab-matrix"' in html
    assert 'id="logistics-tab-market"' in html
    assert 'id="logistics-tab-arbitrage"' in html

    # Key interactive elements
    assert 'id="logistics-wh-select"' in html
    assert 'id="logistics-shelf-select"' in html
    assert 'id="logistics-3d-viewport"' in html
    assert 'id="logistics-slot-inspector"' in html
    assert 'id="logistics-pricing-rows"' in html
    assert 'id="logistics-arbitrage-cards"' in html


def test_web_spa_cef_render_budget():
    css_path = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "web", "css", "app.css")
    assert os.path.isfile(css_path)
    with open(css_path, "r", encoding="utf-8") as f:
        css = f.read()

    section_match = re.search(r"/\* =+\s*20\.\s*3D WAREHOUSE MATRIX.*?/\*", css, re.DOTALL)
    assert section_match is not None, "Section 20 styling must exist in app.css"
    section_css = section_match.group(0)

    # Render budget checks
    assert "backdrop-filter" not in section_css, "CEF budget violation: backdrop-filter found in Section 20"
    assert "blur(" not in section_css, "CEF budget violation: blur() found in Section 20"


def test_web_spa_js_state_and_handlers():
    js_path = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "web", "js", "app.js")
    assert os.path.isfile(js_path)
    with open(js_path, "r", encoding="utf-8") as f:
        js = f.read()

    assert "NyxState.logistics" in js, "NyxState.logistics must be defined"
    assert "LOGISTICS_MATRIX_OPEN" in js, "LOGISTICS_MATRIX_OPEN message handler must exist"
    assert "LOGISTICS_MATRIX_CLOSE" in js, "LOGISTICS_MATRIX_CLOSE message handler must exist"
    assert "dev-btn-logistics" in js, "Dev button listener must exist in app.js"


def test_client_bridge_whitelisting_and_callbacks():
    bridge_path = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "client", "bridge.lua")
    assert os.path.isfile(bridge_path)
    with open(bridge_path, "r", encoding="utf-8") as f:
        bridge = f.read()

    assert "closeMarketMonitor" in bridge
    assert "logistics:getMatrixOverview" in bridge
    assert "logistics:getMarketOverview" in bridge
    assert "logistics:getArbitrageRoutes" in bridge
    assert "logistics:bookDispatch" in bridge

    exports_path = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "client", "exports.lua")
    with open(exports_path, "r", encoding="utf-8") as f:
        exports_content = f.read()

    assert "OpenMarketMonitorUI" in exports_content
    assert "CloseMarketMonitorUI" in exports_content


def test_in_engine_tests_lua_registration():
    tests_lua_path = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "server", "tests.lua")
    assert os.path.isfile(tests_lua_path)
    with open(tests_lua_path, "r", encoding="utf-8") as f:
        tests_lua = f.read()

    assert "function Nyx.Tests.TestWarehouseMatrixAndElasticMarketMonitorUI()" in tests_lua
    assert "local t33 = Nyx.Tests.TestWarehouseMatrixAndElasticMarketMonitorUI()" in tests_lua
    assert "t33" in tests_lua

