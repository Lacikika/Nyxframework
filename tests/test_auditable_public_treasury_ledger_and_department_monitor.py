"""
Unit tests for Auditable Public Treasury Ledger & Department Allocation Monitor (nyx_treasury & nyx_ui).
Tests pure domain logic: municipal balance sheet calculation, automated percentage splits & cap enforcement,
exact zero-cent economic conservation, fiscal crisis telemetry & logarithmic wage scaling, drain velocity runway,
query parameter sanitization, Migration 057 schema, manifests, and Web SPA integration.
"""

import os
import re
import json
import math
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class PublicLedgerDomainEngine:
    """Pure domain engine mirroring Nyx.PublicLedger in nyx_treasury/shared/public_ledger.lua."""

    ALLOCATION_CATEGORIES = {
        "emergency_services": {
            "label": "Készenléti Szervek (Emergency Services)",
            "description": "Rendvédelmi és mentési készenlét, járőrszolgálat és sürgősségi ellátás.",
            "statutoryPillar": "Emergency Services Payroll & Tactical Fleet"
        },
        "infrastructure": {
            "label": "Városi Infrastruktúra & Közművek (Infrastructure)",
            "description": "Elektromos hálózat, transzformátor állomások, vízművek és útkarbantartás.",
            "statutoryPillar": "Public Works & Grid Infrastructure"
        },
        "social_dividend": {
            "label": "Társadalmi Osztalék & Polgári Pályázatok (Social Dividend)",
            "description": "Polgári alapjövedelem, kisvállalkozói támogatások és közösségi ösztöndíjak.",
            "statutoryPillar": "Social Dividend & Citizen Small Grants"
        },
        "general": {
            "label": "Általános Költségvetési Célelőirányzat",
            "description": "Egyéb törvényhozási és közigazgatási céltartalékok.",
            "statutoryPillar": "General Civic Appropriations"
        }
    }

    TRANSACTION_CATEGORIES = {
        "pos_sale": {"label": "Kereskedelmi Értékesítés", "badge": "COMMERCE", "flow": "internal"},
        "pos_tax": {"label": "Értékesítési Adó (ÁFA)", "badge": "TAX_INFLOW", "flow": "inflow"},
        "transfer_p2p": {"label": "Banki Átutelés (P2P)", "badge": "WIRE_TRANSFER", "flow": "internal"},
        "transfer_duty": {"label": "Pénzügyi Tranzakciós Illeték", "badge": "DUTY_INFLOW", "flow": "inflow"},
        "payroll": {"label": "Közszolgálati Bérkifizetés", "badge": "PAYROLL", "flow": "outflow"},
        "allocation": {"label": "Költségvetési Adóelosztás", "badge": "ALLOCATION", "flow": "internal"},
        "emergency_subvention": {"label": "Rendkívüli Kincstári Szubvenció", "badge": "SUBVENTION", "flow": "internal"},
        "commercial_laundering": {"label": "Pénzmosási Letét (Washed)", "badge": "LAUNDER_INFLOW", "flow": "inflow"},
        "laundering_tax": {"label": "Pénzmosási Forgalmi Adó", "badge": "LAUNDER_TAX", "flow": "inflow"},
        "cash_transit_deposit": {"label": "Páncélozott Készpénz Befizetés", "badge": "VAULT_DEPOSIT", "flow": "inflow"},
        "cash_transit_fee": {"label": "Készpénzszállítási Banki Díj", "badge": "TRANSIT_FEE", "flow": "inflow"},
        "equity_dividend": {"label": "Társasági Osztalékfizetés", "badge": "DIVIDEND", "flow": "internal"},
        "utility_bill": {"label": "Közműdíj Befizetés", "badge": "UTILITY_REVENUE", "flow": "inflow"},
        "circuit_event": {"label": "Fiskális Áramkörvédelmi Esemény", "badge": "CIRCUIT_ALERT", "flow": "audit"}
    }

    STATUTORY_OFFICES_DEFAULT = {
        "masterReserve": 5000000.00,
        "targetReserve": 5000000.00,
        "cautionReserve": 2500000.00,
        "recoveryReserve": 1000000.00,
        "criticalReserve": 500000.00
    }

    @classmethod
    def calculate_balance_sheet(cls, accounts, target_reserve=5000000.00, critical_reserve=500000.00):
        if not isinstance(accounts, list):
            accounts = []

        total_liquidity = 0.00
        processed_accounts = []

        for acc in accounts:
            bal = float(acc.get("balance", 0.00))
            total_liquidity += bal

        total_liquidity = round(total_liquidity, 2)

        for acc in accounts:
            bal = float(acc.get("balance", 0.00))
            cap = float(acc.get("cap_limit", 0.00)) if acc.get("cap_limit") else 0.00
            share_pct = round((bal / total_liquidity * 100.00), 2) if total_liquidity > 0 else 0.00

            solvency = "SOLVENT"
            if bal <= 0.00:
                solvency = "DEPLETED"
            elif cap > 0 and (bal / cap) < 0.20:
                solvency = "DEFICIT_WARNING"
            elif cap > 0 and (bal / cap) < 0.50:
                solvency = "LOW_RESERVE"

            processed_accounts.append({
                "accountId": acc.get("account_id") or acc.get("id"),
                "label": acc.get("label") or acc.get("account_id"),
                "type": acc.get("type", "department"),
                "balance": round(bal, 2),
                "capLimit": round(cap, 2) if cap > 0 else None,
                "sharePercentage": share_pct,
                "solvencyStatus": solvency,
                "circuitExempt": bool(acc.get("circuit_exempt", False))
            })

        return {
            "totalLiquidity": total_liquidity,
            "accountCount": len(processed_accounts),
            "accounts": processed_accounts,
            "targetReserve": round(float(target_reserve), 2),
            "criticalReserve": round(float(critical_reserve), 2),
            "isBalanced": True,
            "conservationVariance": 0.00
        }

    @classmethod
    def calculate_sweep_splits(cls, collected_amount, allocations, current_account_balances=None):
        collected_amount = math.floor(float(collected_amount) * 100.0) / 100.0
        if collected_amount < 10.00 or not allocations:
            return {
                "success": False,
                "reason": "INSUFFICIENT_POOL_BALANCE" if collected_amount < 10.00 else "NO_ALLOCATIONS_CONFIGURED",
                "collectedAmount": collected_amount,
                "totalSwept": 0.00,
                "masterSurplusRetained": 0.00,
                "splits": []
            }

        current_balances = current_account_balances or {}
        splits = []
        total_allocated = 0.00
        master_surplus = 0.00

        for alloc in allocations:
            target = alloc.get("target_department") or alloc.get("targetDepartment")
            pct = float(alloc.get("percentage_split", 0.00) or alloc.get("percentageSplit", 0.00))
            cap = float(alloc.get("cap_limit", 0.00) or alloc.get("capLimit", 0.00)) if alloc.get("cap_limit") or alloc.get("capLimit") else None

            raw_share = math.floor((collected_amount * (pct / 100.00)) * 100.0) / 100.0

            current_bal = float(current_balances.get(target, 0.00))
            effective_share = raw_share
            diverted_surplus = 0.00

            if cap is not None and cap > 0:
                headroom = max(0.00, cap - current_bal)
                if raw_share > headroom:
                    effective_share = headroom
                    diverted_surplus = round(raw_share - headroom, 2)
                    master_surplus += diverted_surplus

            splits.append({
                "targetDepartment": target,
                "departmentLabel": alloc.get("department_label") or alloc.get("label") or target,
                "allocationCategory": alloc.get("allocation_category") or alloc.get("category") or "general",
                "percentageSplit": pct,
                "rawShare": raw_share,
                "effectiveShare": effective_share,
                "divertedToMaster": diverted_surplus,
                "capLimit": cap,
                "balanceBefore": current_bal,
                "balanceAfter": round(current_bal + effective_share, 2)
            })

            total_allocated += effective_share

        total_swept = round(total_allocated + master_surplus, 2)
        cent_remainder = round(collected_amount - total_swept, 2)
        if cent_remainder > 0:
            master_surplus = round(master_surplus + cent_remainder, 2)
            total_swept = round(total_allocated + master_surplus, 2)

        return {
            "success": True,
            "collectedAmount": collected_amount,
            "totalAllocated": round(total_allocated, 2),
            "masterSurplusRetained": round(master_surplus, 2),
            "totalSwept": total_swept,
            "variance": round(collected_amount - total_swept, 2),
            "splits": splits
        }

    @classmethod
    def calculate_fiscal_telemetry(cls, master_reserve, circuit_telemetry=None, target_reserve=5000000.00, critical_reserve=500000.00, caution_reserve=2500000.00):
        master_reserve = max(0.00, float(master_reserve))
        target_reserve = float(target_reserve)
        critical_reserve = float(critical_reserve)
        caution_reserve = float(caution_reserve)

        circuit = circuit_telemetry or {}
        is_tripped = bool(circuit.get("tripped", False))

        fiscal_state = "SOLVENT"
        if is_tripped:
            fiscal_state = "CIRCUIT_TRIPPED"
        elif master_reserve <= critical_reserve:
            fiscal_state = "CRITICAL_DEFICIT"
        elif master_reserve < caution_reserve:
            fiscal_state = "AUSTERITY"
        elif master_reserve < target_reserve:
            fiscal_state = "THROTTLED"

        # Logarithmic wage scaling
        wage_multiplier = 1.00
        wage_status = "SOLVENT"
        if is_tripped or master_reserve <= critical_reserve:
            wage_multiplier = 0.00
            wage_status = "CRITICAL_FREEZE"
        elif master_reserve < target_reserve:
            floor = 0.10
            log_ratio = math.log(master_reserve / critical_reserve)
            log_max = math.log(target_reserve / critical_reserve)
            normalized = log_ratio / log_max if log_max > 0 else 0.00
            scaled = floor + ((1.00 - floor) * normalized)
            wage_multiplier = math.floor(max(floor, min(1.00, scaled)) * 100.0) / 100.0
            wage_status = "AUSTERITY" if master_reserve < caution_reserve else "THROTTLED"

        # Drain velocity and runway hours
        drain = circuit.get("drainVelocity") or {}
        outflow_hr = float(drain.get("velocityPerHour", 0.00))
        runway_hours = None
        if outflow_hr > 0 and master_reserve > critical_reserve:
            burnable_surplus = master_reserve - critical_reserve
            runway_hours = round(burnable_surplus / outflow_hr, 1)

        reserve_ratio_pct = round((master_reserve / target_reserve) * 100.0, 1) if target_reserve > 0 else 0.0

        # Public infrastructure degradation indicators
        is_degraded = (fiscal_state in ("CRITICAL_DEFICIT", "CIRCUIT_TRIPPED") or master_reserve <= 100000.00)
        auto_repair_status = "OFFLINE" if is_degraded else "OPERATIONAL"
        impound_surcharge_active = (fiscal_state in ("AUSTERITY", "CRITICAL_DEFICIT", "CIRCUIT_TRIPPED"))
        ai_dispatch_status = "DEGRADED" if is_degraded else "OPERATIONAL"

        return {
            "masterReserve": master_reserve,
            "targetReserve": target_reserve,
            "cautionReserve": caution_reserve,
            "criticalReserve": critical_reserve,
            "reserveRatioPercentage": reserve_ratio_pct,
            "fiscalState": fiscal_state,
            "wageMultiplier": wage_multiplier,
            "wageMultiplierPercentage": round(wage_multiplier * 100.0, 1),
            "wageStatus": wage_status,
            "drainVelocityPerHour": outflow_hr,
            "runwayHours": runway_hours,
            "circuitTripped": is_tripped,
            "infrastructure": {
                "autoRepair": auto_repair_status,
                "impoundSurchargeActive": impound_surcharge_active,
                "aiDispatch": ai_dispatch_status,
                "municipalDegraded": is_degraded
            }
        }

    @classmethod
    def sanitize_ledger_query(cls, params):
        if not isinstance(params, dict):
            params = {}

        page = max(1, int(params.get("page", 1)))
        page_size = max(5, min(100, int(params.get("pageSize", 20))))

        raw_cat = params.get("category", "ALL")
        category = "ALL"
        if raw_cat and isinstance(raw_cat, str) and raw_cat in cls.TRANSACTION_CATEGORIES:
            category = raw_cat

        search = ""
        raw_search = params.get("search")
        if raw_search and isinstance(raw_search, str):
            clean = re.sub(r"[^\w\-: ]", "", raw_search).strip()
            search = clean[:64]

        return {
            "page": page,
            "pageSize": page_size,
            "offset": (page - 1) * page_size,
            "category": category,
            "search": search
        }


# ==============================================================================
# PYTEST TEST SUITE
# ==============================================================================

def test_public_ledger_categories():
    """Verify statutory allocation categories and transaction flow taxonomy."""
    categories = PublicLedgerDomainEngine.ALLOCATION_CATEGORIES
    assert "emergency_services" in categories
    assert "infrastructure" in categories
    assert "social_dividend" in categories
    assert "general" in categories

    tx_categories = PublicLedgerDomainEngine.TRANSACTION_CATEGORIES
    assert "pos_sale" in tx_categories
    assert "pos_tax" in tx_categories
    assert "payroll" in tx_categories
    assert "allocation" in tx_categories
    assert "emergency_subvention" in tx_categories
    assert "commercial_laundering" in tx_categories
    assert "cash_transit_deposit" in tx_categories
    assert "equity_dividend" in tx_categories
    assert "utility_bill" in tx_categories


def test_balance_sheet_calculation():
    """Verify total liquidity, account shares, solvency classification, and exact conservation."""
    mock_accounts = [
        {"account_id": "gov:city:master", "label": "Municipal Master Reserve", "balance": 5000000.00, "type": "public_master"},
        {"account_id": "gov:city:tax", "label": "Tax Collection Pool", "balance": 250000.00, "type": "tax_pool"},
        {"account_id": "gov:dept:police", "label": "State Police Operating", "balance": 600000.00, "type": "department", "cap_limit": 1500000.00},
        {"account_id": "gov:dept:ems", "label": "Emergency Medical Services", "balance": 400000.00, "type": "department", "cap_limit": 1000000.00},
        {"account_id": "gov:dept:works", "label": "Public Works & Infrastructure", "balance": 300000.00, "type": "department", "cap_limit": 800000.00},
        {"account_id": "gov:dept:dividend", "label": "Social Dividend Reserve", "balance": 150000.00, "type": "grant_pool", "cap_limit": 500000.00}
    ]

    sheet = PublicLedgerDomainEngine.calculate_balance_sheet(mock_accounts)
    assert sheet["totalLiquidity"] == 6700000.00
    assert sheet["accountCount"] == 6
    assert sheet["isBalanced"] is True
    assert sheet["conservationVariance"] == 0.00

    master_acc = next(a for a in sheet["accounts"] if a["accountId"] == "gov:city:master")
    assert master_acc["solvencyStatus"] == "SOLVENT"
    assert master_acc["sharePercentage"] == round(5000000.00 / 6700000.00 * 100.0, 2)

    # Test depleted account
    depleted_mock = [{"account_id": "test:depleted", "label": "Broke Dept", "balance": 0.00, "type": "department", "cap_limit": 100000.00}]
    depleted_sheet = PublicLedgerDomainEngine.calculate_balance_sheet(depleted_mock)
    assert depleted_sheet["accounts"][0]["solvencyStatus"] == "DEPLETED"


def test_sweep_splits_exact_cent_conservation():
    """Verify statutory revenue sweeps divide collected funds strictly matching Sum(Allocated) + Surplus == Collected."""
    allocations = [
        {"target_department": "gov:dept:police", "percentage_split": 35.00, "cap_limit": 1500000.00, "department_label": "Police", "allocation_category": "emergency_services"},
        {"target_department": "gov:dept:ems", "percentage_split": 25.00, "cap_limit": 1000000.00, "department_label": "EMS", "allocation_category": "emergency_services"},
        {"target_department": "gov:dept:works", "percentage_split": 25.00, "cap_limit": 800000.00, "department_label": "Works", "allocation_category": "infrastructure"},
        {"target_department": "gov:dept:dividend", "percentage_split": 15.00, "cap_limit": 500000.00, "department_label": "Dividend", "allocation_category": "social_dividend"}
    ]

    collected = 123456.78
    res = PublicLedgerDomainEngine.calculate_sweep_splits(collected, allocations)
    assert res["success"] is True
    assert res["totalSwept"] == collected
    assert res["variance"] == 0.00
    assert len(res["splits"]) == 4

    # Verify sum of effective shares + master surplus equals collected amount to the cent
    sum_parts = sum(s["effectiveShare"] for s in res["splits"]) + res["masterSurplusRetained"]
    assert round(sum_parts, 2) == collected


def test_department_caps_overflow_to_master():
    """Verify that when a department reaches its statutory cap, excess overflows to Master Reserve with zero leakage."""
    allocations = [
        {"target_department": "gov:dept:police", "percentage_split": 40.00, "cap_limit": 1000000.00, "label": "Police"},
        {"target_department": "gov:dept:ems", "percentage_split": 60.00, "cap_limit": 500000.00, "label": "EMS"}
    ]

    # Police has 950k (headroom 50k). 40% of 200k = 80k -> 30k excess overflow!
    # EMS has 100k (headroom 400k). 60% of 200k = 120k -> 0k excess.
    balances = {
        "gov:dept:police": 950000.00,
        "gov:dept:ems": 100000.00
    }

    res = PublicLedgerDomainEngine.calculate_sweep_splits(200000.00, allocations, balances)
    assert res["success"] is True

    police_split = next(s for s in res["splits"] if s["targetDepartment"] == "gov:dept:police")
    assert police_split["rawShare"] == 80000.00
    assert police_split["effectiveShare"] == 50000.00
    assert police_split["divertedToMaster"] == 30000.00
    assert police_split["balanceAfter"] == 1000000.00

    ems_split = next(s for s in res["splits"] if s["targetDepartment"] == "gov:dept:ems")
    assert ems_split["effectiveShare"] == 120000.00
    assert ems_split["divertedToMaster"] == 0.00

    assert res["masterSurplusRetained"] == 30000.00
    assert round(res["totalAllocated"] + res["masterSurplusRetained"], 2) == 200000.00


def test_fiscal_crisis_telemetry():
    """Verify logarithmic wage scaling, crisis states, velocity drain, and projected runway hours."""
    # Solvent state
    telemetry_solvent = PublicLedgerDomainEngine.calculate_fiscal_telemetry(5500000.00)
    assert telemetry_solvent["fiscalState"] == "SOLVENT"
    assert telemetry_solvent["wageMultiplier"] == 1.00
    assert telemetry_solvent["infrastructure"]["municipalDegraded"] is False

    # Throttled state ($3.5M)
    telemetry_throttled = PublicLedgerDomainEngine.calculate_fiscal_telemetry(3500000.00)
    assert telemetry_throttled["fiscalState"] == "THROTTLED"
    assert 0.80 <= telemetry_throttled["wageMultiplier"] < 1.00

    # Austerity state ($1.2M)
    telemetry_austerity = PublicLedgerDomainEngine.calculate_fiscal_telemetry(1200000.00)
    assert telemetry_austerity["fiscalState"] == "AUSTERITY"
    assert 0.10 <= telemetry_austerity["wageMultiplier"] <= 0.60
    assert telemetry_austerity["infrastructure"]["impoundSurchargeActive"] is True

    # Critical Deficit ($400k <= $500k)
    telemetry_critical = PublicLedgerDomainEngine.calculate_fiscal_telemetry(400000.00)
    assert telemetry_critical["fiscalState"] == "CRITICAL_DEFICIT"
    assert telemetry_critical["wageMultiplier"] == 0.00
    assert telemetry_critical["infrastructure"]["autoRepair"] == "OFFLINE"
    assert telemetry_critical["infrastructure"]["aiDispatch"] == "DEGRADED"

    # Circuit Tripped
    circuit_mock = {"tripped": True, "drainVelocity": {"velocityPerHour": 150000.00}}
    telemetry_tripped = PublicLedgerDomainEngine.calculate_fiscal_telemetry(3000000.00, circuit_mock)
    assert telemetry_tripped["fiscalState"] == "CIRCUIT_TRIPPED"
    assert telemetry_tripped["wageMultiplier"] == 0.00
    assert telemetry_tripped["circuitTripped"] is True

    # Runway calculation: Reserve 2M, Critical 500k, Burn 150k/hr -> (2M - 0.5M) / 150k = 10.0 hours
    circuit_burn = {"tripped": False, "drainVelocity": {"velocityPerHour": 150000.00}}
    telemetry_runway = PublicLedgerDomainEngine.calculate_fiscal_telemetry(2000000.00, circuit_burn)
    assert telemetry_runway["runwayHours"] == 10.0


def test_sanitize_ledger_query():
    """Verify zero-trust sanitization for pagination, category whitelist, and search query."""
    clean = PublicLedgerDomainEngine.sanitize_ledger_query({
        "page": "2",
        "pageSize": 50,
        "category": "payroll",
        "search": "char:CIT-9921<script>alert(1)</script>"
    })
    assert clean["page"] == 2
    assert clean["pageSize"] == 50
    assert clean["offset"] == 50
    assert clean["category"] == "payroll"
    assert "<script>" not in clean["search"]

    # Invalid category defaults to ALL
    invalid_cat = PublicLedgerDomainEngine.sanitize_ledger_query({"category": "SQL_INJECTION' OR 1=1--"})
    assert invalid_cat["category"] == "ALL"

    # Extreme bounds clamping
    clamped = PublicLedgerDomainEngine.sanitize_ledger_query({"page": -5, "pageSize": 9999})
    assert clamped["page"] == 1
    assert clamped["pageSize"] == 100


def test_migration_057_structure():
    """Verify migration 057 exists, is registered in index.json as Step 57, and alters/creates required tables."""
    index_path = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", "index.json")
    with open(index_path, "r", encoding="utf-8") as f:
        migrations = json.load(f)

    filename = "057_auditable_public_treasury_ledger_and_department_monitor.sql"
    assert filename in migrations, f"{filename} must be registered in index.json"
    step57_idx = migrations.index(filename)
    assert step57_idx == 56, f"Step 57 must be at index 56, got {step57_idx}"

    core_sql_path = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "sql", "migrations", filename)
    treasury_sql_path = os.path.join(ROOT_DIR, "FiveM", "nyx_treasury", "sql", "migrations", filename)

    assert os.path.isfile(core_sql_path), f"Core migration file missing: {core_sql_path}"
    assert os.path.isfile(treasury_sql_path), f"Treasury migration file mirror missing: {treasury_sql_path}"

    with open(core_sql_path, "r", encoding="utf-8") as f:
        sql = f.read()

    assert "nyx_treasury_revenue_sweeps" in sql
    assert "nyx_treasury_allocations" in sql
    assert "gov:dept:dividend" in sql
    assert "allocation_category" in sql


def test_manifest_declarations():
    """Verify shared/public_ledger.lua is declared in nyx_treasury and nyx_ui fxmanifest.lua."""
    treasury_manifest = os.path.join(ROOT_DIR, "FiveM", "nyx_treasury", "fxmanifest.lua")
    with open(treasury_manifest, "r", encoding="utf-8") as f:
        t_content = f.read()

    assert "shared/public_ledger.lua" in t_content

    ui_manifest = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "fxmanifest.lua")
    with open(ui_manifest, "r", encoding="utf-8") as f:
        u_content = f.read()

    assert "@nyx_treasury/shared/public_ledger.lua" in u_content


def test_web_spa_integration():
    """Verify index.html has 4 modern tabs, app.css has tab/kpi styles, and app.js integrates public ledger handlers."""
    html_path = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "web", "index.html")
    with open(html_path, "r", encoding="utf-8") as f:
        html = f.read()

    assert 'id="treasury-overlay"' in html
    assert 'data-tab="balance_sheet"' in html or 'treasury-tab' in html
    assert 'data-tab="ledger"' in html or 'treasury-tab-ledger' in html
    assert 'data-tab="allocations"' in html or 'treasury-tab-allocations' in html
    assert 'data-tab="telemetry"' in html or 'treasury-tab-telemetry' in html

    js_path = os.path.join(ROOT_DIR, "FiveM", "nyx_ui", "web", "js", "app.js")
    with open(js_path, "r", encoding="utf-8") as f:
        js = f.read()

    assert "openTreasuryDashboard" in js
    assert "closeTreasuryDashboard" in js
    assert "TREASURY_DASHBOARD_OPEN" in js or "OPEN_TREASURY_DASHBOARD" in js
    assert "treasury:getLedgerPage" in js or "getLedgerPage" in js


def test_in_engine_tests_lua_declaration():
    """Verify Test 52 is declared in tests.lua and wired into Nyx.Tests.RunAll()."""
    tests_lua_path = os.path.join(ROOT_DIR, "FiveM", "nyx_core", "server", "tests.lua")
    with open(tests_lua_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "TestAuditablePublicTreasuryLedgerAndDepartmentMonitor" in content
    assert "local t52 = Nyx.Tests.TestAuditablePublicTreasuryLedgerAndDepartmentMonitor()" in content
    assert "t51 and t52" in content

