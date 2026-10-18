-- ============================================================================
-- Nyxframework: nyx_vehicles & nyx_logistics
-- Migration: 043_gas_station_reservoirs_and_bulk_fuel_hauling.sql
-- Description: Dynamic gas station underground reservoirs (reservoir:gas_*),
--              pump status tracking, finite fuel stocks, and bulk tanker logistics audits.
-- ============================================================================

-- 1. Gas Station Facilities & Underground Reservoirs
CREATE TABLE IF NOT EXISTS `nyx_vehicles_gas_stations` (
  `station_id` VARCHAR(32) NOT NULL PRIMARY KEY,
  `name` VARCHAR(64) NOT NULL,
  `brand` VARCHAR(32) NOT NULL DEFAULT 'RON',
  `zone_id` VARCHAR(32) NOT NULL DEFAULT 'zone_ls_metro',
  `reservoir_stash_id` VARCHAR(64) NOT NULL UNIQUE,
  `coords` JSON NOT NULL,
  `fuel_capacity` FLOAT NOT NULL DEFAULT 10000.0,
  `fuel_stock` FLOAT NOT NULL DEFAULT 5000.0,
  `fuel_price_per_liter` DECIMAL(10,2) NOT NULL DEFAULT 1.85,
  `critical_threshold` FLOAT NOT NULL DEFAULT 1000.0,
  `degraded_threshold` FLOAT NOT NULL DEFAULT 2500.0,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `last_emergency_contract_at` TIMESTAMP NULL DEFAULT NULL,
  `last_delivery_at` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_zone` (`zone_id`),
  INDEX `idx_stock` (`fuel_stock`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Immutable Audit Log for Fuel Refueling and Bulk Logistics Deliveries
CREATE TABLE IF NOT EXISTS `nyx_vehicles_fuel_audit` (
  `audit_id` INT AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `station_id` VARCHAR(32) NOT NULL,
  `reservoir_stash_id` VARCHAR(64) NOT NULL,
  `action` ENUM('REFUELED_VEHICLE', 'BULK_DELIVERED', 'RESTOCKED_MANUAL', 'SHORTAGE_ALERT', 'CONTRACT_TRIGGERED', 'PRICE_ADJUSTED') NOT NULL,
  `liters` FLOAT NOT NULL,
  `cost` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `price_per_liter` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `remaining_stock` FLOAT NOT NULL,
  `vehicle_plate` VARCHAR(16) NULL,
  `citizen_id` VARCHAR(64) NULL,
  `contract_id` INT NULL,
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_station_audit` (`station_id`),
  INDEX `idx_reservoir_audit` (`reservoir_stash_id`),
  INDEX `idx_action_audit` (`action`),
  INDEX `idx_vehicle_audit` (`vehicle_plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Register Underground Tank Containers in nyx_inventories
INSERT INTO `nyx_inventories` (`id`, `type`, `max_weight`, `max_slots`, `coords`)
VALUES
  ('reservoir:gas_legion', 'reservoir', 20000000, 50, '{"x": 265.0, "y": -1262.0, "z": 29.3}'),
  ('reservoir:gas_davis', 'reservoir', 20000000, 50, '{"x": -70.0, "y": -1761.5, "z": 29.5}'),
  ('reservoir:gas_sandy_shores', 'reservoir', 15000000, 50, '{"x": 1966.5, "y": 3741.0, "z": 32.3}'),
  ('reservoir:gas_paleto', 'reservoir', 15000000, 50, '{"x": 179.8, "y": 6602.8, "z": 31.9}'),
  ('reservoir:gas_rockford', 'reservoir', 20000000, 50, '{"x": -2096.5, "y": -320.2, "z": 13.2}'),
  ('stash:refinery_fuel', 'stash', 50000000, 100, '{"x": 2736.0, "y": 1420.0, "z": 24.5}')
ON DUPLICATE KEY UPDATE `type` = VALUES(`type`), `coords` = VALUES(`coords`);

-- 4. Seed Canonical Gas Station Facilities
INSERT INTO `nyx_vehicles_gas_stations`
  (`station_id`, `name`, `brand`, `zone_id`, `reservoir_stash_id`, `coords`, `fuel_capacity`, `fuel_stock`, `fuel_price_per_liter`, `critical_threshold`, `degraded_threshold`, `is_active`)
VALUES
  ('gas_legion', 'Legion Square Petrol', 'RON', 'zone_ls_metro', 'reservoir:gas_legion', '{"x": 265.0, "y": -1262.0, "z": 29.3}', 10000.0, 7500.0, 1.85, 1000.0, 2500.0, 1),
  ('gas_davis', 'Davis LTD Gasoline', 'LTD', 'zone_ls_metro', 'reservoir:gas_davis', '{"x": -70.0, "y": -1761.5, "z": 29.5}', 10000.0, 6000.0, 1.80, 1000.0, 2500.0, 1),
  ('gas_sandy_shores', 'Sandy Shores 24/7 Gas', 'Globe Oil', 'zone_sandy_shores', 'reservoir:gas_sandy_shores', '{"x": 1966.5, "y": 3741.0, "z": 32.3}', 8000.0, 4000.0, 2.10, 800.0, 2000.0, 1),
  ('gas_paleto', 'Paleto Bay Xero Gas', 'Xero Gas', 'zone_paleto_bay', 'reservoir:gas_paleto', '{"x": 179.8, "y": 6602.8, "z": 31.9}', 8000.0, 4500.0, 2.15, 800.0, 2000.0, 1),
  ('gas_rockford', 'Rockford Hills RON Express', 'RON', 'zone_ls_metro', 'reservoir:gas_rockford', '{"x": -2096.5, "y": -320.2, "z": 13.2}', 12000.0, 8000.0, 1.95, 1200.0, 3000.0, 1)
ON DUPLICATE KEY UPDATE `fuel_stock` = VALUES(`fuel_stock`), `fuel_price_per_liter` = VALUES(`fuel_price_per_liter`);

-- 5. Seed Initial Bulk Fuel Cargo at El Burro Oil Refinery
INSERT INTO `nyx_inventory_items` (`item_uuid`, `inventory_id`, `item_id`, `slot`, `amount`, `metadata`)
VALUES
  (UUID(), 'stash:refinery_fuel', 'industrial_fuel', 1, 200, '{"label": "Refined Bulk Diesel Drum (50L)"}'),
  (UUID(), 'stash:refinery_fuel', 'bulk_fuel_tank', 2, 50, '{"label": "Commercial Tanker Fuel Pod (500L)"}')
ON DUPLICATE KEY UPDATE `amount` = VALUES(`amount`);
