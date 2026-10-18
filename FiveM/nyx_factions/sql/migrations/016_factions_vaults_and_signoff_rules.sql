-- ============================================================================
-- Nyxframework Factions Engine Database Migration
-- File: 016_factions_vaults_and_signoff_rules.sql
-- Description: Multi-Signature Corporate Treasury Vaults, Dynamic Tiered
--              Sign-Off Rules, Timelock Escrow, and Immutable Audit Trails.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Corporate Treasury Sub-Vaults & Designated Accounts
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_factions_vaults` (
  `vault_id` VARCHAR(64) PRIMARY KEY,
  `faction_id` VARCHAR(32) NOT NULL,
  `vault_label` VARCHAR(64) NOT NULL,
  `account_id` VARCHAR(64) NOT NULL UNIQUE,
  `is_primary` TINYINT(1) NOT NULL DEFAULT 0,
  `daily_limit` DECIMAL(15, 2) NOT NULL DEFAULT 100000.00,
  `daily_withdrawn` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `last_limit_reset` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `is_frozen` TINYINT(1) NOT NULL DEFAULT 0,
  `frozen_by` VARCHAR(16) NULL DEFAULT NULL,
  `freeze_reason` VARCHAR(255) NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`faction_id`) REFERENCES `nyx_factions_registry`(`faction_id`) ON DELETE CASCADE,
  INDEX `idx_vault_faction` (`faction_id`),
  INDEX `idx_vault_primary` (`faction_id`, `is_primary`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 2. Granular Corporate Sign-Off Rules (Tiered Quorum, Roles & Timelocks)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_factions_signoff_rules` (
  `rule_id` VARCHAR(36) PRIMARY KEY,
  `faction_id` VARCHAR(32) NOT NULL,
  `vault_id` VARCHAR(64) NULL DEFAULT NULL,
  `rule_name` VARCHAR(64) NOT NULL,
  `min_amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `max_amount` DECIMAL(15, 2) NULL DEFAULT NULL,
  `required_signatures` TINYINT UNSIGNED NOT NULL DEFAULT 2,
  `required_roles` JSON NULL DEFAULT NULL,
  `timelock_seconds` INT UNSIGNED NOT NULL DEFAULT 0,
  `priority` INT NOT NULL DEFAULT 0,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`faction_id`) REFERENCES `nyx_factions_registry`(`faction_id`) ON DELETE CASCADE,
  INDEX `idx_rule_lookup` (`faction_id`, `vault_id`, `is_active`, `priority` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 3. Enhance Multi-Sig Queue with Vault Binding, Signer Metadata & Timelocks
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_factions_multisig_queue`
  ADD COLUMN IF NOT EXISTS `vault_id` VARCHAR(64) NULL AFTER `faction_id`,
  ADD COLUMN IF NOT EXISTS `rule_id` VARCHAR(36) NULL AFTER `vault_id`,
  ADD COLUMN IF NOT EXISTS `signature_details` JSON NULL AFTER `current_signatures`,
  ADD COLUMN IF NOT EXISTS `timelock_until` TIMESTAMP NULL DEFAULT NULL AFTER `expires_at`,
  ADD COLUMN IF NOT EXISTS `cancelled_by` VARCHAR(16) NULL AFTER `status`,
  ADD COLUMN IF NOT EXISTS `cancellation_reason` VARCHAR(255) NULL AFTER `cancelled_by`,
  MODIFY COLUMN `status` ENUM('pending', 'approved', 'rejected', 'expired', 'timelocked', 'cancelled') DEFAULT 'pending',
  ADD INDEX IF NOT EXISTS `idx_multisig_vault` (`vault_id`);

-- ----------------------------------------------------------------------------
-- 4. Immutable Multi-Signature Audit Trail
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_factions_multisig_audit` (
  `audit_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `request_id` VARCHAR(36) NOT NULL,
  `faction_id` VARCHAR(32) NOT NULL,
  `actor_citizen_id` VARCHAR(16) NOT NULL,
  `action` VARCHAR(32) NOT NULL,
  `details` JSON NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_audit_req` (`request_id`),
  INDEX `idx_audit_faction` (`faction_id`, `created_at` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;
