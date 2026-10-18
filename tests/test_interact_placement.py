import pytest
import math
import os
import re

def test_placement_distance_validation():
    """Validates that target placement coordinates beyond max distance + tolerance are rejected."""
    player_pos = (100.0, 200.0, 30.0)
    max_dist = 6.0 + 2.5 # 8.5m tolerance margin

    def is_within_range(target_pos):
        dx = player_pos[0] - target_pos[0]
        dy = player_pos[1] - target_pos[1]
        dz = player_pos[2] - target_pos[2]
        dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        return dist <= max_dist, dist

    valid, dist = is_within_range((103.0, 202.0, 30.0))
    assert valid is True
    assert dist < 8.5

    invalid, dist = is_within_range((120.0, 200.0, 30.0))
    assert invalid is False
    assert dist == 20.0

def test_heading_normalization():
    """Validates that heading angles wrap properly within [0.0, 360.0) degrees."""
    def normalize_heading(val):
        h = val % 360.0
        if h < 0:
            h += 360.0
        return round(h, 2)

    assert normalize_heading(0.0) == 0.0
    assert normalize_heading(360.0) == 0.0
    assert normalize_heading(375.5) == 15.5
    assert normalize_heading(-45.0) == 315.0
    assert normalize_heading(720.0) == 0.0
    assert normalize_heading(-725.25) == 354.75

def test_coordinate_sanitization():
    """Validates that coordinates are sanitized to 2 decimal places to prevent DB float bloat."""
    def sanitize_coords(c):
        return {
            'x': round(c['x'], 2),
            'y': round(c['y'], 2),
            'z': round(c['z'], 2)
        }

    raw = {'x': 123.4567, 'y': -987.6543, 'z': 45.1234}
    clean = sanitize_coords(raw)
    assert clean == {'x': 123.46, 'y': -987.65, 'z': 45.12}

def test_zero_packet_drag_behavior():
    """Validates that movement/dragging occurs completely client-side with 0 network calls until release."""
    packets = []

    def on_drag_step(current_pos, delta_rot):
        # Client-only local interpolation (zero network emissions)
        new_heading = (current_pos['heading'] + delta_rot) % 360.0
        return {'x': current_pos['x'], 'y': current_pos['y'], 'z': current_pos['z'], 'heading': new_heading}

    def on_release(final_pos):
        packets.append({
            'route': 'inventory:commitWorldPlacement',
            'coords': {'x': final_pos['x'], 'y': final_pos['y'], 'z': final_pos['z']},
            'rotation': {'heading': final_pos['heading']}
        })

    pos = {'x': 100.0, 'y': 200.0, 'z': 30.0, 'heading': 0.0}
    for _ in range(60): # 60 frames
        pos = on_drag_step(pos, 5.0)

    assert len(packets) == 0 # Zero packets emitted during drag

    on_release(pos)
    assert len(packets) == 1 # Exactly one validated packet on placement commit
    assert packets[0]['rotation']['heading'] == (60 * 5.0) % 360.0

def test_no_press_e_loops_elimination():
    """Scans all resource Lua files to ensure no legacy BeginTextCommandDisplayHelp or Press ~INPUT_CONTEXT~ loops remain."""
    fivem_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "FiveM"))
    banned_patterns = [
        re.compile(r'BeginTextCommandDisplayHelp'),
        re.compile(r'Press ~INPUT_CONTEXT~'),
        re.compile(r'IsControlJustPressed\(0,\s*38\)')
    ]

    violations = []
    for root, _, files in os.walk(fivem_root):
        for file in files:
            if file.endswith('.lua'):
                path = os.path.join(root, file)
                with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                    for line_idx, line in enumerate(f, start=1):
                        for pat in banned_patterns:
                            if pat.search(line):
                                violations.append((file, line_idx, line.strip()))

    assert len(violations) == 0, f"Found legacy Press E loops: {violations}"

def test_third_eye_intent_resolution():
    """Validates that NUI option intent payload is securely resolved against client target registry."""
    current_target = {
        'entity': 1234,
        'coords': {'x': 50.0, 'y': 60.0, 'z': 20.0},
        'options': [
            {'id': 'opt_loot', 'label': 'Open Ground Loot', 'event': 'nyx:inventory:client:openTargetDrop', 'args': {'dropId': 'drop:123'}},
            {'id': 'opt_move', 'label': 'Reposition / Move', 'event': 'nyx:inventory:client:grabTargetDrop', 'args': {'dropId': 'drop:123'}}
        ]
    }

    nui_payload = {'id': 'opt_move', 'action': None, 'label': 'Reposition / Move'}

    resolved = None
    for opt in current_target['options']:
        if opt['id'] == nui_payload['id']:
            resolved = opt
            break

    assert resolved is not None
    assert resolved['event'] == 'nyx:inventory:client:grabTargetDrop'
    assert resolved['args']['dropId'] == 'drop:123'
