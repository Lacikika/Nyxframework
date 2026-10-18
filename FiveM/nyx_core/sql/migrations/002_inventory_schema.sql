-- Nyxframework Inventory & Storage Schema
-- Migration: 002_inventory_schema.sql

-- 1. Container definitions and maximum constraints
CREATE TABLE IF NOT EXISTS `nyx_inventories` (
  `id` VARCHAR(64) PRIMARY KEY,
  `type` VARCHAR(24) NOT NULL,
  `max_weight` INT UNSIGNED NOT NULL DEFAULT 30000,
  `max_slots` SMALLINT UNSIGNED NOT NULL DEFAULT 40,
  `coords` JSON NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_inv_type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Discrete items contained within an inventory
CREATE TABLE IF NOT EXISTS `nyx_inventory_items` (
  `item_uuid` VARCHAR(36) PRIMARY KEY,
  `inventory_id` VARCHAR(64) NOT NULL,
  `item_id` VARCHAR(64) NOT NULL,
  `slot` SMALLINT UNSIGNED NOT NULL,
  `amount` INT UNSIGNED NOT NULL DEFAULT 1,
  `metadata` JSON NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`inventory_id`) REFERENCES `nyx_inventories`(`id`) ON DELETE CASCADE,
  UNIQUE KEY `unique_slot_per_inv` (`inventory_id`, `slot`),
  INDEX `idx_item_id` (`item_id`),
  INDEX `idx_inv_slot` (`inventory_id`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
