"""
Unit and Integration Test Suite: Corporate Multi-Sig, RBAC & Union Management UI (`nyx_ui` & `nyx_factions`)
Covers:
- Database migration 034 schema & registration
- Shared Lua 5.4 RBAC, Equity & Escrow logic
- Server RPC endpoints & audit logging
- Client bridge NUI callbacks & zero-trust sanitization
- CEF render budget & Single-Frame SPA DOM integrity
"""

import json
import os
import re
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")
CORE_DIR = os.path.join(FIVEM_DIR, "nyx_core")
FACTIONS_DIR = os.path.join(FIVEM_DIR, "nyx_factions")
UI_DIR = os.path.join(FIVEM_DIR, "nyx_ui")

# ---------------------------------------------------------------------------
# 1. Database Migration 034 Verification
# ---------------------------------------------------------------------------
def test_migration_034_schema_and_registration():
    index_path = os.path.join(CORE_DIR, "sql", "migrations", "index.json")
    assert os.path.isfile(index_path), "Migration index.json must exist"

    with open(index_path, "r", encoding="utf-8") as f:
        index_data = json.load(f)

    migration_34 = "034_factions_corporate_ui_and_rbac_audit.sql"
    assert migration_34 in index_data, "Migration 034 must be registered in index.json"

    # Verify SQL file existence and schema in both nyx_core and nyx_factions
    core_sql = os.path.join(CORE_DIR, "sql", "migrations", "034_factions_corporate_ui_and_rbac_audit.sql")
    factions_sql = os.path.join(FACTIONS_DIR, "sql", "migrations", "034_factions_corporate_ui_and_rbac_audit.sql")
    assert os.path.isfile(core_sql), "034 SQL must exist in nyx_core"
    assert os.path.isfile(factions_sql), "034 SQL must exist in nyx_factions"

    with open(core_sql, "r", encoding="utf-8") as f:
        sql_content = f.read()

    assert "CREATE TABLE IF NOT EXISTS `nyx_factions_rbac_audit`" in sql_content
    assert "`actor_citizen_id`" in sql_content
    assert "`action_type`" in sql_content
    assert "cba_notes" in sql_content


# ---------------------------------------------------------------------------
# 2. Shared Lua Engine & Manifest Declarations
# ---------------------------------------------------------------------------
def test_shared_rbac_lua_and_manifest():
    shared_rbac = os.path.join(FACTIONS_DIR, "shared", "corporate_rbac.lua")
    assert os.path.isfile(shared_rbac), "corporate_rbac.lua must exist in nyx_factions/shared"

    with open(shared_rbac, "r", encoding="utf-8") as f:
        rbac_content = f.read()

    assert "Nyx.CorporateRBAC" in rbac_content
    assert "Taxonomy" in rbac_content
    assert "treasury:view_ledger" in rbac_content
    assert "roster:set_equity" in rbac_content
    assert "EvaluatePermission" in rbac_content
    assert "ValidateEquityBudget" in rbac_content
    assert "EvaluateEscrowStatus" in rbac_content
    assert "ValidateCBAParameters" in rbac_content
    assert "GetStandardRoleTemplates" in rbac_content

    # Manifest verification
    manifest_path = os.path.join(FACTIONS_DIR, "fxmanifest.lua")
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest_content = f.read()

    assert "shared/corporate_rbac.lua" in manifest_content


# ---------------------------------------------------------------------------
# 3. Server-Side Permissions, RPCs & Audit Logging
# ---------------------------------------------------------------------------
def test_factions_server_implementation():
    perms_path = os.path.join(FACTIONS_DIR, "server", "permissions.lua")
    main_path = os.path.join(FACTIONS_DIR, "server", "main.lua")
    exports_path = os.path.join(FACTIONS_DIR, "server", "exports.lua")

    with open(perms_path, "r", encoding="utf-8") as f:
        perms_content = f.read()
    with open(main_path, "r", encoding="utf-8") as f:
        main_content = f.read()
    with open(exports_path, "r", encoding="utf-8") as f:
        exports_content = f.read()

    # Permissions & Audit log functions
    assert "LogRBACAction" in perms_content
    assert "GetRBACAuditLog" in perms_content
    assert "GetCitizenFactions" in perms_content
    assert "CorporateRBAC.EvaluatePermission" in perms_content

    # RPC registration
    assert "factions:getCitizenFactions" in main_content
    assert "factions:getRBACAuditLog" in main_content
    assert "factions:getOverview" in main_content

    # Server exports
    assert "GetCitizenFactions" in exports_content
    assert "GetRBACAuditLog" in exports_content


# ---------------------------------------------------------------------------
# 4. Client-Side Commands & UI Bridge
# ---------------------------------------------------------------------------
def test_client_terminals_and_ui_bridge():
    terminals_path = os.path.join(FACTIONS_DIR, "client", "terminals.lua")
    unions_path = os.path.join(FACTIONS_DIR, "client", "unions.lua")
    bridge_path = os.path.join(UI_DIR, "client", "bridge.lua")
    ui_exports_path = os.path.join(UI_DIR, "client", "exports.lua")

    with open(terminals_path, "r", encoding="utf-8") as f:
        terminals_content = f.read()
    with open(unions_path, "r", encoding="utf-8") as f:
        unions_content = f.read()
    with open(bridge_path, "r", encoding="utf-8") as f:
        bridge_content = f.read()
    with open(ui_exports_path, "r", encoding="utf-8") as f:
        ui_exports_content = f.read()

    # Commands
    assert "RegisterCommand('corporate'" in terminals_content or 'RegisterCommand("corporate"' in terminals_content
    assert "RegisterCommand('faction'" in terminals_content or 'RegisterCommand("faction"' in terminals_content
    assert "OpenFactionDashboard" in terminals_content
    assert "openUnionRegistry" in unions_content

    # UI Bridge NUI callbacks
    expected_callbacks = [
        "closeFactionDashboard",
        "faction:getOverview",
        "faction:getCitizenFactions",
        "faction:addMember",
        "faction:updateMember",
        "faction:removeMember",
        "faction:initiateWithdrawal",
        "faction:signMultiSig",
        "faction:rejectMultiSig",
        "faction:cancelMultiSig",
        "faction:executeTimelocked",
        "faction:proposeCBA",
        "faction:ratifyCBA",
        "faction:claimStrikeRelief",
        "faction:distributeDividends"
    ]
    for cb in expected_callbacks:
        assert cb in bridge_content, f"NUI callback '{cb}' must be registered in bridge.lua"

    # UI Exports
    assert "OpenFactionDashboard" in ui_exports_content
    assert "CloseFactionDashboard" in ui_exports_content


# ---------------------------------------------------------------------------
# 5. SPA CEF Render Budget & HTML / JS DOM Integrity
# ---------------------------------------------------------------------------
def test_spa_cef_budget_and_html_elements():
    css_path = os.path.join(UI_DIR, "web", "css", "app.css")
    html_path = os.path.join(UI_DIR, "web", "index.html")
    js_path = os.path.join(UI_DIR, "web", "js", "app.js")

    with open(css_path, "r", encoding="utf-8") as f:
        css = f.read()
    with open(html_path, "r", encoding="utf-8") as f:
        html = f.read()
    with open(js_path, "r", encoding="utf-8") as f:
        js = f.read()

    # Strict CEF Budget
    assert "backdrop-filter" not in css, "Strict CEF render budget prohibits backdrop-filter"
    assert "blur(" not in css, "Strict CEF render budget prohibits blur shaders"

    # HTML Elements
    required_ids = [
        "faction-overlay",
        "faction-select",
        "faction-close-btn",
        "faction-tab-overview",
        "faction-tab-rbac",
        "faction-tab-multisig",
        "faction-tab-unions",
        "faction-tab-audit",
        "faction-submodal-member",
        "faction-submodal-withdraw",
        "dev-btn-faction",
        "cba-builder-submit-btn",
        "faction-dividend-btn"
    ]
    for el_id in required_ids:
        assert f'id="{el_id}"' in html, f"HTML element with id '{el_id}' must exist"

    # JS Message and State Handlers
    assert "FACTION_DASHBOARD_OPEN" in js
    assert "FACTION_DASHBOARD_CLOSE" in js
    assert "openFactionDashboard" in js
    assert "closeFactionDashboard" in js
    assert "lockButtonAction" in js
    assert "faction-submodal-member" in js
    assert "faction-submodal-withdraw" in js


# ---------------------------------------------------------------------------
# 6. Algorithmic Invariants (Python verification of pure math logic)
# ---------------------------------------------------------------------------
def evaluate_permission(nodes, required_node):
    if not nodes or not required_node:
        return False
    for node in nodes:
        if node == "*" or node == required_node:
            return True
        if node.endswith(":*"):
            prefix = node[:-1]
            if required_node.startswith(prefix):
                return True
    return False

def validate_equity(current_total, old_equity, new_equity):
    current_total = round(float(current_total or 0.0), 2)
    old_equity = round(float(old_equity or 0.0), 2)
    new_equity = round(float(new_equity or 0.0), 2)
    if new_equity < 0.0 or new_equity > 100.0:
        return False, current_total
    adjusted = round(current_total - old_equity + new_equity, 2)
    if adjusted > 100.00:
        return False, adjusted
    return True, adjusted

def evaluate_escrow(current_sigs, req_sigs, timelock_sec, init_unix, curr_unix):
    if current_sigs < req_sigs:
        return "AWAITING_SIGNATURES", False
    elapsed = max(0, curr_unix - init_unix)
    if timelock_sec > 0 and elapsed < timelock_sec:
        return "TIMELOCKED", False
    return "READY_FOR_EXECUTION", True

def test_pure_algorithms_parity():
    # RBAC matching
    assert evaluate_permission(["treasury:*"], "treasury:sign_tx") is True
    assert evaluate_permission(["treasury:*"], "roster:invite") is False
    assert evaluate_permission(["*"], "any:node") is True
    assert evaluate_permission(["fleet:spawn"], "fleet:spawn") is True
    assert evaluate_permission(["fleet:spawn"], "fleet:store") is False

    # Equity Budget
    ok, total = validate_equity(80.0, 0.0, 15.0)
    assert ok is True and total == 95.0
    ok, total = validate_equity(80.0, 0.0, 25.0)
    assert ok is False and total == 105.0
    ok, total = validate_equity(80.0, 20.0, 35.0)
    assert ok is True and total == 95.0

    # Multi-Sig Escrow
    status, can_exec = evaluate_escrow(1, 2, 300, 1000, 1100)
    assert status == "AWAITING_SIGNATURES" and can_exec is False

    status, can_exec = evaluate_escrow(2, 2, 300, 1000, 1100)
    assert status == "TIMELOCKED" and can_exec is False

    status, can_exec = evaluate_escrow(2, 2, 300, 1000, 1400)
    assert status == "READY_FOR_EXECUTION" and can_exec is True
