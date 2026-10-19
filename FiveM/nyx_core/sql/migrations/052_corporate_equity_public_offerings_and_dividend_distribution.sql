-- ============================================================================
-- Nyxframework Factions & Treasury Engine Migration
-- Migration: 052_corporate_equity_public_offerings_and_dividend_distribution.sql
-- Description: Corporate equity public offerings (IPO / capital raising),
--              consolidated shareholder cap table, and automated weekly
--              dividend distribution via double-entry treasury ledgers.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Extend nyx_factions_registry with Dividend Policy & Schedule Attributes
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_factions_registry`
  ADD COLUMN IF NOT EXISTS `dividend_frequency_days` INT NOT NULL DEFAULT 7 AFTER `is_active`,
  ADD COLUMN IF NOT EXISTS `last_dividend_run_at` TIMESTAMP NULL DEFAULT NULL AFTER `dividend_frequency_days`,
  ADD COLUMN IF NOT EXISTS `auto_dividends_enabled` TINYINT(1) NOT NULL DEFAULT 1 AFTER `last_dividend_run_at`,
  ADD COLUMN IF NOT EXISTS `reinvestment_rate_target` DECIMAL(5, 4) NOT NULL DEFAULT 0.2000 AFTER `auto_dividends_enabled`;

-- ----------------------------------------------------------------------------
-- 2. Corporate Equity Public Offerings (IPO / Share Offerings)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_factions_equity_offerings` (
  `offering_id` VARCHAR(36) NOT NULL PRIMARY KEY,
  `faction_id` VARCHAR(32) NOT NULL,
  `title` VARCHAR(128) NOT NULL,
  `prospectus` TEXT NULL,
  `total_shares_offered` DECIMAL(5, 2) NOT NULL,
  `shares_available` DECIMAL(5, 2) NOT NULL,
  `shares_sold` DECIMAL(5, 2) NOT NULL DEFAULT 0.00,
  `price_per_share` DECIMAL(15, 2) NOT NULL,
  `min_purchase` DECIMAL(5, 2) NOT NULL DEFAULT 0.10,
  `max_purchase` DECIMAL(5, 2) NOT NULL DEFAULT 50.00,
  `target_capital` DECIMAL(15, 2) NOT NULL,
  `capital_raised` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `status` ENUM('active', 'completed', 'cancelled', 'expired') NOT NULL DEFAULT 'active',
  `created_by_citizen_id` VARCHAR(64) NOT NULL,
  `expires_at` TIMESTAMP NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  INDEX `idx_eqo_faction` (`faction_id`),
  INDEX `idx_eqo_status` (`status`),
  INDEX `idx_eqo_expires` (`expires_at`),
  FOREIGN KEY (`faction_id`) REFERENCES `nyx_factions_registry`(`faction_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 3. Consolidated Equity Shareholders & Investor Cap Table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_factions_equity_shareholders` (
  `holding_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `faction_id` VARCHAR(32) NOT NULL,
  `citizen_id` VARCHAR(64) NOT NULL,
  `equity_shares` DECIMAL(5, 2) NOT NULL DEFAULT 0.00,
  `is_external_investor` TINYINT(1) NOT NULL DEFAULT 1,
  `total_invested` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `total_dividends_collected` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `last_dividend_at` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY `unique_faction_citizen_holding` (`faction_id`, `citizen_id`),
  INDEX `idx_eqh_citizen` (`citizen_id`),
  INDEX `idx_eqh_faction` (`faction_id`),
  FOREIGN KEY (`faction_id`) REFERENCES `nyx_factions_registry`(`faction_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 4. Immutable Equity Share Purchases & Capital Raising Transaction Ledger
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_factions_equity_purchases` (
  `purchase_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `purchase_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `offering_id` VARCHAR(36) NOT NULL,
  `faction_id` VARCHAR(32) NOT NULL,
  `investor_citizen_id` VARCHAR(64) NOT NULL,
  `shares_acquired` DECIMAL(5, 2) NOT NULL,
  `price_per_share` DECIMAL(15, 2) NOT NULL,
  `total_amount` DECIMAL(15, 2) NOT NULL,
  `treasury_tx_id` VARCHAR(64) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  INDEX `idx_eqp_faction` (`faction_id`),
  INDEX `idx_eqp_citizen` (`investor_citizen_id`),
  INDEX `idx_eqp_offering` (`offering_id`),
  FOREIGN KEY (`faction_id`) REFERENCES `nyx_factions_registry`(`faction_id`) ON DELETE CASCADE,
  FOREIGN KEY (`offering_id`) REFERENCES `nyx_factions_equity_offerings`(`offering_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 5. Immutable Dividend Run Audit Ledger
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_factions_dividend_runs` (
  `run_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `run_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `faction_id` VARCHAR(32) NOT NULL,
  `declared_net_profit` DECIMAL(15, 2) NOT NULL,
  `reinvestment_rate` DECIMAL(5, 4) NOT NULL DEFAULT 0.2000,
  `retained_reserves_amount` DECIMAL(15, 2) NOT NULL,
  `total_disbursed` DECIMAL(15, 2) NOT NULL,
  `shareholder_count` INT UNSIGNED NOT NULL DEFAULT 0,
  `treasury_tx_ids` JSON NULL DEFAULT NULL,
  `executed_by_citizen_id` VARCHAR(64) NOT NULL DEFAULT 'SYSTEM',
  `status` ENUM('completed', 'failed', 'partial', 'skipped_insufficient_funds') NOT NULL DEFAULT 'completed',
  `failure_reason` VARCHAR(255) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  INDEX `idx_divrun_faction` (`faction_id`),
  INDEX `idx_divrun_created` (`created_at`),
  FOREIGN KEY (`faction_id`) REFERENCES `nyx_factions_registry`(`faction_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 6. Seed Canonical Public Equity Offering for Vanilla Unicorn
-- ----------------------------------------------------------------------------
INSERT INTO `nyx_factions_equity_offerings`
  (`offering_id`, `faction_id`, `title`, `prospectus`, `total_shares_offered`, `shares_available`, `shares_sold`, `price_per_share`, `min_purchase`, `max_purchase`, `target_capital`, `capital_raised`, `status`, `created_by_citizen_id`, `expires_at`)
VALUES
  ('offering_unicorn_ipo', 'corp_vanilla_unicorn', 'Vanilla Unicorn Series-A Growth Capital Offering', 'Public capital raise for VIP lounge luxury renovation, high-margin hospitality expansion, and corporate treasury growth.', 25.00, 25.00, 0.00, 2000.00, 1.00, 10.00, 50000.00, 0.00, 'active', 'SYSTEM_IPO', CURRENT_TIMESTAMP + INTERVAL 30 DAY)
ON DUPLICATE KEY UPDATE `title` = VALUES(`title`);

SET FOREIGN_KEY_CHECKS = 1;
