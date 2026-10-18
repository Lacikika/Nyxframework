-- Nyxframework: nyx_inventory / nyx_interact
-- Migration: 025_spatial_grid_drops_and_durability_decay.sql
-- Description: Adds spatial grid cell indexing, offline decay timestamp tracking to inventories,
--              and creates immutable decay & repair audit telemetry ledger.

-- 1. Extend nyx_inventories with spatial grid cell key and offline decay tracking
ALTER TABLE `nyx_inventories`
  ADD COLUMN IF NOT EXISTS `grid_cell` VARCHAR(32) NULL AFTER `routing_bucket`,
  ADD COLUMN IF NOT EXISTS `last_decay_at` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `grid_cell`,
  ADD INDEX IF NOT EXISTS `idx_inv_grid_cell` (`grid_cell`);

-- 2. Create immutable decay and repair audit ledger
CREATE TABLE IF NOT EXISTS `nyx_inventory_decay_logs` (
  `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `inventory_id` VARCHAR(64) NOT NULL,
  `item_id` VARCHAR(64) NOT NULL,
  `event_type` VARCHAR(24) NOT NULL, -- 'decay', 'spoil', 'break', 'expire', 'repair', 'dissolve'
  `previous_durability` FLOAT NOT NULL,
  `new_durability` FLOAT NOT NULL,
  `delta_seconds` INT UNSIGNED NOT NULL,
  `container_type` VARCHAR(24) NOT NULL DEFAULT 'drop',
  `metadata_snapshot` JSON NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_decay_inv` (`inventory_id`),
  INDEX `idx_decay_item` (`item_id`),
  INDEX `idx_decay_event` (`event_type`),
  INDEX `idx_decay_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
