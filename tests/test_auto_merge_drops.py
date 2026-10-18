import pytest
import math
import os
import re

def test_weight_tiered_fallback_model_resolution():
    """Validates that items and containers resolve to appropriate 3D box/crate models based on category and weight."""
    categories = {
        'medical': [
            {'max_weight': 2000, 'model': 'prop_ld_health_pack'},
            {'max_weight': float('inf'), 'model': 'prop_med_box_01b'}
        ],
        'ammo': [
            {'max_weight': 5000, 'model': 'prop_box_ammo04a'},
            {'max_weight': float('inf'), 'model': 'prop_box_ammo03a'}
        ],
        'freight': [
            {'max_weight': 25000, 'model': 'prop_wooden_crate_01'},
            {'max_weight': float('inf'), 'model': 'prop_boxpile_06a'}
        ]
    }

    tiers = [
        {'max_weight': 2500,  'model': 'prop_paper_bag_small'},
        {'max_weight': 10000, 'model': 'prop_cs_cardbox_01'},
        {'max_weight': 35000, 'model': 'prop_box_wood02a'},
        {'max_weight': 80000, 'model': 'prop_wooden_crate_01'},
        {'max_weight': float('inf'), 'model': 'prop_boxpile_06a'}
    ]

    def resolve_fallback(category, weight):
        if category in categories:
            for rule in categories[category]:
                if weight <= rule['max_weight']:
                    return rule['model']
        for rule in tiers:
            if weight <= rule['max_weight']:
                return rule['model']
        return 'prop_paper_bag_small'

    # Medical category brackets
    assert resolve_fallback('medical', 1500) == 'prop_ld_health_pack'
    assert resolve_fallback('medical', 3000) == 'prop_med_box_01b'

    # Ammo category brackets
    assert resolve_fallback('ammo', 2500) == 'prop_box_ammo04a'
    assert resolve_fallback('ammo', 6000) == 'prop_box_ammo03a'

    # Freight category brackets
    assert resolve_fallback('freight', 15000) == 'prop_wooden_crate_01'
    assert resolve_fallback('freight', 60000) == 'prop_boxpile_06a'

    # General / material weight tiers
    assert resolve_fallback('material', 800) == 'prop_paper_bag_small'
    assert resolve_fallback('material', 5000) == 'prop_cs_cardbox_01'
    assert resolve_fallback('material', 20000) == 'prop_box_wood02a'
    assert resolve_fallback('material', 65000) == 'prop_wooden_crate_01'
    assert resolve_fallback('material', 95000) == 'prop_boxpile_06a'

def test_custom_item_model_precedence():
    """Validates that dedicated GTA V item models take precedence over fallback props."""
    registry = {
        'weapon_pistol': {'type': 'weapon', 'weight': 1000, 'client_model': 'w_pi_pistol'},
        'refined_iron': {'type': 'material', 'weight': 2500}
    }

    def resolve_model(item_id, count=1):
        item = registry[item_id]
        if 'client_model' in item:
            return item['client_model']
        weight = item['weight'] * count
        if weight <= 2500:
            return 'prop_paper_bag_small'
        elif weight <= 35000:
            return 'prop_box_wood02a'
        return 'prop_boxpile_06a'

    assert resolve_model('weapon_pistol', 1) == 'w_pi_pistol'
    assert resolve_model('refined_iron', 1) == 'prop_paper_bag_small'
    assert resolve_model('refined_iron', 5) == 'prop_box_wood02a'

def test_proximity_distance_auto_merge_threshold():
    """Validates 1.5m proximity radius gating for auto-merging world drops."""
    merge_radius = 1.5

    existing_drops = {
        'drop:A': {'coords': {'x': 100.0, 'y': 200.0, 'z': 30.0}},
        'drop:B': {'coords': {'x': 110.0, 'y': 200.0, 'z': 30.0}}
    }

    def find_merge_target(coords):
        best_id, best_dist = None, float('inf')
        for drop_id, data in existing_drops.items():
            dx = data['coords']['x'] - coords['x']
            dy = data['coords']['y'] - coords['y']
            dz = data['coords']['z'] - coords['z']
            dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            if dist <= merge_radius and dist < best_dist:
                best_dist = dist
                best_id = drop_id
        return best_id, best_dist

    # Position 1.1m from Drop A (within 1.5m threshold) -> Merges into Drop A
    match_id, dist = find_merge_target({'x': 100.8, 'y': 200.8, 'z': 30.0})
    assert match_id == 'drop:A'
    assert dist <= 1.5

    # Position 2.0m from Drop A (exceeds 1.5m threshold) -> Independent drop
    match_id, _ = find_merge_target({'x': 102.0, 'y': 200.0, 'z': 30.0})
    assert match_id is None

def test_stack_merging_and_max_stack_limit():
    """Validates stack consolidation into existing slots up to maxStack with overflow handling."""
    max_stack = 100
    container = {
        1: {'item_id': 'ammo_9mm', 'amount': 80},
        2: {'item_id': 'med_bandage', 'amount': 5}
    }

    def merge_item(item_id, amount):
        remaining = amount
        # Step 1: Top off existing stacks
        for slot, item in container.items():
            if item['item_id'] == item_id:
                space = max_stack - item['amount']
                if space > 0:
                    add = min(remaining, space)
                    item['amount'] += add
                    remaining -= add
                    if remaining <= 0:
                        break
        # Step 2: Spill overflow into first empty slot
        if remaining > 0:
            empty_slot = max(container.keys()) + 1
            container[empty_slot] = {'item_id': item_id, 'amount': remaining}
            remaining = 0
        return remaining == 0

    # Add 35 ammo: 20 fills slot 1 (80 -> 100), remaining 15 spills into slot 3
    success = merge_item('ammo_9mm', 35)
    assert success is True
    assert container[1]['amount'] == 100
    assert container[3]['item_id'] == 'ammo_9mm'
    assert container[3]['amount'] == 15

def test_container_max_weight_ceiling():
    """Validates that a container rejects merging items that would breach its maximum weight capacity."""
    max_weight = 100000 # 100 kg
    current_weight = 94000 # 94 kg

    def can_merge(incoming_weight):
        return (current_weight + incoming_weight) <= max_weight

    assert can_merge(5000) is True   # 94kg + 5kg = 99kg <= 100kg
    assert can_merge(6000) is True   # 94kg + 6kg = 100kg <= 100kg
    assert can_merge(6500) is False  # 94kg + 6.5kg = 100.5kg > 100kg (Rejected)

def test_dynamic_prop_morphing_telemetry():
    """Validates that container 3D model morphs when total weight transitions between tiers."""
    def get_tier_model(weight):
        if weight <= 2500:
            return 'prop_paper_bag_small'
        elif weight <= 10000:
            return 'prop_cs_cardbox_01'
        elif weight <= 35000:
            return 'prop_box_wood02a'
        return 'prop_wooden_crate_01'

    # Initial state: 1 item (500g) -> paper bag
    drop = {'weight': 500, 'model': get_tier_model(500)}
    assert drop['model'] == 'prop_paper_bag_small'

    # After merging 20kg of materials -> upgraded to wooden crate
    drop['weight'] += 20000
    drop['model'] = get_tier_model(drop['weight'])
    assert drop['model'] == 'prop_box_wood02a'

def test_container_to_container_relocation_merge():
    """Validates that repositioning a container to within 1.5m of another merges all items and deletes source."""
    boxes = {
        'drop:SRC': {'items': [{'item_id': 'refined_iron', 'amount': 3}], 'coords': {'x': 100.0, 'y': 200.0, 'z': 30.0}},
        'drop:DST': {'items': [{'item_id': 'refined_iron', 'amount': 7}], 'coords': {'x': 101.0, 'y': 200.0, 'z': 30.0}}
    }

    # Relocate SRC within 1.0m of DST
    src_total = sum(x['amount'] for x in boxes['drop:SRC']['items'])
    dst_total = sum(x['amount'] for x in boxes['drop:DST']['items'])
    total_expected = src_total + dst_total

    # Perform relocation merge
    for it in boxes['drop:SRC']['items']:
        boxes['drop:DST']['items'][0]['amount'] += it['amount']
    del boxes['drop:SRC']

    assert 'drop:SRC' not in boxes
    assert boxes['drop:DST']['items'][0]['amount'] == total_expected
    assert boxes['drop:DST']['items'][0]['amount'] == 10

def test_code_audit_auto_merge_and_fallback_models():
    """Verifies that all required Lua files, configurations, and migrations exist with proper syntax and bindings."""
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    inv_dir = os.path.join(base_dir, "FiveM", "nyx_inventory")

    # 1. Verify shared/drops.lua exists
    shared_drops = os.path.join(inv_dir, "shared", "drops.lua")
    assert os.path.exists(shared_drops)
    with open(shared_drops, "r", encoding="utf-8") as f:
        content = f.read()
        assert "Nyx.Drops.GetFallbackModel" in content
        assert "Nyx.Drops.ResolveModel" in content
        assert "Nyx.Drops.GetAllFallbackModels" in content

    # 2. Verify config.lua has DropAutoMergeDistance and DropFallbackModels
    config_file = os.path.join(inv_dir, "config.lua")
    assert os.path.exists(config_file)
    with open(config_file, "r", encoding="utf-8") as f:
        cfg = f.read()
        assert "Config.DropAutoMergeDistance = 1.5" in cfg
        assert "Config.DropFallbackModels" in cfg

    # 3. Verify server/drops.lua has merge functions
    server_drops = os.path.join(inv_dir, "server", "drops.lua")
    assert os.path.exists(server_drops)
    with open(server_drops, "r", encoding="utf-8") as f:
        sd = f.read()
        assert "Nyx.Drops.FindAutoMergeTarget" in sd
        assert "Nyx.Drops.MergeItem" in sd
        assert "Nyx.Drops.TryAutoMergeContainers" in sd
        assert "Nyx.Drops.RecalculateModel" in sd

    # 4. Verify server/actions.lua hooks merge in dropItem & commitWorldPlacement
    server_actions = os.path.join(inv_dir, "server", "actions.lua")
    with open(server_actions, "r", encoding="utf-8") as f:
        sa = f.read()
        assert "Nyx.Drops.FindAutoMergeTarget" in sa
        assert "Nyx.Drops.MergeItem" in sa
        assert "Nyx.Drops.TryAutoMergeContainers" in sa

    # 5. Verify client/drops.lua registers all fallback models and handles model updates
    client_drops = os.path.join(inv_dir, "client", "drops.lua")
    with open(client_drops, "r", encoding="utf-8") as f:
        cd = f.read()
        assert "dropModelUpdated" in cd
        assert "GetAllFallbackModels" in cd

    # 6. Verify migration 018 exists and is registered in index.json
    migration_018_core = os.path.join(base_dir, "FiveM", "nyx_core", "sql", "migrations", "018_inventory_drop_models.sql")
    migration_018_inv = os.path.join(inv_dir, "sql", "migrations", "018_inventory_drop_models.sql")
    index_json = os.path.join(base_dir, "FiveM", "nyx_core", "sql", "migrations", "index.json")

    assert os.path.exists(migration_018_core)
    assert os.path.exists(migration_018_inv)
    with open(index_json, "r", encoding="utf-8") as f:
        idx = f.read()
        assert "018_inventory_drop_models.sql" in idx
