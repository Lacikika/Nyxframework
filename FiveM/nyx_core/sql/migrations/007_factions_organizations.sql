-- ============================================================================
-- Nyxframework: nyx_factions
-- Migration: 007_factions_organizations.sql
-- Description: Autonomous player organizations, granular RBAC membership,
--              multi-sig treasury queue, and commercial fleet management.
-- ============================================================================

-- Registered player organizations and enterprises
CREATE TABLE IF NOT EXISTS `nyx_factions_registry` (
  `faction_id` VARCHAR(32) PRIMARY KEY,
  `legal_name` VARCHAR(96) NOT NULL UNIQUE,
  `charter_type` ENUM('corporation', 'cooperative', 'trade_union', 'private_enterprise', 'syndicate') NOT NULL,
  `treasury_account_id` VARCHAR(64) NOT NULL UNIQUE,
  `primary_stash_id` VARCHAR(64) NOT NULL UNIQUE,
  `multisig_threshold_amount` DECIMAL(15, 2) NOT NULL DEFAULT 50000.00,
  `multisig_required_signatures` TINYINT UNSIGNED NOT NULL DEFAULT 2,
  `is_active` TINYINT(1) DEFAULT 1,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_charter_type` (`charter_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Organization membership and dynamic permission matrices
CREATE TABLE IF NOT EXISTS `nyx_factions_members` (
  `membership_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `faction_id` VARCHAR(32) NOT NULL,
  `citizen_id` VARCHAR(16) NOT NULL,
  `role_title` VARCHAR(48) NOT NULL DEFAULT 'Associate',
  `permission_nodes` JSON NOT NULL,
  `equity_shares` DECIMAL(5, 2) NOT NULL DEFAULT 0.00,
  `wage_hourly` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `hired_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_char_faction` (`faction_id`, `citizen_id`),
  FOREIGN KEY (`faction_id`) REFERENCES `nyx_factions_registry`(`faction_id`) ON DELETE CASCADE,
  INDEX `idx_member_lookup` (`citizen_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Multi-Signature withdrawal queue
CREATE TABLE IF NOT EXISTS `nyx_factions_multisig_queue` (
  `request_id` VARCHAR(36) PRIMARY KEY,
  `faction_id` VARCHAR(32) NOT NULL,
  `initiated_by` VARCHAR(16) NOT NULL,
  `target_account` VARCHAR(64) NOT NULL,
  `amount` DECIMAL(15, 2) NOT NULL,
  `reason` VARCHAR(255) NOT NULL,
  `required_signatures` TINYINT UNSIGNED NOT NULL,
  `current_signatures` JSON NOT NULL,
  `status` ENUM('pending', 'approved', 'rejected', 'expired') DEFAULT 'pending',
  `expires_at` TIMESTAMP NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`faction_id`) REFERENCES `nyx_factions_registry`(`faction_id`) ON DELETE CASCADE,
  INDEX `idx_multisig_status` (`faction_id`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Registered commercial fleet assets
CREATE TABLE IF NOT EXISTS `nyx_factions_fleet` (
  `vin` VARCHAR(32) PRIMARY KEY,
  `plate` VARCHAR(12) NOT NULL UNIQUE,
  `faction_id` VARCHAR(32) NOT NULL,
  `model_hash` INT NOT NULL,
  `parking_depot_id` VARCHAR(32) NOT NULL,
  `storage_state` ENUM('stored', 'active', 'impounded') DEFAULT 'stored',
  `condition_data` JSON NOT NULL,
  FOREIGN KEY (`faction_id`) REFERENCES `nyx_factions_registry`(`faction_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
