-- ============================================================================
-- Nyxframework Logistics & Warehousing Schema Update
-- Migration: 038_warehouse_matrix_and_elastic_market_monitor.sql
-- Description: Interactive 3D shelf matrices, slot temperature zones,
--              hauler route dispatching, and regional arbitrage tracking.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Extend Physical Shelf Nodes with Slot Status, Temperature & Reservation
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_logistics_shelf_nodes`
  ADD COLUMN IF NOT EXISTS `slot_status` VARCHAR(20) NOT NULL DEFAULT 'available' AFTER `occupied_drop_id`,
  ADD COLUMN IF NOT EXISTS `temperature_zone` VARCHAR(20) NOT NULL DEFAULT 'ambient' AFTER `slot_status`,
  ADD COLUMN IF NOT EXISTS `reserved_until` TIMESTAMP NULL DEFAULT NULL AFTER `temperature_zone`,
  ADD COLUMN IF NOT EXISTS `reserved_by_citizen_id` VARCHAR(64) NULL DEFAULT NULL AFTER `reserved_until`,
  ADD INDEX IF NOT EXISTS `idx_slot_status` (`slot_status`),
  ADD INDEX IF NOT EXISTS `idx_temp_zone` (`temperature_zone`);

-- ----------------------------------------------------------------------------
-- 2. Hauler Route Dispatches & Regional Arbitrage Deliveries
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_logistics_hauler_dispatches` (
  `dispatch_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `hauler_citizen_id` VARCHAR(64) NOT NULL,
  `origin_warehouse_id` VARCHAR(64) NOT NULL,
  `destination_zone_id` VARCHAR(32) NOT NULL,
  `item_id` VARCHAR(64) NOT NULL,
  `units` INT UNSIGNED NOT NULL DEFAULT 1,
  `unit_cost` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `target_price` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `projected_profit` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `fuel_surcharge` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `status` VARCHAR(20) NOT NULL DEFAULT 'claimed' CHECK (`status` IN ('claimed', 'loaded', 'completed', 'abandoned')),
  `claimed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed_at` TIMESTAMP NULL DEFAULT NULL,
  INDEX `idx_hauler_status` (`hauler_citizen_id`, `status`),
  INDEX `idx_dispatch_route` (`origin_warehouse_id`, `destination_zone_id`),
  INDEX `idx_dispatch_item` (`item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;
