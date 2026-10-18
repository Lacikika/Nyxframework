-- ============================================================================
-- Nyxframework: nyx_parliament & nyx_mdt & nyx_vehicles
-- Migration: 059_dynamic_speed_limits_statutory_laws_and_mdt_overlays.sql
-- Description: Dynamic Speed Limits, Statutory Law Formulation, Sales Tax Caps,
--              Zoning Policies, and MDT Real-Time Dispatch Warning Overlays.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Extend Parliament Laws Table with Subsystem Target & Description
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_parliament_laws`
  ADD COLUMN IF NOT EXISTS `subsystem_target` ENUM('mdt', 'treasury', 'vehicles', 'properties', 'general') NOT NULL DEFAULT 'general' AFTER `category`,
  ADD COLUMN IF NOT EXISTS `description` VARCHAR(255) NULL DEFAULT NULL AFTER `title`;

-- ----------------------------------------------------------------------------
-- 2. Seed Dynamic Speed Limits, Tax Caps, and Statutory Offenses
-- ----------------------------------------------------------------------------
INSERT INTO `nyx_parliament_laws` 
  (`law_id`, `title`, `description`, `category`, `subsystem_target`, `current_value`, `min_allowed`, `max_allowed`)
VALUES
  ('speed:urban', 'Statutory Speed Limit: Urban Metro Zones', 'Maximum allowable speed within municipal urban surface street zones.', 'speed_limit', 'vehicles', '{"mph": 45}', '{"mph": 25}', '{"mph": 65}'),
  ('speed:highway', 'Statutory Speed Limit: Interstates & Highways', 'Maximum allowable velocity across primary highways and interstates.', 'speed_limit', 'vehicles', '{"mph": 75}', '{"mph": 55}', '{"mph": 100}'),
  ('speed:industrial', 'Statutory Speed Limit: Industrial & Port Corridors', 'Designated safe hauling velocity within heavy industrial and logistics sectors.', 'speed_limit', 'vehicles', '{"mph": 35}', '{"mph": 20}', '{"mph": 50}'),
  ('speed:school_residential', 'Statutory Speed Limit: School & Residential Districts', 'Strict traffic calming ceiling for suburban residential neighborhoods and schools.', 'speed_limit', 'vehicles', '{"mph": 25}', '{"mph": 15}', '{"mph": 35}'),
  ('penal:speeding_minor', 'Traffic Infraction: Minor Speeding (6-15 mph over)', 'Exceeding statutory zone speed limit by 6 to 15 mph.', 'penal_infraction', 'mdt', '{"fine": 250, "months": 0}', '{"fine": 50, "months": 0}', '{"fine": 1000, "months": 0}'),
  ('penal:speeding_major', 'Traffic Misdemeanor: Major Speeding (16-30 mph over)', 'Exceeding statutory zone speed limit by 16 to 30 mph.', 'penal_misdemeanor', 'mdt', '{"fine": 750, "months": 5}', '{"fine": 250, "months": 0}', '{"fine": 3000, "months": 15}'),
  ('tax:sales_cap', 'Statutory Maximum Legal Sales Tax Cap Rate', 'Upper constitutional boundary on point-of-sale transaction tax rates.', 'fiscal_policy', 'treasury', '{"rate": 0.12}', '{"rate": 0.05}', '{"rate": 0.20}'),
  ('zoning:commercial_tax_rebate', 'Zoning Policy: Commercial Business District Tax Rebate', 'Tax incentive reduction percentage applied to registered storefront leases in commercial zones.', 'zoning', 'properties', '{"rebate": 0.02}', '{"rebate": 0.00}', '{"rebate": 0.05}'),
  ('zoning:industrial_environmental_surcharge', 'Zoning Policy: Industrial Environmental Surcharge', 'Heavy freight and manufacturing environmental mitigation surcharge percentage.', 'zoning', 'properties', '{"surcharge": 0.03}', '{"surcharge": 0.00}', '{"surcharge": 0.08}'),
  ('zoning:residential_noise_curfew', 'Zoning Policy: Residential Quiet Hours Curfew', 'Evening hour starting statutory residential noise abatement enforcement.', 'zoning', 'general', '{"hour": 22}', '{"hour": 20}', '{"hour": 24}')
ON DUPLICATE KEY UPDATE
  `title` = VALUES(`title`),
  `description` = VALUES(`description`),
  `subsystem_target` = VALUES(`subsystem_target`);

-- ----------------------------------------------------------------------------
-- 3. MDT Dispatch Warning Overlays Table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_mdt_dispatch_warnings` (
  `warning_id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `warning_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `category` ENUM('speeding_anpr', 'statutory_amendment', 'reckless_endangerment', 'warrant_zone_breach') NOT NULL DEFAULT 'speeding_anpr',
  `severity` ENUM('low', 'medium', 'high', 'critical') NOT NULL DEFAULT 'medium',
  `title` VARCHAR(128) NOT NULL,
  `description` TEXT NOT NULL,
  `location_label` VARCHAR(128) NOT NULL,
  `coords` JSON NOT NULL,
  `target_plate` VARCHAR(16) NULL DEFAULT NULL,
  `target_model` VARCHAR(64) NULL DEFAULT NULL,
  `speed_recorded_mph` DECIMAL(6, 2) NULL DEFAULT NULL,
  `speed_limit_mph` DECIMAL(6, 2) NULL DEFAULT NULL,
  `target_citizen_id` VARCHAR(64) NULL DEFAULT NULL,
  `status` ENUM('active', 'acknowledged', 'cleared') NOT NULL DEFAULT 'active',
  `acknowledged_by` VARCHAR(64) NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `acknowledged_at` TIMESTAMP NULL DEFAULT NULL,
  INDEX `idx_warning_status` (`status`),
  INDEX `idx_warning_category` (`category`),
  INDEX `idx_warning_plate` (`target_plate`),
  INDEX `idx_warning_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- 4. Traffic Radar / ANPR Sensor Monitoring Zones Table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_mdt_traffic_radar_zones` (
  `zone_id` VARCHAR(64) NOT NULL PRIMARY KEY,
  `zone_name` VARCHAR(96) NOT NULL,
  `zone_type` ENUM('urban', 'highway', 'industrial', 'school_residential') NOT NULL DEFAULT 'urban',
  `coords` JSON NOT NULL,
  `radius` DECIMAL(8, 2) NOT NULL DEFAULT 120.00,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `nyx_mdt_traffic_radar_zones`
  (`zone_id`, `zone_name`, `zone_type`, `coords`, `radius`, `is_active`)
VALUES
  ('radar:vinewood_blvd', 'Vinewood Boulevard Speed Trap & ANPR', 'urban', '{"x": 312.4, "y": 182.5, "z": 103.8}', 150.00, 1),
  ('radar:del_perro_fwy', 'Del Perro Freeway Interstate Radar & ANPR', 'highway', '{"x": -1125.8, "y": -650.3, "z": 21.4}', 250.00, 1),
  ('radar:elysian_port', 'Elysian Island Logistics Corridor Radar', 'industrial', '{"x": 152.4, "y": -3005.2, "z": 5.9}', 180.00, 1),
  ('radar:rockford_hills', 'Rockford Hills Residential Calming Radar', 'school_residential', '{"x": -755.2, "y": 320.1, "z": 85.6}', 120.00, 1)
ON DUPLICATE KEY UPDATE
  `zone_name` = VALUES(`zone_name`),
  `zone_type` = VALUES(`zone_type`),
  `coords` = VALUES(`coords`);

-- ----------------------------------------------------------------------------
-- 5. MDT Statutory Overrides Audit Ledger
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_mdt_statutory_overrides` (
  `override_id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `law_id` VARCHAR(64) NOT NULL,
  `enacted_session_id` VARCHAR(64) NOT NULL,
  `statutory_field` VARCHAR(64) NOT NULL,
  `previous_value` DECIMAL(12, 4) NOT NULL,
  `new_value` DECIMAL(12, 4) NOT NULL,
  `synced_to_mdt` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_override_law` (`law_id`),
  INDEX `idx_override_session` (`enacted_session_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
