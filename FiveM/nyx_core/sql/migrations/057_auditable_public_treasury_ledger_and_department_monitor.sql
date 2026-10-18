-- ============================================================================
-- Nyxframework: nyx_treasury & nyx_ui
-- Migration: 057_auditable_public_treasury_ledger_and_department_monitor.sql
-- Description: Auditable Public Treasury Ledger, Open Municipal Balance Sheets,
--              Automated Revenue Sweep Splits Across Statutory Pillars (Emergency
--              Services, Infrastructure, Social Dividend), and Sweep Audit Ledger.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Ensure Social Dividend & Civic Grants Reserve Account Exists
-- ----------------------------------------------------------------------------
INSERT IGNORE INTO `nyx_treasury_accounts` (`account_id`, `label`, `balance`, `type`, `circuit_exempt`) VALUES
('gov:dept:dividend', 'Citizen Social Dividend & Small Grants Reserve', 250000.00, 'grant_pool', 1);

-- ----------------------------------------------------------------------------
-- 2. Extend Allocations Schema with Department Label, Statutory Category, & Auditing
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_treasury_allocations`
  ADD COLUMN IF NOT EXISTS `department_label` VARCHAR(96) NULL AFTER `target_department`,
  ADD COLUMN IF NOT EXISTS `allocation_category` ENUM('emergency_services', 'infrastructure', 'social_dividend', 'general') NOT NULL DEFAULT 'general' AFTER `department_label`,
  ADD COLUMN IF NOT EXISTS `last_allocated_amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00 AFTER `ratified_by_bill_id`,
  ADD COLUMN IF NOT EXISTS `last_allocated_at` TIMESTAMP NULL AFTER `last_allocated_amount`;

-- ----------------------------------------------------------------------------
-- 3. Synchronize Statutory Allocation Schedules (Tervek.md Section 1.1 - 1.2)
--    Emergency Services: Police (35%) + EMS (25%) = 60%
--    Public Works / Infrastructure: Works (25%)
--    Social Dividend & Small Grants: Dividend (15%)
--    Total Split: Exactly 100.00%
-- ----------------------------------------------------------------------------
UPDATE `nyx_treasury_allocations`
SET `department_label` = 'San Andreas State Police Operating Account',
    `allocation_category` = 'emergency_services',
    `percentage_split` = 35.00,
    `cap_limit` = 1500000.00
WHERE `target_department` = 'gov:dept:police';

UPDATE `nyx_treasury_allocations`
SET `department_label` = 'Emergency Medical Services Operating Account',
    `allocation_category` = 'emergency_services',
    `percentage_split` = 25.00,
    `cap_limit` = 1000000.00
WHERE `target_department` = 'gov:dept:ems';

UPDATE `nyx_treasury_allocations`
SET `department_label` = 'Department of Public Works Infrastructure Account',
    `allocation_category` = 'infrastructure',
    `percentage_split` = 25.00,
    `cap_limit` = 800000.00
WHERE `target_department` = 'gov:dept:works';

INSERT IGNORE INTO `nyx_treasury_allocations` (`target_department`, `department_label`, `allocation_category`, `percentage_split`, `cap_limit`, `ratified_by_bill_id`) VALUES
('gov:dept:dividend', 'Citizen Social Dividend & Small Grants Reserve', 'social_dividend', 15.00, 500000.00, 'CHARTER_CIVIC_2026');

-- ----------------------------------------------------------------------------
-- 4. Immutable Revenue Sweep Execution Audit Ledger
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_treasury_revenue_sweeps` (
  `sweep_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `sweep_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `tax_pool_balance_before` DECIMAL(15, 2) NOT NULL,
  `total_swept` DECIMAL(15, 2) NOT NULL,
  `master_surplus_retained` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `allocations_count` INT UNSIGNED NOT NULL DEFAULT 0,
  `allocations_json` JSON NOT NULL,
  `fiscal_state` VARCHAR(32) NOT NULL DEFAULT 'SOLVENT',
  `executed_by` VARCHAR(64) NOT NULL DEFAULT 'REVENUE_SWEEP_DAEMON',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_sweep_uuid` (`sweep_uuid`),
  INDEX `idx_sweep_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;
