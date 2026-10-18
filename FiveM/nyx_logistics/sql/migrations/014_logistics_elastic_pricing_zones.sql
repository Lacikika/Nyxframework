-- ============================================================================
-- Nyxframework Logistics Engine Database Migration
-- File: 014_logistics_elastic_pricing_zones.sql
-- Description: Localized Delivery Zones, Dynamic Stock-to-Demand Elasticity,
--              Zone Tax Surcharges, and Commodity Price Index Tracking.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Localized Economic Delivery Zones (Logisztikai Kiszállítási Körzetek)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_logistics_zones` (
  `zone_id` VARCHAR(32) PRIMARY KEY,
  `name` VARCHAR(64) NOT NULL,
  `description` VARCHAR(255) NULL,
  `coords` JSON NOT NULL,
  `radius` FLOAT NOT NULL DEFAULT 1500.0,
  `base_demand_multiplier` DECIMAL(5, 2) NOT NULL DEFAULT 1.00 CHECK (`base_demand_multiplier` >= 0.10 AND `base_demand_multiplier` <= 5.00),
  `tax_surcharge` DECIMAL(5, 4) NOT NULL DEFAULT 0.0000 CHECK (`tax_surcharge` >= 0.0000 AND `tax_surcharge` <= 0.1000),
  `import_tariff_rate` DECIMAL(5, 4) NOT NULL DEFAULT 0.0000 CHECK (`import_tariff_rate` >= 0.0000),
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 2. Seed Default Delivery Zones (Los Santos Metro, Sandy Shores, Paleto Bay, Port)
-- ----------------------------------------------------------------------------
INSERT INTO `nyx_logistics_zones` 
  (`zone_id`, `name`, `description`, `coords`, `radius`, `base_demand_multiplier`, `tax_surcharge`, `import_tariff_rate`, `is_active`)
VALUES
  ('zone_ls_metro', 'Los Santos Metro', 'Dense urban consumer core with accelerated retail throughput and municipal tax surcharges.', '{"x": -48.2, "y": -1757.4, "z": 29.4}', 2500.0, 1.35, 0.0150, 0.0000, 1),
  ('zone_sandy_shores', 'Blaine County Central', 'Semi-arid rural outpost with moderate demand and zero municipal retail surcharges.', '{"x": 1845.2, "y": 3782.1, "z": 33.5}', 2000.0, 0.85, 0.0000, 0.0050, 1),
  ('zone_paleto_bay', 'Paleto Bay Enclave', 'Remote northern maritime settlement with high shipping distance overhead and lower base consumption.', '{"x": -140.5, "y": 6350.2, "z": 31.5}', 1800.0, 0.75, 0.0000, 0.0200, 1),
  ('zone_port_industrial', 'Port of Los Santos Logistics Basin', 'Heavy maritime terminal, bulk freight staging area, and processing depot.', '{"x": 152.4, "y": -3205.2, "z": 5.9}', 1600.0, 1.15, 0.0050, 0.0000, 1)
ON DUPLICATE KEY UPDATE 
  `name` = VALUES(`name`),
  `base_demand_multiplier` = VALUES(`base_demand_multiplier`),
  `tax_surcharge` = VALUES(`tax_surcharge`);

-- ----------------------------------------------------------------------------
-- 3. Enhance Retail Shelves with Zone Affinity & Sales Velocity Metrics
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_logistics_shelves`
  ADD COLUMN IF NOT EXISTS `zone_id` VARCHAR(32) NOT NULL DEFAULT 'zone_ls_metro' AFTER `store_id`,
  ADD COLUMN IF NOT EXISTS `sales_velocity` DECIMAL(8, 2) NOT NULL DEFAULT 0.00 AFTER `current_price`,
  ADD COLUMN IF NOT EXISTS `last_purchased_at` TIMESTAMP NULL DEFAULT NULL AFTER `sales_velocity`,
  ADD INDEX IF NOT EXISTS `idx_shelf_zone` (`zone_id`);

-- Update existing shelves with accurate geographic zones
UPDATE `nyx_logistics_shelves` SET `zone_id` = 'zone_ls_metro' WHERE `shelf_id` = 'shelf_vinewood_tools';
UPDATE `nyx_logistics_shelves` SET `zone_id` = 'zone_ls_metro' WHERE `shelf_id` = 'shelf_pillbox_meds';

-- ----------------------------------------------------------------------------
-- 4. Enhance Freight Contracts with Regional Zone Tagging
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_logistics_freight_contracts`
  ADD COLUMN IF NOT EXISTS `zone_id` VARCHAR(32) NULL AFTER `dest_coords`,
  ADD INDEX IF NOT EXISTS `idx_freight_zone` (`zone_id`);

-- ----------------------------------------------------------------------------
-- 5. Rolling Demand Velocity & Price Audit Journal
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_logistics_price_history` (
  `history_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `shelf_id` VARCHAR(64) NOT NULL,
  `zone_id` VARCHAR(32) NOT NULL,
  `item_id` VARCHAR(64) NOT NULL,
  `base_price` DECIMAL(10, 2) NOT NULL,
  `calculated_price` DECIMAL(10, 2) NOT NULL,
  `stock_level` INT NOT NULL,
  `effective_demand` DECIMAL(10, 2) NOT NULL,
  `stock_to_demand_ratio` DECIMAL(6, 4) NOT NULL,
  `price_multiplier` DECIMAL(6, 4) NOT NULL,
  `recorded_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_history_shelf` (`shelf_id`, `recorded_at` DESC),
  INDEX `idx_history_zone` (`zone_id`, `recorded_at` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;
