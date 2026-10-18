"""
Unit tests for Hotfix: Resolve Nil RPC Reference in Inactivity Handlers (nyx_factions & nyx_properties).
Validates that inactivity handlers do not call uninitialized Nyx.RPC directly,
that exports['nyx_core']:RegisterRPC is used or kernel RPC table is safely hydrated,
and that player references (GetPlayer, GetPlayerByCitizenId) are safely resolved.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIVEM = ROOT / "FiveM"


def test_factions_inactivity_no_uninitialized_nyx_rpc_calls():
    """Verify nyx_factions/server/inactivity.lua does not directly index uninitialized Nyx.RPC."""
    factions_inact = (FIVEM / "nyx_factions" / "server" / "inactivity.lua").read_text(encoding="utf-8")

    # Should not have raw unhydrated/unguarded `Nyx.RPC.Register(` calls
    # Either exports['nyx_core']:RegisterRPC is used, or Nyx.RPC is explicitly hydrated with fallback
    raw_calls = re.findall(r"(?<!if\s)(?<!and\s)Nyx\.RPC\.Register\s*\(", factions_inact)
    assert len(raw_calls) == 0, (
        f"Found {len(raw_calls)} raw Nyx.RPC.Register call(s) in nyx_factions/server/inactivity.lua. "
        "Must use exports['nyx_core']:RegisterRPC or ensure Nyx.RPC is hydrated."
    )


def test_properties_inactivity_no_uninitialized_nyx_rpc_calls():
    """Verify nyx_properties/server/inactivity.lua does not directly index uninitialized Nyx.RPC."""
    props_inact = (FIVEM / "nyx_properties" / "server" / "inactivity.lua").read_text(encoding="utf-8")

    raw_calls = re.findall(r"(?<!if\s)(?<!and\s)Nyx\.RPC\.Register\s*\(", props_inact)
    assert len(raw_calls) == 0, (
        f"Found {len(raw_calls)} raw Nyx.RPC.Register call(s) in nyx_properties/server/inactivity.lua. "
        "Must use exports['nyx_core']:RegisterRPC or ensure Nyx.RPC is hydrated."
    )


def test_properties_inactivity_safe_player_lookups():
    """Verify nyx_properties/server/inactivity.lua uses exports['nyx_core'] for player lookups."""
    props_inact = (FIVEM / "nyx_properties" / "server" / "inactivity.lua").read_text(encoding="utf-8")

    # In nyx_properties, Nyx.GetPlayer is not a built-in global; exports['nyx_core']:GetPlayer must be used
    raw_get_player = re.findall(r"(?<!exports\['nyx_core'\]:)Nyx\.GetPlayer\s*\(", props_inact)
    assert len(raw_get_player) == 0, (
        f"Found {len(raw_get_player)} uninitialized Nyx.GetPlayer call(s) in nyx_properties/server/inactivity.lua. "
        "Must use exports['nyx_core']:GetPlayer."
    )

    raw_get_cit = re.findall(r"(?<!exports\['nyx_core'\]:)Nyx\.GetPlayerByCitizenId\s*\(", props_inact)
    assert len(raw_get_cit) == 0, (
        f"Found {len(raw_get_cit)} uninitialized Nyx.GetPlayerByCitizenId call(s) in nyx_properties/server/inactivity.lua. "
        "Must use exports['nyx_core']:GetPlayerByCitizenId."
    )


def test_factions_kernel_table_hydration():
    """Verify nyx_factions safely bridges or hydrates Nyx.RPC and Nyx.GetPlayer before handlers bind."""
    factions_inact = (FIVEM / "nyx_factions" / "server" / "inactivity.lua").read_text(encoding="utf-8")
    factions_perm = (FIVEM / "nyx_factions" / "server" / "permissions.lua").read_text(encoding="utf-8")

    # Either permissions.lua (first server script) or inactivity.lua must hydrate Nyx.RPC and Nyx.GetPlayer
    combined = factions_perm + "\n" + factions_inact
    assert "exports['nyx_core']:RegisterRPC" in combined or "Nyx.RPC =" in combined
    assert "exports['nyx_core']:GetPlayer" in combined or "Nyx.GetPlayer =" in combined


def test_all_expected_inactivity_rpc_endpoints_present():
    """Verify all 7 inactivity and stewardship RPC routes are declared across both resources."""
    factions_inact = (FIVEM / "nyx_factions" / "server" / "inactivity.lua").read_text(encoding="utf-8")
    props_inact = (FIVEM / "nyx_properties" / "server" / "inactivity.lua").read_text(encoding="utf-8")

    expected_factions_routes = [
        "factions:setFactionStewardDelegate",
        "factions:getFactionInactivityStatus",
    ]
    for route in expected_factions_routes:
        assert route in factions_inact, f"Missing route {route} in nyx_factions/server/inactivity.lua"

    expected_props_routes = [
        "properties:registerStewardDelegate",
        "properties:revokeStewardDelegate",
        "properties:assignPropertySteward",
        "properties:getMyStewardship",
        "properties:getInactivityAuditLogs",
    ]
    for route in expected_props_routes:
        assert route in props_inact, f"Missing route {route} in nyx_properties/server/inactivity.lua"
