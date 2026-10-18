-- Nyxframework: nyx_logistics / nyx_services
-- Migration: 026_logistics_physical_pallets_and_power_assembly.sql
-- Description: Physical heavy freight pallet persistence, vehicle attachment registry,
--              power grid substation linking, metered facility consumption, and output modes.

-- 1. Create table for physical heavy freight pallets
CREATE TABLE IF NOT EXISTS `nyx_logistics_pallets` (
  `pallet_id` VARCHAR(64) PRIMARY KEY,
  `inventory_id` VARCHAR(64) NOT NULL UNIQUE,
  `label` VARCHAR(128) NOT NULL DEFAULT 'Industrial Freight Pallet',
  `model` VARCHAR(64) NOT NULL DEFAULT 'prop_boxpile_06a',
  `coords` JSON NULL,
  `heading` FLOAT DEFAULT 0.0,
  `routing_bucket` INT NOT NULL DEFAULT 0,
  `attached_vehicle_plate` VARCHAR(16) NULL,
  `attached_slot_index` INT DEFAULT 0,
  `attached_offset` JSON NULL,
  `shelf_node_id` VARCHAR(64) NULL,
  `is_sealed` TINYINT(1) DEFAULT 0,
  `created_by_citizen_id` VARCHAR(64) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_pallet_inv` (`inventory_id`),
  INDEX `idx_pallet_vehicle` (`attached_vehicle_plate`),
  INDEX `idx_pallet_shelf` (`shelf_node_id`),
  INDEX `idx_pallet_bucket` (`routing_bucket`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Create immutable audit ledger for pallet movements and operations
CREATE TABLE IF NOT EXISTS `nyx_logistics_pallet_logs` (
  `log_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `pallet_id` VARCHAR(64) NOT NULL,
  `action` VARCHAR(32) NOT NULL,
  `actor_citizen_id` VARCHAR(64) NULL,
  `vehicle_plate` VARCHAR(16) NULL,
  `coords` JSON NULL,
  `details` JSON NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_plog_pallet` (`pallet_id`),
  INDEX `idx_plog_action` (`action`),
  INDEX `idx_plog_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Extend nyx_logistics_facilities with power grid telemetry and pallet dock
ALTER TABLE `nyx_logistics_facilities`
  ADD COLUMN IF NOT EXISTS `coords` JSON NULL AFTER `type`,
  ADD COLUMN IF NOT EXISTS `power_status` VARCHAR(24) NOT NULL DEFAULT 'online' AFTER `power_grid_id`,
  ADD COLUMN IF NOT EXISTS `power_consumption_kw` DECIMAL(8, 2) NOT NULL DEFAULT 0.00 AFTER `power_status`,
  ADD COLUMN IF NOT EXISTS `total_energy_consumed_kwh` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 AFTER `power_consumption_kw`,
  ADD COLUMN IF NOT EXISTS `pallet_dock_coords` JSON NULL AFTER `total_energy_consumed_kwh`,
  ADD COLUMN IF NOT EXISTS `pallet_dock_heading` FLOAT DEFAULT 0.0 AFTER `pallet_dock_coords`,
  ADD COLUMN IF NOT EXISTS `output_mode` VARCHAR(16) NOT NULL DEFAULT 'inventory' AFTER `pallet_dock_heading`,
  ADD COLUMN IF NOT EXISTS `last_power_tick` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `output_mode`;

-- 4. Update seed facilities with real substation IDs, world coords, and pallet loading docks
UPDATE `nyx_logistics_facilities`
SET
  `power_grid_id` = 'grid_sandy_shores',
  `coords` = '{"x": 2742.0, "y": 1505.0, "z": 24.5}',
  `pallet_dock_coords` = '{"x": 2746.0, "y": 1502.0, "z": 24.5}',
  `pallet_dock_heading` = 90.0,
  `power_status` = 'online'
WHERE `facility_id` = 'fac_sandy_refinery';

UPDATE `nyx_logistics_facilities`
SET
  `power_grid_id` = 'grid_port_ls',
  `coords` = '{"x": 1085.0, "y": -2002.0, "z": 31.5}',
  `pallet_dock_coords` = '{"x": 1089.0, "y": -2006.0, "z": 31.5}',
  `pallet_dock_heading` = 180.0,
  `power_status` = 'online'
WHERE `facility_id` = 'fac_davis_assembly';

-- 5. Insert additional industrial manufacturing facilities
INSERT IGNORE INTO `nyx_logistics_facilities`
  (`facility_id`, `type`, `coords`, `input_inventory_id`, `output_inventory_id`, `power_grid_id`, `power_status`, `pallet_dock_coords`, `pallet_dock_heading`, `output_mode`)
VALUES
  ('fac_cypress_chemical', 'chemical', '{"x": 920.0, "y": -2150.0, "z": 30.5}', 'stash:cypress_chem_in', 'stash:cypress_chem_out', 'grid_port_ls', 'online', '{"x": 923.0, "y": -2154.0, "z": 30.5}', 270.0, 'inventory'),
  ('fac_paleto_smelter', 'smelter', '{"x": 160.0, "y": 6620.0, "z": 31.5}', 'stash:paleto_smelt_in', 'stash:paleto_smelt_out', 'grid_paleto', 'online', '{"x": 164.0, "y": 6624.0, "z": 31.5}', 45.0, 'pallet');
