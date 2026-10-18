-- ============================================================================
-- Nyxframework: nyx_vehicles
-- Migration: 009_vehicles_persistence.sql
-- Description: Authoritative vehicle persistence, damage snapshots, fuel tracking,
--              and dynamic physical/digital key registries.
-- ============================================================================

-- Registered player and organization owned vehicles
CREATE TABLE IF NOT EXISTS `nyx_vehicles_owned` (
  `vin` VARCHAR(32) PRIMARY KEY,
  `plate` VARCHAR(12) NOT NULL UNIQUE,
  `owner_citizen_id` VARCHAR(16) NULL,
  `faction_id` VARCHAR(32) NULL,
  `model_name` VARCHAR(48) NOT NULL,
  `model_hash` INT NOT NULL,
  `garage_id` VARCHAR(32) NOT NULL DEFAULT 'legion_square',
  `storage_state` ENUM('stored', 'out', 'impounded', 'destroyed') DEFAULT 'stored',
  `fuel_level` DECIMAL(6, 2) NOT NULL DEFAULT 65.00,
  `lock_state` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `last_coords` JSON NULL,
  `condition_data` JSON NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_owner` (`owner_citizen_id`),
  INDEX `idx_plate` (`plate`),
  INDEX `idx_storage` (`storage_state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Vehicle key bindings and authorized driver permissions
CREATE TABLE IF NOT EXISTS `nyx_vehicles_keys` (
  `key_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `vin` VARCHAR(32) NOT NULL,
  `plate` VARCHAR(12) NOT NULL,
  `holder_citizen_id` VARCHAR(16) NOT NULL,
  `key_type` ENUM('master', 'copy', 'fob', 'valet') DEFAULT 'master',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_holder_vehicle` (`vin`, `holder_citizen_id`),
  FOREIGN KEY (`vin`) REFERENCES `nyx_vehicles_owned`(`vin`) ON DELETE CASCADE,
  INDEX `idx_key_holder` (`holder_citizen_id`),
  INDEX `idx_key_vin` (`vin`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
