-- ============================================================================
-- Nyxframework: nyx_services
-- Migration: 008_services_infrastructure.sql
-- Description: Regional power grid substations, metered utility accounts,
--              and healthcare medical supply reserves.
-- ============================================================================

-- Regional Electrical Substations and Power Grids
CREATE TABLE IF NOT EXISTS `nyx_services_substations` (
  `substation_id` VARCHAR(32) PRIMARY KEY,
  `label` VARCHAR(96) NOT NULL,
  `fuel_level` DECIMAL(6, 2) NOT NULL DEFAULT 100.00,
  `condition_health` DECIMAL(6, 2) NOT NULL DEFAULT 100.00,
  `is_blackout` TINYINT(1) DEFAULT 0,
  `coords` JSON NOT NULL,
  `bounding_radius` DECIMAL(8, 2) NOT NULL DEFAULT 1600.00,
  `last_maintained_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_blackout` (`is_blackout`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Metered Property Utility Consumption Accounts
CREATE TABLE IF NOT EXISTS `nyx_services_utility_meters` (
  `meter_id` VARCHAR(32) PRIMARY KEY,
  `owner_citizen_id` VARCHAR(16) NOT NULL,
  `linked_substation_id` VARCHAR(32) NOT NULL,
  `property_type` ENUM('residential', 'commercial', 'industrial') NOT NULL,
  `kwh_consumed` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  `water_consumed` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  `unpaid_balance` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `is_service_suspended` TINYINT(1) DEFAULT 0,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`linked_substation_id`) REFERENCES `nyx_services_substations`(`substation_id`) ON DELETE CASCADE,
  INDEX `idx_meter_owner` (`owner_citizen_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Hospital Medical Reserves & Treatment Availability
CREATE TABLE IF NOT EXISTS `nyx_services_hospitals` (
  `hospital_id` VARCHAR(32) PRIMARY KEY,
  `label` VARCHAR(96) NOT NULL,
  `coords` JSON NOT NULL,
  `substation_id` VARCHAR(32) NOT NULL,
  `trauma_kits` INT NOT NULL DEFAULT 50,
  `sterile_plasma` INT NOT NULL DEFAULT 100,
  `surgical_packs` INT NOT NULL DEFAULT 30,
  `status` ENUM('optimal', 'degraded', 'critical_shortage') DEFAULT 'optimal',
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`substation_id`) REFERENCES `nyx_services_substations`(`substation_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Initial Seed: Regional Substations
INSERT INTO `nyx_services_substations` (`substation_id`, `label`, `fuel_level`, `condition_health`, `is_blackout`, `coords`, `bounding_radius`)
VALUES
  ('grid_central_ls', 'Central Los Santos Metro Substation', 100.00, 100.00, 0, '{"x": 711.5, "y": -963.2, "z": 30.4}', 1600.00),
  ('grid_port_ls', 'Port of Los Santos & Cypress Industrial Grid', 100.00, 100.00, 0, '{"x": 1072.0, "y": -2006.0, "z": 31.5}', 1800.00),
  ('grid_rockford', 'Rockford Hills & Del Perro Power Station', 100.00, 100.00, 0, '{"x": -1440.0, "y": -250.0, "z": 48.0}', 2000.00),
  ('grid_sandy_shores', 'Grand Senora Desert Substation', 100.00, 100.00, 0, '{"x": 2732.0, "y": 1572.0, "z": 24.5}', 2500.00),
  ('grid_paleto', 'Paleto Bay & Mount Chiliad Regional Generator', 100.00, 100.00, 0, '{"x": 140.0, "y": 6600.0, "z": 31.8}', 2200.00)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

-- Initial Seed: Core Medical Facilities
INSERT INTO `nyx_services_hospitals` (`hospital_id`, `label`, `coords`, `substation_id`, `trauma_kits`, `sterile_plasma`, `surgical_packs`, `status`)
VALUES
  ('pillbox_hill', 'Pillbox Hill Medical Center', '{"x": 340.0, "y": -1396.0, "z": 32.5}', 'grid_central_ls', 50, 100, 30, 'optimal'),
  ('sandy_shores_clinic', 'Mount Zonah Desert Clinic', '{"x": 1839.5, "y": 3672.5, "z": 34.3}', 'grid_sandy_shores', 30, 50, 15, 'optimal'),
  ('paleto_bay_hospital', 'Paleto Bay Emergency Care Center', '{"x": -247.0, "y": 6331.0, "z": 32.4}', 'grid_paleto', 25, 40, 10, 'optimal')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);
