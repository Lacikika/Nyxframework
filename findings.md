# Findings: Organizational Warehousing & Storage Networks (`nyx_factions`, `nyx_logistics` & `nyx_inventory`)

## Context & Architecture
1. **Organizational Storage Networks (Tervek.md 5.2)**:
   - Self-formed player corporations, unions, and cooperatives require decentralized, staff-free infrastructure to store goods, craft items, and stage logistics hauls.
   - Deployed assets are bound to facilities (e.g. warehouses from `nyx_logistics`, commercial storefronts from `nyx_properties`, or corporate properties).
   - Asset Types:
     - `secured_stash`: High-capacity inventory container with customizable RBAC access permissions (`inventory:view`, `inventory:deposit`, `inventory:withdraw`, or wildcard `*`) and minimum rank level.
     - `industrial_workbench`: Crafting / processing station supporting assembly, mineral refining, weapon etching, and pharmaceutical synthesis.
     - `pallet_drop_zone`: Designated physical staging pad for commercial freight pallets (`prop_pallet_01a`) allowing quick forklift and flatbed transfer.

2. **Access Control & RBAC Interlocks**:
   - Assets are owned by a faction (`faction_id`).
   - Access is evaluated using `Nyx.CorporateRBAC.EvaluatePermission`:
     - Global wildcard `*` grants supreme executive access.
     - Category wildcard `inventory:*` grants access to all inventory and storage assets.
     - Exact permission node (e.g. `inventory:withdraw` vs `inventory:deposit`).
     - Minimum rank tier (e.g. 1 = Associate, 2 = Supervisor, 3 = Executive).
   - Security locks:
     - If `is_locked == 1`, only members with `inventory:manage_stashes` or wildcard `*` can access or unlock it.

3. **Facility Bounds & Capacity Limits**:
   - Warehouses: Up to 10 stashes, 4 workbenches, 4 pallet drop zones.
   - Commercial Storefronts: Up to 4 stashes, 2 workbenches, 1 pallet drop zone.
   - Standard Properties: Up to 2 stashes, 1 workbench, 0 pallet drop zones.
