-- ============================================================================
-- Migration 060: Organizational Warehousing & Storage Networks
-- Resources: nyx_factions, nyx_logistics, nyx_inventory
-- Description: Enables autonomous player organizations, cooperatives, and commercial
--              enterprises to deploy, configure, and secure physical stashes,
--              industrial workbenches, and pallet drop zones bound to customized
--              role-based access control (RBAC) permissions.
-- ============================================================================

-- 1. Deployed Organizational Storage & Processing Assets
CREATE TABLE IF NOT EXISTS `nyx_factions_deployed_assets` (
    `asset_id` INT AUTO_INCREMENT PRIMARY KEY,
    `asset_uuid` VARCHAR(64) NOT NULL UNIQUE,
    `faction_id` VARCHAR(32) NOT NULL,
    `facility_type` ENUM('property', 'warehouse', 'commercial_storefront') NOT NULL,
    `facility_id` VARCHAR(64) NOT NULL,
    `asset_type` ENUM('secured_stash', 'industrial_workbench', 'pallet_drop_zone') NOT NULL,
    `asset_label` VARCHAR(64) NOT NULL,
    `model_name` VARCHAR(64) NOT NULL,
    `coords` LONGTEXT NOT NULL,
    `routing_bucket` INT NOT NULL DEFAULT 0,
    `access_permission_node` VARCHAR(64) NOT NULL DEFAULT 'inventory:view',
    `min_rank_level` INT NOT NULL DEFAULT 1,
    `inventory_id` VARCHAR(64) NULL,
    `capacity_grams` INT NOT NULL DEFAULT 1000000,
    `slots_count` INT NOT NULL DEFAULT 60,
    `workbench_subtype` ENUM('assembly', 'refining', 'weapons', 'medical', 'none') NOT NULL DEFAULT 'none',
    `pallet_max_capacity` INT NOT NULL DEFAULT 4,
    `staged_pallets_json` LONGTEXT NULL,
    `is_locked` TINYINT(1) NOT NULL DEFAULT 0,
    `decommissioned` TINYINT(1) NOT NULL DEFAULT 0,
    `deployed_by_citizen_id` VARCHAR(32) NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_faction_assets` (`faction_id`),
    INDEX `idx_facility_assets` (`facility_id`),
    INDEX `idx_type_assets` (`asset_type`),
    INDEX `idx_bucket_assets` (`routing_bucket`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Immutable Storage & Processing Access Audit Log
CREATE TABLE IF NOT EXISTS `nyx_factions_storage_access_audit` (
    `audit_id` INT AUTO_INCREMENT PRIMARY KEY,
    `audit_uuid` VARCHAR(64) NOT NULL UNIQUE,
    `asset_id` INT NOT NULL,
    `faction_id` VARCHAR(32) NOT NULL,
    `citizen_id` VARCHAR(32) NOT NULL,
    `action` ENUM('DEPLOYED', 'ACCESSED', 'STASH_OPENED', 'WORKBENCH_USED', 'PALLET_STAGED', 'PALLET_RETRIEVED', 'ACCESS_RULE_CHANGED', 'LOCK_TOGGLED', 'DECOMMISSIONED') NOT NULL,
    `permission_evaluated` VARCHAR(64) NOT NULL,
    `notes` VARCHAR(255) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_asset_audit` (`asset_id`),
    INDEX `idx_faction_audit` (`faction_id`),
    INDEX `idx_citizen_audit` (`citizen_id`),
    INDEX `idx_created_audit` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Seed Canonical Baseline Organizational Assets
INSERT INTO `nyx_factions_deployed_assets`
    (`asset_uuid`, `faction_id`, `facility_type`, `facility_id`, `asset_type`, `asset_label`, `model_name`, `coords`, `routing_bucket`, `access_permission_node`, `min_rank_level`, `inventory_id`, `capacity_grams`, `slots_count`, `workbench_subtype`, `pallet_max_capacity`, `staged_pallets_json`, `is_locked`, `decommissioned`, `deployed_by_citizen_id`)
VALUES
    ('asset-elysian-stash-01', 'corp:elysian_logistics', 'warehouse', 'wh_elysian_04', 'secured_stash', 'Elysian Főraktár Páncélrekesz', 'prop_ld_greenscrn_01', '{"x":156.4,"y":-3180.2,"z":6.1,"h":90.0}', 3004, 'inventory:withdraw', 2, 'faction:stash:deployed:asset-elysian-stash-01', 3000000, 100, 'none', 0, '[]', 0, 0, 'CIT-GOV-FOUNDER'),
    ('asset-elysian-bench-01', 'corp:elysian_logistics', 'warehouse', 'wh_elysian_04', 'industrial_workbench', 'Elysian Nehézipari Munkapad', 'gr_prop_gr_bench_02b', '{"x":160.2,"y":-3175.5,"z":6.1,"h":180.0}', 3004, 'inventory:manage_stashes', 2, NULL, 0, 0, 'assembly', 0, '[]', 0, 0, 'CIT-GOV-FOUNDER'),
    ('asset-elysian-pallet-01', 'corp:elysian_logistics', 'warehouse', 'wh_elysian_04', 'pallet_drop_zone', 'Elysian Pallet Átrakó Zóna A', 'prop_pallet_01a', '{"x":148.0,"y":-3190.0,"z":6.1,"h":0.0}', 3004, 'fleet:spawn', 1, NULL, 0, 0, 'none', 4, '[]', 0, 0, 'CIT-GOV-FOUNDER'),
    ('asset-vinewood-stash-01', 'corp:vinewood_retail', 'commercial_storefront', 'store_vinewood_24', 'secured_stash', 'Vinewood Üzleti Széf', 'prop_cabinet_02b', '{"x":-708.2,"y":-914.5,"z":19.2,"h":270.0}', 0, 'inventory:withdraw', 2, 'faction:stash:deployed:asset-vinewood-stash-01', 1000000, 60, 'none', 0, '[]', 0, 0, 'CIT-GOV-FOUNDER')
ON DUPLICATE KEY UPDATE `updated_at` = CURRENT_TIMESTAMP;
