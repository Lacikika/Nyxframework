import os
import re
import pytest

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIVEM_DIR = os.path.join(ROOT_DIR, "FiveM")
NYX_UI_DIR = os.path.join(FIVEM_DIR, "nyx_ui")

def test_css_cef_budget_and_wcag_tokens():
    css_path = os.path.join(NYX_UI_DIR, "web", "css", "app.css")
    assert os.path.isfile(css_path), "app.css must exist"

    with open(css_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Root CEF Render Budget Enforcement
    assert "background: transparent !important" in content
    assert "overflow: hidden !important" in content
    assert "user-select: none !important" in content
    assert "-webkit-user-drag: none !important" in content

    # 2. Strict Prohibition of backdrop-filter and blur shaders
    assert "backdrop-filter" not in content, "Strict CEF render budget prohibits backdrop-filter: blur()"
    assert "blur(" not in content, "No blur shader filters allowed in app.css"

    # 3. High-Opacity Dark Surfaces & Subtle 1px borders
    assert "rgba(12, 15, 22, 0.94)" in content or "--color-bg-base" in content
    assert "rgba(255, 255, 255, 0.08)" in content or "--color-border-subtle" in content

    # 4. WCAG AA+ Color Tokens
    assert "#F8FAFC" in content, "Primary text token #F8FAFC must be defined"
    assert "#94A3B8" in content, "Secondary text token #94A3B8 must be defined"
    assert "#475569" in content, "Muted text token #475569 must be defined"

    # 5. Keyframe Animation Restraints: strictly transform and opacity, no box-shadow animations
    keyframe_blocks = re.findall(r'@keyframes\s+([^{]+)\{([^}]+)\}', content)
    for name, body in keyframe_blocks:
        assert "box-shadow" not in body, f"Keyframe '{name.strip()}' animates box-shadow which causes CEF repaints"
        # Must only animate transform and/or opacity
        properties = re.findall(r'([a-zA-Z\-]+)\s*:', body)
        for prop in properties:
            assert prop in ("transform", "opacity", "from", "to"), f"Keyframe '{name.strip()}' uses disallowed property '{prop}'"

    # 6. Sizing and Ergonomics
    assert "min-height: 40px" in content or "min-height: 38px" in content or "min-height: 42px" in content
    assert "max-height: 85vh" in content

def test_js_dynamic_endpoints_and_dev_mode():
    js_path = os.path.join(NYX_UI_DIR, "web", "js", "app.js")
    assert os.path.isfile(js_path), "app.js must exist"

    with open(js_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Dynamic Endpoint Resolution
    assert "window.GetParentResourceName" in content
    assert "'nui-dev'" in content

    # 2. Desktop Browser Dev Mode Mocking
    assert "isBrowserDev" in content
    assert "handleDevMockNui" in content
    assert "initBrowserDevMode" in content

    # 3. Zero-Trust Button Pending State
    assert "lockButtonAction" in content
    assert "is-pending" in content
    assert "dataset.pending" in content

    # 4. Failsafe Keyboard Navigation
    assert "isEditableElement" in content
    assert "'Backspace'" in content
    assert "'Escape'" in content

    # 5. Modal Hierarchy Closing Order (submodals first, then main overlays)
    assert "inspect-popover" in content
    assert "dialog-overlay" in content
    assert "closeInventory" in content
    assert "closeMdt" in content
    assert "closeTreasuryDashboard" in content

    # 6. Auto-Focused Search Inputs
    assert "mdt-citizen-search-input" in content
    assert "focus()" in content

def test_lua_bridge_and_lifecycle_failsafes():
    bridge_path = os.path.join(NYX_UI_DIR, "client", "bridge.lua")
    main_path = os.path.join(NYX_UI_DIR, "client", "main.lua")
    hud_path = os.path.join(NYX_UI_DIR, "client", "hud.lua")
    config_path = os.path.join(NYX_UI_DIR, "config.lua")

    for p in (bridge_path, main_path, hud_path, config_path):
        assert os.path.isfile(p), f"{p} must exist"

    with open(bridge_path, "r", encoding="utf-8") as f:
        bridge_content = f.read()
    with open(main_path, "r", encoding="utf-8") as f:
        main_content = f.read()
    with open(hud_path, "r", encoding="utf-8") as f:
        hud_content = f.read()
    with open(config_path, "r", encoding="utf-8") as f:
        cfg_content = f.read()

    # 1. Safe NUI Callback Runner with guaranteed resolution
    assert "Nyx.UI.SafeNUICallback" in bridge_content
    assert "pcall" in bridge_content
    assert "safeCb" in bridge_content

    # 2. Zero-Trust Payload Sanitization
    assert "Nyx.UI.SanitizePayload" in bridge_content
    assert "itemId" in bridge_content
    assert "slot" in bridge_content

    # 3. Lifecycle Failsafe on Resource Stop
    assert 'AddEventHandler("onResourceStop"' in main_content
    assert "SetNuiFocus(false, false)" in main_content
    assert "SetNuiFocusKeepInput(false)" in main_content

    # 4. HUD Delta-Checking & Throttling (100ms-250ms)
    assert "HasHudDelta" in hud_content or "AreVitalsEqual" in hud_content
    assert "math.max(100, math.min(250" in hud_content
    assert not re.search(r'\bWait\s*\(\s*0\s*\)', hud_content), "Wait(0) busy-loop calls are strictly prohibited in HUD updates"

    # 5. Config HUD polling interval within 100ms-250ms
    m = re.search(r'UpdateIntervalMs\s*=\s*(\d+)', cfg_content)
    assert m, "UpdateIntervalMs must be configured"
    interval = int(m.group(1))
    assert 100 <= interval <= 250, f"Config HUD interval {interval}ms outside 100ms-250ms budget"
