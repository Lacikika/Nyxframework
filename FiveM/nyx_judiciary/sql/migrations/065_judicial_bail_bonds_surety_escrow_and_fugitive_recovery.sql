-- ============================================================================
-- Nyxframework: nyx_judiciary & nyx_treasury
-- Migration: 065_judicial_bail_bonds_surety_escrow_and_fugitive_recovery.sql
-- Description: Pre-trial judicial bail bonds, commercial surety escrow pools,
--              court appearance verification, exoneration splits, forfeiture,
--              and automated fugitive recovery warrants with bounty rewards.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Create judicial bail bonds registry
CREATE TABLE IF NOT EXISTS `nyx_judiciary_bail_bonds` (
  `bond_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `bond_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `docket_id` VARCHAR(32) NOT NULL,
  `defendant_citizen_id` VARCHAR(16) NOT NULL,
  `poster_citizen_id` VARCHAR(16) NOT NULL,
  `bond_type` ENUM('cash', 'surety', 'recognizance') NOT NULL DEFAULT 'cash',
  `bail_amount` DECIMAL(15, 2) NOT NULL,
  `collateral_amount` DECIMAL(15, 2) NOT NULL,
  `bondsman_fee` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `clerk_admin_fee` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `status` ENUM('posted', 'exonerated', 'forfeited', 'revoked') NOT NULL DEFAULT 'posted',
  `escrow_account_id` VARCHAR(64) NOT NULL DEFAULT 'gov:escrow:bail',
  `treasury_tx_uuid` VARCHAR(36) NULL,
  `conditions` JSON NOT NULL,
  `court_appearance_verified` TINYINT(1) NOT NULL DEFAULT 0,
  `bounty_claimed` TINYINT(1) NOT NULL DEFAULT 0,
  `bounty_hunter_citizen_id` VARCHAR(16) NULL,
  `posted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `resolved_at` TIMESTAMP NULL,
  `notes` VARCHAR(255) NULL,
  INDEX `idx_bail_docket` (`docket_id`),
  INDEX `idx_bail_defendant` (`defendant_citizen_id`),
  INDEX `idx_bail_poster` (`poster_citizen_id`),
  INDEX `idx_bail_status` (`status`),
  INDEX `idx_bail_created` (`posted_at` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Create immutable judicial bail audit ledger
CREATE TABLE IF NOT EXISTS `nyx_judiciary_bail_audits` (
  `audit_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `bond_id` BIGINT NOT NULL,
  `docket_id` VARCHAR(32) NOT NULL,
  `citizen_id` VARCHAR(16) NOT NULL,
  `action` ENUM('BAIL_SCHEDULE_SET', 'BAIL_POSTED', 'CONDITIONS_UPDATED', 'APPEARANCE_CHECKED', 'BAIL_EXONERATED', 'BAIL_FORFEITED_FTA', 'FUGITIVE_WARRANT_ISSUED', 'FUGITIVE_APPREHENDED', 'BOUNTY_DISBURSED') NOT NULL,
  `amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `treasury_tx_uuid` VARCHAR(36) NULL,
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_bail_audit_bond` (`bond_id`),
  INDEX `idx_bail_audit_docket` (`docket_id`),
  INDEX `idx_bail_audit_citizen` (`citizen_id`),
  INDEX `idx_bail_audit_action` (`action`),
  INDEX `idx_bail_audit_created` (`created_at` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Extend nyx_judiciary_dockets with bail schedule attributes
ALTER TABLE `nyx_judiciary_dockets`
  ADD COLUMN IF NOT EXISTS `bail_schedule_amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00 AFTER `case_type`,
  ADD COLUMN IF NOT EXISTS `bail_status` ENUM('not_set', 'eligible', 'posted', 'remand_no_bail', 'exonerated', 'forfeited') NOT NULL DEFAULT 'not_set' AFTER `bail_schedule_amount`,
  ADD COLUMN IF NOT EXISTS `bail_bond_id` BIGINT NULL AFTER `bail_status`;

-- 4. Seed municipal bail escrow reserve account in nyx_treasury_accounts
INSERT INTO `nyx_treasury_accounts`
  (`account_id`, `label`, `balance`, `type`, `signatories_required`)
VALUES
  ('gov:escrow:bail', 'Municipal Court Judicial Bail Escrow Pool', 0.00, 'reserve', 1)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

-- 5. Seed default bail schedules for existing open felony and misdemeanor dockets
UPDATE `nyx_judiciary_dockets`
SET `bail_schedule_amount` = 2500.00, `bail_status` = 'eligible'
WHERE `case_type` = 'criminal_misdemeanor' AND `status` IN ('filed', 'scheduled');

UPDATE `nyx_judiciary_dockets`
SET `bail_schedule_amount` = 50000.00, `bail_status` = 'eligible'
WHERE `case_type` = 'criminal_felony' AND `status` IN ('filed', 'scheduled');

SET FOREIGN_KEY_CHECKS = 1;
