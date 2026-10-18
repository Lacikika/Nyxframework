-- ============================================================================
-- Nyxframework: nyx_services & nyx_logistics
-- Migration: 046_agricultural_extraction_milling_and_perishable_food_logistics.sql
-- Description: Natural crop harvest nodes, soil fertility tracking, industrial grain
--              milling refineries, municipal emergency food pantries, perishable food
--              decay tracking, and retail food shelf logistics.
-- ============================================================================

-- 1. Agricultural Farmland & Crop Harvest Tracking
CREATE TABLE IF NOT EXISTS `nyx_logistics_agriculture_farms` (
  `farm_id` VARCHAR(64) PRIMARY KEY,
  `name` VARCHAR(128) NOT NULL,
  `zone_id` VARCHAR(32) NOT NULL,
  `crop_type` VARCHAR(64) NOT NULL,
  `soil_fertility` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
  `irrigation_status` VARCHAR(24) NOT NULL DEFAULT 'optimal',
  `current_reserve` INT UNSIGNED NOT NULL DEFAULT 600,
  `max_reserve` INT UNSIGNED NOT NULL DEFAULT 600,
  `regen_rate_per_hour` INT UNSIGNED NOT NULL DEFAULT 60,
  `coords` JSON NOT NULL,
  `last_harvested_at` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_farm_crop` (`crop_type`),
  INDEX `idx_farm_zone` (`zone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Municipal Emergency Food Pantries & Relief Stashes
CREATE TABLE IF NOT EXISTS `nyx_services_food_pantries` (
  `pantry_id` VARCHAR(64) PRIMARY KEY,
  `name` VARCHAR(128) NOT NULL,
  `zone_id` VARCHAR(32) NOT NULL,
  `stash_id` VARCHAR(64) NOT NULL UNIQUE,
  `target_rations` INT UNSIGNED NOT NULL DEFAULT 100,
  `target_bread` INT UNSIGNED NOT NULL DEFAULT 50,
  `status` ENUM('optimal', 'degraded', 'critical_shortage') NOT NULL DEFAULT 'optimal',
  `last_emergency_contract_at` TIMESTAMP NULL DEFAULT NULL,
  `last_inspection_at` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_pantry_status` (`status`),
  INDEX `idx_pantry_zone` (`zone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Immutable Agricultural & Food Logistics Audit Ledger
CREATE TABLE IF NOT EXISTS `nyx_logistics_food_audit` (
  `audit_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `action` VARCHAR(32) NOT NULL,
  `source_id` VARCHAR(64) NULL,
  `target_inventory_id` VARCHAR(64) NULL,
  `item_id` VARCHAR(64) NOT NULL,
  `quantity` INT NOT NULL,
  `durability` DECIMAL(5, 2) NULL,
  `is_spoiled` TINYINT(1) DEFAULT 0,
  `citizen_id` VARCHAR(64) NULL,
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_faudit_action` (`action`),
  INDEX `idx_faudit_item` (`item_id`),
  INDEX `idx_faudit_target` (`target_inventory_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Seed Canonical Agricultural Farmland Nodes
INSERT INTO `nyx_logistics_agriculture_farms`
  (`farm_id`, `name`, `zone_id`, `crop_type`, `soil_fertility`, `irrigation_status`, `current_reserve`, `max_reserve`, `regen_rate_per_hour`, `coords`)
VALUES
  ('farm_grapeseed_wheat', 'Grapeseed Golden Wheat Fields', 'grapeseed', 'crop_wheat', 100.00, 'optimal', 800, 800, 80, '{"x": 2320.5, "y": 4890.2, "z": 41.5}'),
  ('farm_chaparral_corn', 'Great Chaparral Sun Corn Plantation', 'chaparral', 'crop_corn', 100.00, 'optimal', 600, 600, 60, '{"x": 1055.2, "y": 1420.4, "z": 98.2}'),
  ('farm_paleto_produce', 'Paleto Bay Coastal Organic Orchard', 'paleto_bay', 'crop_produce', 100.00, 'optimal', 500, 500, 50, '{"x": -420.8, "y": 6250.6, "z": 30.5}')
ON DUPLICATE KEY UPDATE
  `name` = VALUES(`name`),
  `crop_type` = VALUES(`crop_type`),
  `coords` = VALUES(`coords`);

-- 5. Mirror Farm Extraction Points into nyx_logistics_nodes
INSERT INTO `nyx_logistics_nodes`
  (`node_id`, `resource_item`, `current_reserve`, `max_reserve`, `regen_rate_per_hour`, `coords`)
VALUES
  ('farm_grapeseed_wheat', 'crop_wheat', 800, 800, 80, '{"x": 2320.5, "y": 4890.2, "z": 41.5}'),
  ('farm_chaparral_corn', 'crop_corn', 600, 600, 60, '{"x": 1055.2, "y": 1420.4, "z": 98.2}'),
  ('farm_paleto_produce', 'crop_produce', 500, 500, 50, '{"x": -420.8, "y": 6250.6, "z": 30.5}')
ON DUPLICATE KEY UPDATE
  `resource_item` = VALUES(`resource_item`),
  `coords` = VALUES(`coords`);

-- 6. Register Grapeseed Grain Mill Facility in nyx_logistics_facilities
INSERT INTO `nyx_logistics_facilities`
  (`facility_id`, `type`, `coords`, `input_inventory_id`, `output_inventory_id`, `power_grid_id`, `power_status`, `pallet_dock_coords`, `pallet_dock_heading`, `output_mode`)
VALUES
  ('fac_grapeseed_mill', 'refinery', '{"x": 2434.5, "y": 4968.2, "z": 46.0}', 'stash:grapeseed_mill_in', 'stash:grapeseed_mill_out', 'grid_sandy_shores', 'online', '{"x": 2438.0, "y": 4964.0, "z": 46.0}', 180.0, 'inventory')
ON DUPLICATE KEY UPDATE
  `type` = VALUES(`type`),
  `coords` = VALUES(`coords`),
  `pallet_dock_coords` = VALUES(`pallet_dock_coords`);

-- 7. Seed Municipal Food Pantries
INSERT INTO `nyx_services_food_pantries`
  (`pantry_id`, `name`, `zone_id`, `stash_id`, `target_rations`, `target_bread`, `status`)
VALUES
  ('pantry_city_hall', 'City Hall Emergency Food Pantry', 'los_santos_metro', 'stash:pantry_city_hall', 150, 75, 'optimal'),
  ('pantry_sandy_community', 'Sandy Shores Community Food Pantry', 'sandy_shores', 'stash:pantry_sandy_community', 100, 50, 'optimal')
ON DUPLICATE KEY UPDATE
  `name` = VALUES(`name`),
  `target_rations` = VALUES(`target_rations`),
  `target_bread` = VALUES(`target_bread`);

-- 8. Seed Storage Containers in nyx_inventories
INSERT INTO `nyx_inventories` (`id`, `type`, `max_weight`, `max_slots`, `coords`)
VALUES
  ('stash:grapeseed_mill_in', 'stash', 1500000, 100, '{"x": 2434.5, "y": 4968.2, "z": 46.0}'),
  ('stash:grapeseed_mill_out', 'stash', 1500000, 100, '{"x": 2436.5, "y": 4966.2, "z": 46.0}'),
  ('stash:pantry_city_hall', 'stash', 800000, 80, '{"x": -545.0, "y": -204.0, "z": 38.2}'),
  ('stash:pantry_sandy_community', 'stash', 600000, 80, '{"x": 1852.0, "y": 3688.0, "z": 34.2}'),
  ('stash:store_vinewood_food', 'stash', 500000, 60, '{"x": 373.8, "y": 325.8, "z": 103.5}'),
  ('stash:store_davis_food', 'stash', 500000, 60, '{"x": -48.2, "y": -1757.5, "z": 29.4}')
ON DUPLICATE KEY UPDATE `type` = VALUES(`type`), `coords` = VALUES(`coords`);

-- 9. Seed Retail Food Shelves in nyx_logistics_shelves
INSERT INTO `nyx_logistics_shelves`
  (`shelf_id`, `store_id`, `target_capacity`, `item_id`, `base_price`, `current_price`, `inventory_id`)
VALUES
  ('shelf_vinewood_food', 'store_vinewood_247', 80, 'food_bread', 12.00, 12.00, 'stash:store_vinewood_food'),
  ('shelf_davis_food', 'store_davis_ltd', 100, 'food_sandwich', 15.00, 15.00, 'stash:store_davis_food')
ON DUPLICATE KEY UPDATE
  `target_capacity` = VALUES(`target_capacity`),
  `base_price` = VALUES(`base_price`),
  `current_price` = VALUES(`current_price`);

-- 10. Seed Initial Stocks into Mill, Pantry, and Shelf Containers
INSERT INTO `nyx_inventory_items` (`item_uuid`, `inventory_id`, `item_id`, `slot`, `amount`, `metadata`)
VALUES
  (UUID(), 'stash:grapeseed_mill_in', 'crop_wheat', 1, 80, '{"label": "Raw Wheat Sheaf", "durability": 100.0}'),
  (UUID(), 'stash:grapeseed_mill_in', 'crop_corn', 2, 60, '{"label": "Field Corn Ears", "durability": 100.0}'),
  (UUID(), 'stash:grapeseed_mill_out', 'bulk_flour', 1, 40, '{"label": "Commercial Milled Flour Sack", "durability": 100.0}'),
  (UUID(), 'stash:grapeseed_mill_out', 'bulk_cornmeal', 2, 30, '{"label": "Industrial Cornmeal Sack", "durability": 100.0}'),
  (UUID(), 'stash:pantry_city_hall', 'food_ration', 1, 80, '{"label": "Civil Defense Ration", "durability": 100.0, "nutrition": 45}'),
  (UUID(), 'stash:pantry_city_hall', 'food_bread', 2, 40, '{"label": "Fresh Artisan Bread Loaf", "durability": 100.0, "isSpoiled": false, "nutrition": 35}'),
  (UUID(), 'stash:pantry_sandy_community', 'food_ration', 1, 50, '{"label": "Civil Defense Ration", "durability": 100.0, "nutrition": 45}'),
  (UUID(), 'stash:pantry_sandy_community', 'food_bread', 2, 25, '{"label": "Fresh Artisan Bread Loaf", "durability": 100.0, "isSpoiled": false, "nutrition": 35}'),
  (UUID(), 'stash:store_vinewood_food', 'food_bread', 1, 30, '{"label": "Fresh Artisan Bread Loaf", "durability": 100.0, "isSpoiled": false, "nutrition": 35}'),
  (UUID(), 'stash:store_vinewood_food', 'food_sandwich', 2, 25, '{"label": "Fresh Sandwich", "durability": 100.0, "isSpoiled": false, "nutrition": 25}'),
  (UUID(), 'stash:store_davis_food', 'food_bread', 1, 25, '{"label": "Fresh Artisan Bread Loaf", "durability": 100.0, "isSpoiled": false, "nutrition": 35}'),
  (UUID(), 'stash:store_davis_food', 'food_sandwich', 2, 35, '{"label": "Fresh Sandwich", "durability": 100.0, "isSpoiled": false, "nutrition": 25}')
ON DUPLICATE KEY UPDATE `amount` = VALUES(`amount`);
