-- ============================================================================
-- Nyxframework Treasury & Public Finance Database Migration
-- File: 024_treasury_fiscal_circuit_and_payroll_scaling.sql
-- Description: Fiscal Circuit Breaker Protection, Drain Velocity Telemetry,
--              Logarithmic Public Payroll Scaling & Subvention Ledger.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Extend Treasury Accounts with Circuit Exemption & Outflow Thresholds
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_treasury_accounts`
  ADD COLUMN IF NOT EXISTS `circuit_exempt` TINYINT(1) NOT NULL DEFAULT 0 AFTER `signatories_required`,
  ADD COLUMN IF NOT EXISTS `daily_outflow_limit` DECIMAL(15, 2) NULL DEFAULT NULL AFTER `circuit_exempt`;

-- ----------------------------------------------------------------------------
-- 2. Fiscal Circuit Breaker Event Logs
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_treasury_circuit_logs` (
  `log_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `event_type` VARCHAR(48) NOT NULL,
  `previous_state` VARCHAR(32) NOT NULL,
  `new_state` VARCHAR(32) NOT NULL,
  `trigger_reason` VARCHAR(255) NOT NULL,
  `master_reserve` DECIMAL(15, 2) NOT NULL,
  `drain_velocity` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `authorized_by` VARCHAR(64) NOT NULL DEFAULT 'SYSTEM',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_circuit_event_type` (`event_type`),
  INDEX `idx_circuit_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 3. Public Service Payroll Run History & Subvention Ledger
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_treasury_payroll_runs` (
  `run_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `run_uuid` VARCHAR(36) NOT NULL,
  `fiscal_state` VARCHAR(32) NOT NULL,
  `wage_multiplier` DECIMAL(5, 4) NOT NULL,
  `total_disbursed` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `recipient_count` INT UNSIGNED NOT NULL DEFAULT 0,
  `master_reserve_before` DECIMAL(15, 2) NOT NULL,
  `master_reserve_after` DECIMAL(15, 2) NOT NULL,
  `subventions_total` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_payroll_run_uuid` (`run_uuid`),
  INDEX `idx_payroll_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;
