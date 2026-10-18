-- Nyxframework Treasury & Public Ledger Schema
-- Migration: 003_treasury_ledger.sql

-- 1. Municipal and organizational bank accounts
CREATE TABLE IF NOT EXISTS `nyx_treasury_accounts` (
  `account_id` VARCHAR(64) PRIMARY KEY,
  `label` VARCHAR(96) NOT NULL,
  `balance` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `type` ENUM('public_master', 'department', 'reserve', 'grant_pool', 'tax_pool') NOT NULL,
  `signatories_required` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `chk_positive_balance` CHECK (`balance` >= 0.00),
  INDEX `idx_acc_type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Append-only double-entry transaction ledger
CREATE TABLE IF NOT EXISTS `nyx_treasury_ledger` (
  `entry_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `transaction_uuid` VARCHAR(36) NOT NULL,
  `debit_account` VARCHAR(64) NOT NULL,
  `credit_account` VARCHAR(64) NOT NULL,
  `amount` DECIMAL(15, 2) NOT NULL,
  `tax_deducted` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `category` VARCHAR(48) NOT NULL,
  `authorized_by` VARCHAR(64) NOT NULL,
  `memo` VARCHAR(255) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_tx_uuid` (`transaction_uuid`),
  INDEX `idx_debit` (`debit_account`),
  INDEX `idx_credit` (`credit_account`),
  INDEX `idx_cat_created` (`category`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Budget allocation schedules voted by elected councils
CREATE TABLE IF NOT EXISTS `nyx_treasury_allocations` (
  `allocation_id` INT AUTO_INCREMENT PRIMARY KEY,
  `target_department` VARCHAR(64) NOT NULL,
  `percentage_split` DECIMAL(5, 2) NOT NULL,
  `cap_limit` DECIMAL(15, 2) NULL,
  `ratified_by_bill_id` VARCHAR(32) NOT NULL,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`target_department`) REFERENCES `nyx_treasury_accounts`(`account_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Initial Seed Data
INSERT IGNORE INTO `nyx_treasury_accounts` (`account_id`, `label`, `balance`, `type`) VALUES
('gov:city:master', 'Municipal Master Reserve', 5000000.00, 'public_master'),
('gov:city:tax', 'Consolidated Tax Collection Pool', 0.00, 'tax_pool'),
('gov:dept:police', 'San Andreas State Police Operating Account', 500000.00, 'department'),
('gov:dept:ems', 'Emergency Medical Services Operating Account', 300000.00, 'department'),
('gov:dept:works', 'Department of Public Works Infrastructure Account', 200000.00, 'department');

INSERT IGNORE INTO `nyx_treasury_allocations` (`allocation_id`, `target_department`, `percentage_split`, `cap_limit`, `ratified_by_bill_id`) VALUES
(1, 'gov:dept:police', 40.00, 1000000.00, 'CHARTER_INIT_2026'),
(2, 'gov:dept:ems', 35.00, 800000.00, 'CHARTER_INIT_2026'),
(3, 'gov:dept:works', 25.00, 500000.00, 'CHARTER_INIT_2026');
