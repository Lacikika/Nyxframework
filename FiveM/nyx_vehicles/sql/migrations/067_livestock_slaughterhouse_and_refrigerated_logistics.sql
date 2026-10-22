-- ============================================================================
-- Nyxframework: nyx_services, nyx_logistics, nyx_vehicles & nyx_inventory
-- Migration: 067_livestock_slaughterhouse_and_refrigerated_logistics.sql
-- Description: Agricultural livestock husbandry, slaughterhouse processing,
--              carcass decay, refrigerated cold-chain logistics, and reefer
--              freight haulage tracking.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Create livestock ranches table
CREATE TABLE IF NOT EXISTS `nyx_livestock_ranches` (
  `ranch_id` VARCHAR(32) NOT NULL PRIMARY KEY,
  `ranch_name` VARCHAR(64) NOT NULL,
  `zone_name` VARCHAR(64) NOT NULL,
  `cattle_head` INT NOT NULL DEFAULT 50,
  `max_capacity` INT NOT NULL DEFAULT 200,
  `feed_level` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
  `health_index` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_ranch_zone` (`zone_name`),
  INDEX `idx_ranch_health` (`health_index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Create slaughterhouse facilities table
CREATE TABLE IF NOT EXISTS `nyx_slaughterhouses` (
  `facility_id` VARCHAR(32) NOT NULL PRIMARY KEY,
  `facility_name` VARCHAR(64) NOT NULL,
  `cold_chain_temp_c` DECIMAL(4, 1) NOT NULL DEFAULT 2.0,
  `cold_storage_capacity` INT NOT NULL DEFAULT 500,
  `cleanliness_index` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
  `total_carcasses_processed` INT NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_slaughter_temp` (`cold_chain_temp_c`),
  INDEX `idx_slaughter_clean` (`cleanliness_index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Create refrigerated cold-chain telemetry logs table
CREATE TABLE IF NOT EXISTS `nyx_refrigerated_logs` (
  `log_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `container_id` VARCHAR(64) NOT NULL,
  `item_name` VARCHAR(64) NOT NULL,
  `durability` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
  `is_reefer_active` TINYINT(1) NOT NULL DEFAULT 1,
  `temperature_c` DECIMAL(4, 1) NOT NULL DEFAULT 2.0,
  `inspection_status` ENUM('PRISTINE', 'FRESH', 'STALE', 'SPOILED') NOT NULL DEFAULT 'PRISTINE',
  `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_reefer_container` (`container_id`),
  INDEX `idx_reefer_item` (`item_name`),
  INDEX `idx_reefer_status` (`inspection_status`),
  INDEX `idx_reefer_timestamp` (`timestamp` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Seed regional livestock ranches
INSERT INTO `nyx_livestock_ranches`
  (`ranch_id`, `ranch_name`, `zone_name`, `cattle_head`, `max_capacity`, `feed_level`, `health_index`)
VALUES
  ('ranch_grapeseed', 'O\'Neil Grapeseed Livestock Ranch', 'Grapeseed', 120, 200, 100.00, 100.00),
  ('ranch_paleto', 'Paleto Bay Coastal Cattle Ranch', 'Paleto Bay', 80, 150, 95.00, 98.00)
ON DUPLICATE KEY UPDATE `ranch_name` = VALUES(`ranch_name`);

-- 5. Seed regional slaughterhouse facilities
INSERT INTO `nyx_slaughterhouses`
  (`facility_id`, `facility_name`, `cold_chain_temp_c`, `cold_storage_capacity`, `cleanliness_index`, `total_carcasses_processed`)
VALUES
  ('slaughterhouse_cypress_flats', 'Cypress Flats Industrial Slaughterhouse', 2.0, 500, 100.00, 0),
  ('slaughterhouse_paleto', 'Paleto Meat Processing Plant', 1.5, 300, 96.50, 0)
ON DUPLICATE KEY UPDATE `facility_name` = VALUES(`facility_name`);

SET FOREIGN_KEY_CHECKS = 1;
