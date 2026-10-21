-- ============================================================================
-- Nyxframework: nyx_vehicles, nyx_logistics, nyx_treasury & nyx_mdt
-- Migration: 066_municipal_toll_booths_and_commercial_weigh_stations.sql
-- Description: Municipal transit infrastructure, highway toll plazas,
--              automated RFID toll deduction, commercial axle multipliers,
--              and commercial weigh station inspection/bypass logging.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Create municipal toll plazas table
CREATE TABLE IF NOT EXISTS `nyx_toll_plazas` (
  `plaza_id` VARCHAR(32) NOT NULL PRIMARY KEY,
  `zone_name` VARCHAR(64) NOT NULL,
  `base_fee` DECIMAL(10, 2) NOT NULL DEFAULT 5.00,
  `commercial_axle_multiplier` DECIMAL(5, 2) NOT NULL DEFAULT 1.50,
  `active_status` TINYINT(1) NOT NULL DEFAULT 1,
  `total_collected` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_toll_zone` (`zone_name`),
  INDEX `idx_toll_status` (`active_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Create automated commercial weigh station inspection logs table
CREATE TABLE IF NOT EXISTS `nyx_weigh_station_logs` (
  `log_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `vehicle_plate` VARCHAR(16) NOT NULL,
  `driver_identifier` VARCHAR(64) NULL,
  `manifest_id` VARCHAR(64) NULL,
  `gross_weight_kg` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `max_allowed_kg` DECIMAL(10, 2) NOT NULL DEFAULT 15000.00,
  `overweight_fine` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `inspection_status` ENUM('PASS', 'OVERWEIGHT', 'CONTRABAND_FLAG', 'BYPASSED') NOT NULL DEFAULT 'PASS',
  `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_weigh_plate` (`vehicle_plate`),
  INDEX `idx_weigh_driver` (`driver_identifier`),
  INDEX `idx_weigh_manifest` (`manifest_id`),
  INDEX `idx_weigh_status` (`inspection_status`),
  INDEX `idx_weigh_timestamp` (`timestamp` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Seed municipal highway toll plazas
INSERT INTO `nyx_toll_plazas`
  (`plaza_id`, `zone_name`, `base_fee`, `commercial_axle_multiplier`, `active_status`, `total_collected`)
VALUES
  ('plaza_del_perro_fwy', 'Del Perro Freeway Gantry', 5.00, 1.50, 1, 0.00),
  ('plaza_la_puerta_fwy', 'La Puerta Freeway Toll Plaza', 7.50, 1.75, 1, 0.00),
  ('plaza_palomino_fwy', 'Palomino Freeway East Barrier', 10.00, 2.00, 1, 0.00),
  ('plaza_senora_fwy', 'Senora Freeway North Express Gantry', 6.00, 1.60, 1, 0.00)
ON DUPLICATE KEY UPDATE `zone_name` = VALUES(`zone_name`);

SET FOREIGN_KEY_CHECKS = 1;
