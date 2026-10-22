-- ============================================================================
-- Nyxframework: nyx_vehicles, nyx_services & nyx_treasury
-- Migration: 067_highway_degradation_and_transit_repair.sql
-- Description: Commercial highway infrastructure degradation, heavy vehicle axle stress
--              pavement wear modeling, municipal road quality tracking, and
--              public works asphalt/resurfacing repair contracts.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Create highway segments table
CREATE TABLE IF NOT EXISTS `nyx_highway_segments` (
  `segment_id` VARCHAR(64) NOT NULL PRIMARY KEY,
  `highway_name` VARCHAR(128) NOT NULL,
  `start_coords` JSON NOT NULL,
  `end_coords` JSON NOT NULL,
  `length_meters` DECIMAL(10, 2) NOT NULL DEFAULT 1000.00,
  `quality_pct` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
  `total_heavy_axle_passages` INT UNSIGNED NOT NULL DEFAULT 0,
  `status` ENUM('OPTIMAL', 'WEAR_WARNING', 'DEGRADED', 'CRITICAL') NOT NULL DEFAULT 'OPTIMAL',
  `last_repaired_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_seg_highway` (`highway_name`),
  INDEX `idx_seg_quality` (`quality_pct`),
  INDEX `idx_seg_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Create municipal road repair contracts table
CREATE TABLE IF NOT EXISTS `nyx_road_repair_contracts` (
  `contract_id` VARCHAR(64) NOT NULL PRIMARY KEY,
  `segment_id` VARCHAR(64) NOT NULL,
  `required_asphalt_kg` DECIMAL(10, 2) NOT NULL DEFAULT 1000.00,
  `treasury_payout` DECIMAL(10, 2) NOT NULL DEFAULT 2500.00,
  `assigned_faction_id` VARCHAR(64) NULL DEFAULT NULL,
  `status` ENUM('OPEN', 'IN_PROGRESS', 'COMPLETED', 'EXPIRED') NOT NULL DEFAULT 'OPEN',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed_at` TIMESTAMP NULL DEFAULT NULL,
  FOREIGN KEY (`segment_id`) REFERENCES `nyx_highway_segments` (`segment_id`) ON DELETE CASCADE,
  INDEX `idx_repair_segment` (`segment_id`),
  INDEX `idx_repair_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Seed major municipal highway transit corridors
INSERT INTO `nyx_highway_segments`
  (`segment_id`, `highway_name`, `start_coords`, `end_coords`, `length_meters`, `quality_pct`, `total_heavy_axle_passages`, `status`)
VALUES
  ('seg_del_perro_fwy_1', 'Del Perro Freeway - Westbound Corridor', '{"x": -1200.0, "y": -800.0, "z": 15.0}', '{"x": 400.0, "y": -800.0, "z": 25.0}', 1600.00, 100.00, 0, 'OPTIMAL'),
  ('seg_la_puerta_fwy_1', 'La Puerta Freeway - Port Access Connector', '{"x": -200.0, "y": -2000.0, "z": 10.0}', '{"x": 400.0, "y": -1500.0, "z": 20.0}', 1200.00, 95.00, 12, 'OPTIMAL'),
  ('seg_palomino_fwy_1', 'Palomino Freeway - East Industrial Bypass', '{"x": 1200.0, "y": -1000.0, "z": 30.0}', '{"x": 2200.0, "y": 500.0, "z": 45.0}', 2500.00, 82.00, 48, 'OPTIMAL'),
  ('seg_senora_fwy_1', 'Senora Freeway - Desert Logistics Route', '{"x": 1500.0, "y": 2500.0, "z": 50.0}', '{"x": 2500.0, "y": 4500.0, "z": 60.0}', 3200.00, 68.00, 120, 'WEAR_WARNING')
ON DUPLICATE KEY UPDATE `highway_name` = VALUES(`highway_name`);

SET FOREIGN_KEY_CHECKS = 1;
