-- Nyxframework Logistics & Supply Chain Schema
-- Migration: 004_logistics_schema.sql

-- 1. Finite natural extraction points
CREATE TABLE IF NOT EXISTS `nyx_logistics_nodes` (
  `node_id` VARCHAR(64) PRIMARY KEY,
  `resource_item` VARCHAR(64) NOT NULL,
  `current_reserve` INT UNSIGNED NOT NULL,
  `max_reserve` INT UNSIGNED NOT NULL,
  `regen_rate_per_hour` INT UNSIGNED NOT NULL,
  `coords` JSON NOT NULL,
  `last_harvested_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_resource` (`resource_item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Processing, refining, and assembly facilities
CREATE TABLE IF NOT EXISTS `nyx_logistics_facilities` (
  `facility_id` VARCHAR(64) PRIMARY KEY,
  `owner_faction_id` VARCHAR(64) NULL,
  `type` ENUM('refinery', 'smelter', 'assembly', 'chemical') NOT NULL,
  `input_inventory_id` VARCHAR(64) NOT NULL,
  `output_inventory_id` VARCHAR(64) NOT NULL,
  `power_grid_id` VARCHAR(32) NOT NULL,
  `is_active` TINYINT(1) DEFAULT 0,
  `active_recipe` VARCHAR(64) NULL,
  `progress` DECIMAL(5, 2) DEFAULT 0.00,
  INDEX `idx_owner` (`owner_faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Physical shelf containers tied to points of sale
CREATE TABLE IF NOT EXISTS `nyx_logistics_shelves` (
  `shelf_id` VARCHAR(64) PRIMARY KEY,
  `store_id` VARCHAR(32) NOT NULL,
  `target_capacity` INT UNSIGNED NOT NULL DEFAULT 100,
  `item_id` VARCHAR(64) NOT NULL,
  `base_price` DECIMAL(10, 2) NOT NULL,
  `current_price` DECIMAL(10, 2) NOT NULL,
  `inventory_id` VARCHAR(64) NOT NULL,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_store` (`store_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Public freight contracts generated dynamically by shortages
CREATE TABLE IF NOT EXISTS `nyx_logistics_contracts` (
  `contract_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `source_inventory_id` VARCHAR(64) NOT NULL,
  `dest_shelf_id` VARCHAR(64) NOT NULL,
  `item_id` VARCHAR(64) NOT NULL,
  `quantity` INT UNSIGNED NOT NULL,
  `payout_per_unit` DECIMAL(10, 2) NOT NULL,
  `issuer_faction_id` VARCHAR(64) NOT NULL,
  `status` ENUM('available', 'in_transit', 'completed', 'expired') DEFAULT 'available',
  `claimed_by_char_id` INT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 5. Initial Seed Data
INSERT IGNORE INTO `nyx_logistics_nodes` (`node_id`, `resource_item`, `current_reserve`, `max_reserve`, `regen_rate_per_hour`, `coords`) VALUES
('mine_quarry_iron', 'refined_iron', 500, 500, 50, '{"x": 2950.1, "y": 2780.4, "z": 41.2}'),
('mine_copper_sandy', 'refined_copper', 400, 400, 40, '{"x": 1845.2, "y": 3782.1, "z": 33.5}'),
('oil_well_sandy', 'crude_oil', 1000, 1000, 100, '{"x": 605.3, "y": 2898.6, "z": 41.8}');

INSERT IGNORE INTO `nyx_logistics_facilities` (`facility_id`, `type`, `input_inventory_id`, `output_inventory_id`, `power_grid_id`) VALUES
('fac_sandy_refinery', 'refinery', 'stash:refinery_in', 'stash:refinery_out', 'grid_sandy_01'),
('fac_davis_assembly', 'assembly', 'stash:assembly_in', 'stash:assembly_out', 'grid_city_01');

INSERT IGNORE INTO `nyx_logistics_shelves` (`shelf_id`, `store_id`, `target_capacity`, `item_id`, `base_price`, `current_price`, `inventory_id`) VALUES
('shelf_vinewood_tools', 'store_vinewood_247', 100, 'tool_repairkit', 100.00, 100.00, 'stash:vinewood_tools'),
('shelf_pillbox_meds', 'store_pillbox_pharmacy', 50, 'med_firstaid', 75.00, 75.00, 'stash:pillbox_meds');
