-- ============================================================================
-- Nyxframework Factions & Treasury Engine Migration
-- Migration: 053_armored_cash_transit_and_banking_freight.sql
-- Description: Retail store cash register excess accumulation thresholds,
--              armored cash box container generation, high-security municipal
--              bank vault deposits with double-entry clearing and courier rewards.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Extend nyx_factions_commercial_registers with Transit Threshold Attributes
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_factions_commercial_registers`
  ADD COLUMN IF NOT EXISTS `transit_threshold` DECIMAL(15, 2) NOT NULL DEFAULT 10000.00 AFTER `dirty_cash_pool`,
  ADD COLUMN IF NOT EXISTS `pending_transit_box_id` VARCHAR(36) NULL DEFAULT NULL AFTER `transit_threshold`;

-- ----------------------------------------------------------------------------
-- 2. Central Municipal Bank Vaults Registry
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_treasury_bank_vaults` (
  `vault_id` VARCHAR(64) NOT NULL PRIMARY KEY,
  `label` VARCHAR(96) NOT NULL,
  `treasury_account_id` VARCHAR(64) NOT NULL DEFAULT 'gov:city:master',
  `coords` JSON NOT NULL,
  `security_level` ENUM('maximum', 'high', 'standard') NOT NULL DEFAULT 'maximum',
  `deposit_fee_pct` DECIMAL(5, 2) NOT NULL DEFAULT 1.00,
  `courier_reward_pct` DECIMAL(5, 2) NOT NULL DEFAULT 2.00,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  INDEX `idx_tbv_active` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 3. Armored Cash Transit Boxes Registry
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_treasury_cash_transit_boxes` (
  `box_id` VARCHAR(36) NOT NULL PRIMARY KEY,
  `box_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `register_id` VARCHAR(64) NOT NULL,
  `faction_id` VARCHAR(32) NOT NULL,
  `carrier_citizen_id` VARCHAR(64) NULL DEFAULT NULL,
  `cash_amount` DECIMAL(15, 2) NOT NULL,
  `seal_serial` VARCHAR(32) NOT NULL,
  `tamper_state` ENUM('sealed', 'tampered', 'breached') NOT NULL DEFAULT 'sealed',
  `status` ENUM('staged', 'in_transit', 'deposited', 'intercepted', 'lost') NOT NULL DEFAULT 'staged',
  `origin_coords` JSON NULL DEFAULT NULL,
  `destination_vault_id` VARCHAR(64) NOT NULL DEFAULT 'vault:pacific_standard',
  `dispatched_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `deposited_at` TIMESTAMP NULL DEFAULT NULL,
  `deposited_by_citizen_id` VARCHAR(64) NULL DEFAULT NULL,
  `treasury_tx_id` VARCHAR(64) NULL DEFAULT NULL,
  `breached_at` TIMESTAMP NULL DEFAULT NULL,
  `breached_by_citizen_id` VARCHAR(64) NULL DEFAULT NULL,
  `evidence_id` VARCHAR(64) NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  INDEX `idx_box_reg` (`register_id`),
  INDEX `idx_box_faction` (`faction_id`),
  INDEX `idx_box_carrier` (`carrier_citizen_id`),
  INDEX `idx_box_status` (`status`),
  INDEX `idx_box_vault` (`destination_vault_id`),
  FOREIGN KEY (`destination_vault_id`) REFERENCES `nyx_treasury_bank_vaults`(`vault_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 4. Immutable Armored Cash Transit Audit Trail
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_treasury_cash_transit_audits` (
  `audit_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `box_id` VARCHAR(36) NOT NULL,
  `action` ENUM('BOX_CREATED', 'TRANSIT_START', 'DEPOSITED_VAULT', 'BOX_BREACHED', 'TAMPER_DETECTED') NOT NULL,
  `actor_citizen_id` VARCHAR(64) NOT NULL,
  `cash_amount` DECIMAL(15, 2) NOT NULL,
  `faction_id` VARCHAR(32) NOT NULL,
  `vault_id` VARCHAR(64) NULL DEFAULT NULL,
  `notes` VARCHAR(255) NULL DEFAULT NULL,
  `coords` JSON NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  INDEX `idx_tca_box` (`box_id`),
  INDEX `idx_tca_action` (`action`),
  INDEX `idx_tca_actor` (`actor_citizen_id`),
  INDEX `idx_tca_faction` (`faction_id`),
  INDEX `idx_tca_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 5. Seed Canonical Municipal Bank Vaults & Clearing Account
-- ----------------------------------------------------------------------------
INSERT INTO `nyx_treasury_accounts` (`account_id`, `label`, `balance`, `type`) VALUES
('pool:cash_transit:clearing', 'Armored Cash-In-Transit Clearing Pool', 0.00, 'reserve')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

INSERT INTO `nyx_treasury_bank_vaults`
  (`vault_id`, `label`, `treasury_account_id`, `coords`, `security_level`, `deposit_fee_pct`, `courier_reward_pct`, `is_active`)
VALUES
  ('vault:pacific_standard', 'Pacific Standard Municipal Central Vault', 'gov:city:master', '{"x": 255.2, "y": 217.4, "z": 101.9}', 'maximum', 1.00, 2.00, 1),
  ('vault:blaine_county', 'Blaine County Savings Vault', 'gov:city:master', '{"x": -111.4, "y": 6465.1, "z": 31.6}', 'high', 1.00, 2.50, 1),
  ('vault:legion_square', 'Legion Square Commercial Reserve Vault', 'gov:city:master', '{"x": 150.1, "y": -1040.5, "z": 29.4}', 'maximum', 1.00, 2.00, 1)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

SET FOREIGN_KEY_CHECKS = 1;
