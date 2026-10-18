import pytest
import math
import os
import json
import re

def round2(val):
    return round(val, 2)

def calculate_shelf_nodes(shelf):
    """Python reference mirror of Nyx.Warehouses.CalculateShelfNodes."""
    shelf_id = shelf.get('shelf_id', 'shelf_01')
    warehouse_id = shelf.get('warehouse_id', 'wh_01')
    label = shelf.get('label', 'Shelf Rack')
    coords = shelf.get('coords', {'x': 0.0, 'y': 0.0, 'z': 0.0})
    shelf_x = float(coords.get('x', 0.0))
    shelf_y = float(coords.get('y', 0.0))
    shelf_z = float(coords.get('z', 0.0))

    rot = shelf.get('rotation', {})
    heading = float(rot.get('heading', rot.get('z', 0.0)))
    heading = (heading % 360.0 + 360.0) % 360.0

    tiers = int(shelf.get('tiers', 3))
    slots_per_tier = int(shelf.get('slots_per_tier', 3))
    tier_spacing = float(shelf.get('tier_spacing', 0.50))
    slot_spacing = float(shelf.get('slot_spacing', 0.55))
    tier_base_z = float(shelf.get('tier_base_z', 0.35))
    depth_offset = float(shelf.get('depth_offset', 0.05))
    routing_bucket = int(shelf.get('routing_bucket', 0))

    rad = math.radians(heading)
    cos_a = math.cos(rad)
    sin_a = math.sin(rad)

    nodes_map = {}
    nodes_list = []

    for t in range(1, tiers + 1):
        dz = tier_base_z + (t - 1) * tier_spacing
        for s in range(1, slots_per_tier + 1):
            dx = (s - (slots_per_tier + 1) / 2.0) * slot_spacing
            dy = depth_offset

            # 2D Euler heading rotation
            wx = shelf_x + (dx * cos_a - dy * sin_a)
            wy = shelf_y + (dx * sin_a + dy * cos_a)
            wz = shelf_z + dz

            node_id = f"{shelf_id}:t{t}_s{s}"
            node_obj = {
                'id': node_id,
                'shelf_id': shelf_id,
                'warehouse_id': warehouse_id,
                'shelf_label': label,
                'tier': t,
                'slot': s,
                'local_offset': {'x': round(dx, 3), 'y': round(dy, 3), 'z': round(dz, 3)},
                'world_coords': {'x': round2(wx), 'y': round2(wy), 'z': round2(wz)},
                'heading': round2(heading),
                'routing_bucket': routing_bucket,
                'occupied_drop_id': None
            }
            nodes_map[node_id] = node_obj
            nodes_list.append(node_obj)

    return nodes_map, nodes_list

def find_nearest_snap_node(nodes_map, target_point, max_snap_distance=0.85, current_drop_id=None):
    """Python mirror of Nyx.Warehouses.FindNearestSnapNode."""
    best_node = None
    best_dist = max_snap_distance + 0.001
    tx = float(target_point.get('x', 0.0))
    ty = float(target_point.get('y', 0.0))
    tz = float(target_point.get('z', 0.0))

    for node_id, node in nodes_map.items():
        occ = node.get('occupied_drop_id')
        if occ is None or (current_drop_id and occ == current_drop_id):
            nx = node['world_coords']['x']
            ny = node['world_coords']['y']
            nz = node['world_coords']['z']
            dx = tx - nx
            dy = ty - ny
            dz = tz - nz
            dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            if dist <= max_snap_distance and dist < best_dist:
                best_dist = dist
                best_node = node

    return best_node, round(best_dist, 3) if best_node else None

def test_shelf_matrix_3d_node_generation_north():
    """Validates 3D grid node offsets when shelf faces North (heading = 0.0)."""
    shelf = {
        'shelf_id': 'shelf_wh_01',
        'warehouse_id': 'wh_dock_ls_01',
        'coords': {'x': 1050.0, 'y': -3100.0, 'z': -39.0},
        'rotation': {'heading': 0.0},
        'tiers': 3,
        'slots_per_tier': 3,
        'tier_spacing': 0.50,
        'slot_spacing': 0.55,
        'tier_base_z': 0.35,
        'depth_offset': 0.05,
        'routing_bucket': 3001
    }

    nodes_map, nodes_list = calculate_shelf_nodes(shelf)
    assert len(nodes_list) == 9

    # Tier 1, Slot 1 (Left column, bottom shelf)
    t1_s1 = nodes_map['shelf_wh_01:t1_s1']
    assert t1_s1['tier'] == 1 and t1_s1['slot'] == 1
    assert t1_s1['world_coords']['x'] == 1049.45  # 1050.0 - 0.55
    assert t1_s1['world_coords']['y'] == -3099.95 # -3100.0 + 0.05
    assert t1_s1['world_coords']['z'] == -38.65   # -39.0 + 0.35

    # Tier 1, Slot 2 (Center column, bottom shelf)
    t1_s2 = nodes_map['shelf_wh_01:t1_s2']
    assert t1_s2['world_coords']['x'] == 1050.0
    assert t1_s2['world_coords']['y'] == -3099.95
    assert t1_s2['world_coords']['z'] == -38.65

    # Tier 3, Slot 3 (Right column, top shelf)
    t3_s3 = nodes_map['shelf_wh_01:t3_s3']
    assert t3_s3['tier'] == 3 and t3_s3['slot'] == 3
    assert t3_s3['world_coords']['x'] == 1050.55
    assert t3_s3['world_coords']['z'] == -37.65   # -39.0 + 0.35 + 2 * 0.50

def test_shelf_matrix_rotations():
    """Validates 2D Euler heading rotations for shelf matrix across 90 and 180 degrees."""
    shelf_west = {
        'shelf_id': 'shelf_west',
        'warehouse_id': 'wh_dock_ls_01',
        'coords': {'x': 1052.0, 'y': -3096.0, 'z': -39.0},
        'rotation': {'heading': 90.0},
        'tiers': 2,
        'slots_per_tier': 2,
        'tier_spacing': 0.60,
        'slot_spacing': 0.80,
        'tier_base_z': 0.40,
        'depth_offset': 0.10,
        'routing_bucket': 3001
    }

    nodes_map, _ = calculate_shelf_nodes(shelf_west)
    assert len(nodes_map) == 4

    # Heading 90 (West): Forward along -X, Lateral along +Y
    # Slot 1: dx = -0.40, dy = 0.10 -> wx = 1052 - 0.10 = 1051.90, wy = -3096 - 0.40 = -3096.40
    # Slot 2: dx = +0.40, dy = 0.10 -> wx = 1052 - 0.10 = 1051.90, wy = -3096 + 0.40 = -3095.60
    t1_s1 = nodes_map['shelf_west:t1_s1']
    t1_s2 = nodes_map['shelf_west:t1_s2']

    assert t1_s1['world_coords']['x'] == 1051.90
    assert t1_s1['world_coords']['y'] == -3096.40
    assert t1_s2['world_coords']['x'] == 1051.90
    assert t1_s2['world_coords']['y'] == -3095.60

    # Distance between slot 1 and slot 2 along shelf should be exactly 0.80m
    dx = t1_s2['world_coords']['x'] - t1_s1['world_coords']['x']
    dy = t1_s2['world_coords']['y'] - t1_s1['world_coords']['y']
    assert round(math.sqrt(dx*dx + dy*dy), 2) == 0.80

def test_nearest_snap_node_gating():
    """Validates snapping threshold and boundary rejection."""
    shelf = {
        'shelf_id': 'shelf_snap',
        'coords': {'x': 0.0, 'y': 0.0, 'z': 0.0},
        'rotation': {'heading': 0.0},
        'tiers': 1,
        'slots_per_tier': 2,
        'slot_spacing': 1.0,
        'tier_base_z': 0.0,
        'depth_offset': 0.0
    }
    # Slots at (-0.5, 0, 0) and (+0.5, 0, 0)
    nodes_map, _ = calculate_shelf_nodes(shelf)

    # Near Slot 1 (-0.5, 0, 0)
    near_pt = {'x': -0.45, 'y': 0.05, 'z': 0.02}
    node, dist = find_nearest_snap_node(nodes_map, near_pt, max_snap_distance=0.85)
    assert node is not None
    assert node['id'] == 'shelf_snap:t1_s1'
    assert dist < 0.15

    # Out of range (> 0.85m from any slot)
    far_pt = {'x': -0.5, 'y': 1.5, 'z': 0.0}
    far_node, _ = find_nearest_snap_node(nodes_map, far_pt, max_snap_distance=0.85)
    assert far_node is None

def test_single_occupancy_and_resnap_tolerance():
    """Validates that occupied nodes cannot be snapped by third parties, but can be re-snapped by owner."""
    shelf = {
        'shelf_id': 'shelf_occ',
        'coords': {'x': 0.0, 'y': 0.0, 'z': 0.0},
        'rotation': {'heading': 0.0},
        'tiers': 1,
        'slots_per_tier': 2,
        'slot_spacing': 1.0,
        'tier_base_z': 0.0,
        'depth_offset': 0.0
    }
    nodes_map, _ = calculate_shelf_nodes(shelf)

    # Occupy slot 1 with drop A
    nodes_map['shelf_occ:t1_s1']['occupied_drop_id'] = 'drop:A'

    # Query from drop B at slot 1 position -> must skip slot 1 and snap to slot 2
    near_s1 = {'x': -0.45, 'y': 0.02, 'z': 0.0}
    b_node, _ = find_nearest_snap_node(nodes_map, near_s1, max_snap_distance=1.2, current_drop_id='drop:B')
    assert b_node is not None
    assert b_node['id'] == 'shelf_occ:t1_s2'

    # Query from drop A (owner repositioning) at slot 1 position -> can re-snap to slot 1
    a_node, _ = find_nearest_snap_node(nodes_map, near_s1, max_snap_distance=0.85, current_drop_id='drop:A')
    assert a_node is not None
    assert a_node['id'] == 'shelf_occ:t1_s1'

def test_virtual_routing_bucket_isolation():
    """Validates that overworld (Bucket 0) clients never stream entities from interior warehouse buckets."""
    all_drops = [
        {'id': 'drop:overworld_apple', 'routing_bucket': 0},
        {'id': 'drop:overworld_car',   'routing_bucket': 0},
        {'id': 'drop:warehouse_copper', 'routing_bucket': 3001},
        {'id': 'drop:warehouse_iron',   'routing_bucket': 3001},
        {'id': 'drop:sandy_fuel',       'routing_bucket': 3002}
    ]

    def get_client_streamed_drops(drops, player_bucket):
        return [d for d in drops if d.get('routing_bucket', 0) == player_bucket]

    # Player on public street
    overworld_drops = get_client_streamed_drops(all_drops, player_bucket=0)
    assert len(overworld_drops) == 2
    assert all(d['routing_bucket'] == 0 for d in overworld_drops)
    assert not any('warehouse' in d['id'] for d in overworld_drops)

    # Player inside Port Warehouse (Bucket 3001)
    port_drops = get_client_streamed_drops(all_drops, player_bucket=3001)
    assert len(port_drops) == 2
    assert all(d['routing_bucket'] == 3001 for d in port_drops)

    # Player inside Sandy Freight Depot (Bucket 3002)
    sandy_drops = get_client_streamed_drops(all_drops, player_bucket=3002)
    assert len(sandy_drops) == 1
    assert sandy_drops[0]['id'] == 'drop:sandy_fuel'

def test_manifest_and_migration_integrity():
    """Validates migration 019 registration in index.json and script registration in fxmanifest.lua."""
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    migration_index_path = os.path.join(root_dir, 'FiveM', 'nyx_core', 'sql', 'migrations', 'index.json')
    with open(migration_index_path, 'r', encoding='utf-8') as f:
        migrations = json.load(f)

    assert "019_logistics_warehouses_and_shelf_matrices.sql" in migrations

    # Check fxmanifest
    fxmanifest_path = os.path.join(root_dir, 'FiveM', 'nyx_logistics', 'fxmanifest.lua')
    with open(fxmanifest_path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert "shared/warehouses.lua" in content
    assert "server/warehouses.lua" in content
    assert "client/warehouses.lua" in content
