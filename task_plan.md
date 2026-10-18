# Task Plan: Organizational Warehousing & Storage Networks (`nyx_factions`, `nyx_logistics` & `nyx_inventory`)

## Goal
Implement full organizational warehousing and storage networks from Tervek.md section 5.2. Enable player organizations (factions/cooperatives/enterprises) to deploy, configure, and operate secured stashes, industrial workbenches, and pallet drop zones bound to customized role-based access control (RBAC) levels within their owned or leased warehouses, commercial storefronts, and facility properties.

## Architecture & Requirements
1. **Database Migration (`060_organizational_warehousing_and_storage_networks.sql` & `index.json`)**:
   - Table `nyx_factions_deployed_assets`:
     - `asset_id` INT AUTO_INCREMENT PRIMARY KEY
     - `asset_uuid` VARCHAR(64) NOT NULL UNIQUE
     - `faction_id` VARCHAR(32) NOT NULL
     - `facility_type` ENUM('property', 'warehouse', 'commercial_storefront') NOT NULL
     - `facility_id` VARCHAR(64) NOT NULL
     - `asset_type` ENUM('secured_stash', 'industrial_workbench', 'pallet_drop_zone') NOT NULL
     - `asset_label` VARCHAR(64) NOT NULL
     - `model_name` VARCHAR(64) NOT NULL
     - `coords` LONGTEXT NOT NULL (JSON: `{x, y, z, h}`)
     - `routing_bucket` INT NOT NULL DEFAULT 0
     - `access_permission_node` VARCHAR(64) NOT NULL DEFAULT 'inventory:view'
     - `min_rank_level` INT NOT NULL DEFAULT 1
     - `inventory_id` VARCHAR(64) NULL
     - `capacity_grams` INT NOT NULL DEFAULT 1000000 (1,000 kg)
     - `slots_count` INT NOT NULL DEFAULT 60
     - `workbench_subtype` ENUM('assembly', 'refining', 'weapons', 'medical', 'none') NOT NULL DEFAULT 'none'
     - `pallet_max_capacity` INT NOT NULL DEFAULT 4
     - `staged_pallets_json` LONGTEXT NULL
     - `is_locked` TINYINT(1) NOT NULL DEFAULT 0
     - `decommissioned` TINYINT(1) NOT NULL DEFAULT 0
     - `deployed_by_citizen_id` VARCHAR(32) NOT NULL
     - `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
     - `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
   - Table `nyx_factions_storage_access_audit`:
     - `audit_id` INT AUTO_INCREMENT PRIMARY KEY
     - `audit_uuid` VARCHAR(64) NOT NULL UNIQUE
     - `asset_id` INT NOT NULL
     - `faction_id` VARCHAR(32) NOT NULL
     - `citizen_id` VARCHAR(32) NOT NULL
     - `action` ENUM('DEPLOYED', 'ACCESSED', 'STASH_OPENED', 'WORKBENCH_USED', 'PALLET_STAGED', 'PALLET_RETRIEVED', 'ACCESS_RULE_CHANGED', 'LOCK_TOGGLED', 'DECOMMISSIONED') NOT NULL
     - `permission_evaluated` VARCHAR(64) NOT NULL
     - `notes` VARCHAR(255) NULL
     - `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
   - Seed default deployment catalog and baseline fixtures.
   - Register Step 60 in `FiveM/nyx_core/sql/migrations/index.json` and mirror to `FiveM/nyx_factions/sql/migrations/`.

2. **Shared Pure Lua 5.4 Domain Engine (`FiveM/nyx_factions/shared/storage_networks.lua`)**:
   - `Nyx.StorageNetworks.Taxonomy`: Asset types (`secured_stash`, `industrial_workbench`, `pallet_drop_zone`), subtypes, capacities, default models, fee schedules.
   - `Nyx.StorageNetworks.EvaluateAssetAccess(asset, citizenMember)`: Granular RBAC evaluation using wildcard hierarchy (`*`, `inventory:*`, `inventory:withdraw`, `inventory:manage_stashes`), rank levels, and lock status.
   - `Nyx.StorageNetworks.ValidateDeploymentParameters(facilityType, facilityId, assetType, subtype, coords, existingCount)`: Spatial validation, bounds checking, and facility density limits.
   - `Nyx.StorageNetworks.EvaluatePalletStaging(dropZone, palletId, action)`: Pallet staging / retrieval logic with capacity bounds and deduplication.
   - `Nyx.StorageNetworks.FormatAssetSummary(asset, memberCount)`: Badge formatting and ASCII summary for terminal inspection.

3. **Authoritative Server Subsystems & RPCs (`FiveM/nyx_factions/server/storage_networks.lua`)**:
   - Startup hydration into memory `Nyx.Factions.DeployedAssets`.
   - Dynamic inventory container registration via `exports['nyx_inventory']:RegisterContainer(...)`.
   - RPC routes:
     - `factions:getFacilityAssets(facilityId)`
     - `factions:deployStorageAsset(payload)`
     - `factions:accessStorageAsset(assetId)`
     - `factions:updateAssetAccessRule(assetId, newPermission, minRank)`
     - `factions:toggleAssetLock(assetId)`
     - `factions:decommissionStorageAsset(assetId)`
     - `factions:stagePalletInDropZone(assetId, palletId)`
     - `factions:retrievePalletFromDropZone(assetId, palletId)`
   - Server exports in `server/exports.lua`:
     - `GetDeployedAsset(assetId)`
     - `GetFacilityAssets(facilityId)`
     - `CanCitizenAccessAsset(citizenId, assetId)`
     - `DeployStorageAsset(factionId, assetData)`
     - `DecommissionStorageAsset(assetId)`

4. **Client Subsystems & Spatial Interaction (`FiveM/nyx_factions/client/storage_networks.lua`)**:
   - Spawns client-side prop entities with proper collision and freezing.
   - Third-Eye targets (`nyx_interact`):
     - Secured Stash: "Biztonsági Raktárláda Megnyitása" & "Láda Jogosultságok Kezelése".
     - Industrial Workbench: "Ipari Munkapad Használata" & "Munkapad Karbantartása".
     - Pallet Drop Zone: "Raklap Lerakása Zónába" & "Raklap Felvétele Zónából".
   - Event listeners for real-time asset syncing across clients.
   - Player commands: `/deployasset [stash|workbench|pallet_zone]`, `/facilityassets`.

5. **Manifest Declarations**:
   - `FiveM/nyx_factions/fxmanifest.lua`: Add `shared/storage_networks.lua`, `server/storage_networks.lua`, `client/storage_networks.lua`.
   - `FiveM/nyx_logistics/fxmanifest.lua`: Add `@nyx_factions/shared/storage_networks.lua`.

6. **In-Engine Integration Test (`FiveM/nyx_core/server/tests.lua`)**:
   - Test 55: `Nyx.Tests.TestOrganizationalWarehousingAndStorageNetworks()`
   - Validates taxonomy, access evaluation with wildcards and rank requirements, capacity and slots math, deployment validation, pallet staging arithmetic, lock states, and receipt generation.
   - Wire into `Nyx.Tests.RunAll()`.

7. **Dedicated Pytest Suite (`tests/test_organizational_warehousing_and_storage_networks.py`)**:
   - Unit tests for pure algorithms, SQL migration, manifest entries, and integration tests.

## Phase Plan
- [x] Phase 1: Test-Driven Design — Create pytest test suite (`tests/test_organizational_warehousing_and_storage_networks.py`)
- [x] Phase 2: Database Migration — Create `060_organizational_warehousing_and_storage_networks.sql`, register in `index.json`, mirror to `nyx_factions`
- [x] Phase 3: Shared Pure Lua 5.4 Storage Networks Engine — Implement `FiveM/nyx_factions/shared/storage_networks.lua`, update manifests
- [x] Phase 4: Authoritative Server Subsystems & RPCs — Implement `FiveM/nyx_factions/server/storage_networks.lua`, update `server/exports.lua` and `server/main.lua`
- [x] Phase 5: Client Subsystems & Spatial Interaction — Implement `FiveM/nyx_factions/client/storage_networks.lua`, update `client/exports.lua`
- [x] Phase 6: In-Engine Integration Test — Implement Test 55 in `FiveM/nyx_core/server/tests.lua` & wire into `RunAll()`
- [x] Phase 7: Full Verification & Completion — Run pytest, validator.py, verify.ps1, update `AGENT_TASK.md` and `Tervek.md`
