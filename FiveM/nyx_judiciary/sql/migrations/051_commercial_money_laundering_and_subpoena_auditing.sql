-- ============================================================================
-- Nyxframework Factions & Treasury Engine Migration
-- Migration: 051_commercial_money_laundering_and_subpoena_auditing.sql
-- Description: Commercial front business registers, dirty cash injection &
--              drip laundering engine, and judicial subpoena forensic auditing.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Extend nyx_judiciary_evidence with 'financial' Forensic Evidence Type
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_judiciary_evidence`
  MODIFY COLUMN `type` ENUM('casing', 'blood', 'fingerprint', 'swab', 'photo', 'document', 'ballistics', 'toolmark', 'weapon', 'financial') NOT NULL;

-- ----------------------------------------------------------------------------
-- 2. Commercial Front Business Cash Registers
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_factions_commercial_registers` (
  `register_id` VARCHAR(64) NOT NULL PRIMARY KEY,
  `faction_id` VARCHAR(32) NOT NULL,
  `label` VARCHAR(96) NOT NULL,
  `business_type` ENUM('retail', 'nightclub', 'carwash', 'restaurant', 'logistics', 'pawnshop', 'consulting') NOT NULL DEFAULT 'retail',
  `clean_cash_balance` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `dirty_cash_pool` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `total_washed` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `total_tax_paid` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `max_daily_laundering_cap` DECIMAL(15, 2) NOT NULL DEFAULT 50000.00,
  `daily_laundered_amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `last_cap_reset` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `wash_rate_pct` DECIMAL(5, 2) NOT NULL DEFAULT 80.00,
  `drip_amount_per_tick` DECIMAL(10, 2) NOT NULL DEFAULT 2500.00,
  `coords` JSON NULL DEFAULT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `is_frozen` TINYINT(1) NOT NULL DEFAULT 0,
  `frozen_by` VARCHAR(64) NULL DEFAULT NULL,
  `freeze_reason` VARCHAR(255) NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  INDEX `idx_cmr_faction` (`faction_id`),
  INDEX `idx_cmr_type` (`business_type`),
  INDEX `idx_cmr_status` (`is_active`, `is_frozen`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- 3. Commercial Dirty Cash Injections Registry
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_factions_laundering_injections` (
  `injection_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `injection_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `register_id` VARCHAR(64) NOT NULL,
  `faction_id` VARCHAR(32) NOT NULL,
  `citizen_id` VARCHAR(64) NOT NULL,
  `amount` DECIMAL(15, 2) NOT NULL,
  `source_note` VARCHAR(128) NULL,
  `status` ENUM('queued', 'processing', 'completed', 'intercepted') NOT NULL DEFAULT 'queued',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  INDEX `idx_inj_register` (`register_id`),
  INDEX `idx_inj_faction` (`faction_id`),
  INDEX `idx_inj_citizen` (`citizen_id`),
  INDEX `idx_inj_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- 4. Judicial Subpoena Forensic Audit Records
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_treasury_subpoena_audits` (
  `audit_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `subpoena_warrant_id` VARCHAR(64) NOT NULL,
  `target_type` ENUM('faction', 'register', 'citizen') NOT NULL DEFAULT 'faction',
  `target_id` VARCHAR(64) NOT NULL,
  `auditor_citizen_id` VARCHAR(64) NOT NULL,
  `anomaly_score` DECIMAL(5, 2) NOT NULL DEFAULT 0.00,
  `suspicion_level` ENUM('clean', 'low_risk', 'elevated', 'high_suspicion', 'blatant_anomalies') NOT NULL DEFAULT 'clean',
  `anomalies_detected` JSON NOT NULL,
  `total_volume_audited` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `cash_ratio_pct` DECIMAL(5, 2) NOT NULL DEFAULT 0.00,
  `forensic_report_sha256` VARCHAR(64) NOT NULL,
  `evidence_id` VARCHAR(64) NULL,
  `recommendation` VARCHAR(255) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  INDEX `idx_tsa_target` (`target_type`, `target_id`),
  INDEX `idx_tsa_auditor` (`auditor_citizen_id`),
  INDEX `idx_tsa_score` (`anomaly_score`),
  INDEX `idx_tsa_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- 5. Seed Canonical Front Enterprises, Treasury Accounts & Registers
-- ----------------------------------------------------------------------------
-- Ensure Clearing & Corporate Accounts exist in nyx_treasury_accounts
INSERT INTO `nyx_treasury_accounts` (`account_id`, `label`, `balance`, `type`) VALUES
('pool:laundering:clearing', 'Commercial Cash Clearing Transit Pool', 0.00, 'reserve'),
('faction:corp_vanilla_unicorn', 'Vanilla Unicorn Commercial Operating Account', 75000.00, 'department'),
('faction:priv_carwash_strawberry', 'Strawberry Carwash Operating Account', 25000.00, 'department'),
('faction:syn_pacific_consulting', 'Pacific Coast Consulting Operating Account', 150000.00, 'department')
ON DUPLICATE KEY UPDATE `balance` = VALUES(`balance`);

-- Seed Stashes into nyx_inventories
INSERT INTO `nyx_inventories` (`id`, `label`, `max_weight`, `max_slots`, `type`) VALUES
('stash:corp_vanilla_unicorn', 'Vanilla Unicorn Warehouse Vault', 2000000, 120, 'permanent'),
('stash:priv_carwash_strawberry', 'Strawberry Carwash Office Safe', 500000, 50, 'permanent'),
('stash:syn_pacific_consulting', 'Pacific Consulting Executive Safe', 1000000, 80, 'permanent')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

-- Seed Enterprises into nyx_factions_registry
INSERT INTO `nyx_factions_registry`
  (`faction_id`, `legal_name`, `charter_type`, `treasury_account_id`, `primary_stash_id`, `multisig_threshold_amount`, `multisig_required_signatures`, `is_active`)
VALUES
  ('corp_vanilla_unicorn', 'Vanilla Unicorn Entertainment Corp', 'corporation', 'faction:corp_vanilla_unicorn', 'stash:corp_vanilla_unicorn', 50000.00, 2, 1),
  ('priv_carwash_strawberry', 'Strawberry Quick-Shine Carwash', 'private_enterprise', 'faction:priv_carwash_strawberry', 'stash:priv_carwash_strawberry', 20000.00, 1, 1),
  ('syn_pacific_consulting', 'Pacific Coast Management Consulting', 'syndicate', 'faction:syn_pacific_consulting', 'stash:syn_pacific_consulting', 100000.00, 2, 1)
ON DUPLICATE KEY UPDATE `is_active` = VALUES(`is_active`);

-- Seed Commercial Front Cash Registers
INSERT INTO `nyx_factions_commercial_registers`
  (`register_id`, `faction_id`, `label`, `business_type`, `clean_cash_balance`, `dirty_cash_pool`, `max_daily_laundering_cap`, `wash_rate_pct`, `drip_amount_per_tick`, `coords`)
VALUES
  ('reg_unicorn_main', 'corp_vanilla_unicorn', 'Vanilla Unicorn VIP Lounge Register', 'nightclub', 12500.00, 0.00, 100000.00, 82.00, 5000.00, '{"x": 129.2, "y": -1284.5, "z": 29.3}'),
  ('reg_carwash_01', 'priv_carwash_strawberry', 'Strawberry Carwash Checkout Till', 'carwash', 4200.00, 0.00, 40000.00, 78.00, 2000.00, '{"x": -700.1, "y": -932.4, "z": 19.0}'),
  ('reg_consulting_01', 'syn_pacific_consulting', 'Pacific Consulting Accounts Desk', 'consulting', 35000.00, 0.00, 20000.00, 75.00, 1000.00, '{"x": -141.2, "y": -620.8, "z": 168.8}')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

SET FOREIGN_KEY_CHECKS = 1;
