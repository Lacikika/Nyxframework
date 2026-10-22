-- ============================================================================
-- Nyxframework: nyx_services, nyx_properties, nyx_treasury & nyx_vehicles
-- Migration: 067_municipal_water_utility_and_hydrant_pressure.sql
-- Description: Municipal reservoirs, contamination diffusion, pump station power
--              dependencies, and fire hydrant pressure dynamics.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Create municipal water reservoirs table
CREATE TABLE IF NOT EXISTS `nyx_water_reservoirs` (
  `reservoir_id` VARCHAR(32) NOT NULL PRIMARY KEY,
  `label` VARCHAR(64) NOT NULL,
  `water_level_liters` DECIMAL(15, 2) NOT NULL DEFAULT 5000000.00,
  `max_capacity_liters` DECIMAL(15, 2) NOT NULL DEFAULT 10000000.00,
  `purity_percentage` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
  `contamination_ppm` DECIMAL(8, 2) NOT NULL DEFAULT 0.00,
  `substation_id` VARCHAR(32) NOT NULL,
  `coords_x` DECIMAL(10, 4) NOT NULL DEFAULT 0.0000,
  `coords_y` DECIMAL(10, 4) NOT NULL DEFAULT 0.0000,
  `coords_z` DECIMAL(10, 4) NOT NULL DEFAULT 0.0000,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_res_substation` (`substation_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Create municipal pump stations table
CREATE TABLE IF NOT EXISTS `nyx_water_pump_stations` (
  `pump_id` VARCHAR(32) NOT NULL PRIMARY KEY,
  `reservoir_id` VARCHAR(32) NOT NULL,
  `substation_id` VARCHAR(32) NOT NULL,
  `pump_status` ENUM('ONLINE', 'OFFLINE_POWER', 'FAULT') NOT NULL DEFAULT 'ONLINE',
  `flow_rate_lps` DECIMAL(8, 2) NOT NULL DEFAULT 150.00,
  `power_draw_kw` DECIMAL(8, 2) NOT NULL DEFAULT 750.00,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_pump_res` (`reservoir_id`),
  INDEX `idx_pump_sub` (`substation_id`),
  INDEX `idx_pump_status` (`pump_status`),
  CONSTRAINT `fk_pump_reservoir` FOREIGN KEY (`reservoir_id`) REFERENCES `nyx_water_reservoirs`(`reservoir_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Create municipal fire hydrants table
CREATE TABLE IF NOT EXISTS `nyx_fire_hydrants` (
  `hydrant_id` VARCHAR(32) NOT NULL PRIMARY KEY,
  `reservoir_id` VARCHAR(32) NOT NULL,
  `coords_x` DECIMAL(10, 4) NOT NULL DEFAULT 0.0000,
  `coords_y` DECIMAL(10, 4) NOT NULL DEFAULT 0.0000,
  `coords_z` DECIMAL(10, 4) NOT NULL DEFAULT 0.0000,
  `pressure_psi` DECIMAL(6, 2) NOT NULL DEFAULT 85.00,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `last_inspected_at` TIMESTAMP NULL DEFAULT NULL,
  INDEX `idx_hydrant_res` (`reservoir_id`),
  INDEX `idx_hydrant_status` (`is_active`),
  CONSTRAINT `fk_hydrant_reservoir` FOREIGN KEY (`reservoir_id`) REFERENCES `nyx_water_reservoirs`(`reservoir_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Create water contamination incident log table
CREATE TABLE IF NOT EXISTS `nyx_water_contamination_events` (
  `event_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `reservoir_id` VARCHAR(32) NOT NULL,
  `contaminant_type` VARCHAR(64) NOT NULL,
  `ppm_added` DECIMAL(8, 2) NOT NULL DEFAULT 0.00,
  `reported_by` VARCHAR(64) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_contam_res` (`reservoir_id`),
  INDEX `idx_contam_time` (`created_at` DESC),
  CONSTRAINT `fk_contam_reservoir` FOREIGN KEY (`reservoir_id`) REFERENCES `nyx_water_reservoirs`(`reservoir_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed default reservoirs
INSERT INTO `nyx_water_reservoirs`
  (`reservoir_id`, `label`, `water_level_liters`, `max_capacity_liters`, `purity_percentage`, `contamination_ppm`, `substation_id`, `coords_x`, `coords_y`, `coords_z`)
VALUES
  ('res_vinewood_lake', 'Vinewood Hills Main Reservoir', 8500000.00, 10000000.00, 100.00, 0.00, 'grid_central_ls', 212.4500, 715.3200, 185.1000),
  ('res_zancudo_aquifer', 'Fort Zancudo Subterranean Aquifer', 6000000.00, 8000000.00, 99.50, 0.50, 'grid_zancudo', -2250.1000, 3210.4500, 15.2000),
  ('res_paleto_basin', 'Paleto Bay Coastal Basin', 4500000.00, 5000000.00, 100.00, 0.00, 'grid_paleto', -280.5000, 6210.8000, 30.0000)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

-- Seed default pump stations
INSERT INTO `nyx_water_pump_stations`
  (`pump_id`, `reservoir_id`, `substation_id`, `pump_status`, `flow_rate_lps`, `power_draw_kw`)
VALUES
  ('pump_vinewood_01', 'res_vinewood_lake', 'grid_central_ls', 'ONLINE', 250.00, 1200.00),
  ('pump_zancudo_01', 'res_zancudo_aquifer', 'grid_zancudo', 'ONLINE', 180.00, 900.00),
  ('pump_paleto_01', 'res_paleto_basin', 'grid_paleto', 'ONLINE', 120.00, 600.00)
ON DUPLICATE KEY UPDATE `reservoir_id` = VALUES(`reservoir_id`);

-- Seed default fire hydrants
INSERT INTO `nyx_fire_hydrants`
  (`hydrant_id`, `reservoir_id`, `coords_x`, `coords_y`, `coords_z`, `pressure_psi`, `is_active`)
VALUES
  ('hydrant_vinewood_01', 'res_vinewood_lake', 220.1000, 700.5000, 180.2000, 85.00, 1),
  ('hydrant_legion_01', 'res_vinewood_lake', 150.0000, -900.0000, 30.0000, 90.00, 1),
  ('hydrant_zancudo_01', 'res_zancudo_aquifer', -2200.0000, 3200.0000, 15.0000, 80.00, 1),
  ('hydrant_paleto_01', 'res_paleto_basin', -270.0000, 6200.0000, 30.0000, 75.00, 1)
ON DUPLICATE KEY UPDATE `reservoir_id` = VALUES(`reservoir_id`);

SET FOREIGN_KEY_CHECKS = 1;
