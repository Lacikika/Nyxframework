-- ============================================================================
-- Nyxframework Judiciary & Civic Architecture Database Migration
-- File: 023_judiciary_jury_dispatcher_and_courtroom_routing.sql
-- Description: Automated Civic Jury Pool Dispatcher, Fisher-Yates Permutations,
--              OneSync Virtual Routing Bucket Courtroom Isolation & Deliberation.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Extend Dockets with Routing Buckets, Deliberation Timers & Extended Status
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_judiciary_dockets`
  MODIFY COLUMN `status` ENUM('filed', 'scheduled', 'in_trial', 'deliberation', 'concluded', 'dismissed', 'mistrial') DEFAULT 'filed',
  ADD COLUMN IF NOT EXISTS `routing_bucket` INT UNSIGNED NULL DEFAULT NULL AFTER `status`,
  ADD COLUMN IF NOT EXISTS `deliberation_bucket` INT UNSIGNED NULL DEFAULT NULL AFTER `routing_bucket`,
  ADD COLUMN IF NOT EXISTS `deliberation_started_at` TIMESTAMP NULL DEFAULT NULL AFTER `scheduled_for`;

-- ----------------------------------------------------------------------------
-- 2. Extend Juries Registry with Seat Allocation, Summons Expiry & Stipends
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_judiciary_juries`
  MODIFY COLUMN `selection_status` ENUM('summoned', 'excused', 'seated', 'deliberating', 'voted', 'dismissed') DEFAULT 'summoned',
  ADD COLUMN IF NOT EXISTS `seat_index` TINYINT UNSIGNED NULL DEFAULT NULL AFTER `citizen_id`,
  ADD COLUMN IF NOT EXISTS `summons_expires_at` TIMESTAMP NULL DEFAULT NULL AFTER `assigned_at`,
  ADD COLUMN IF NOT EXISTS `deliberation_entered_at` TIMESTAMP NULL DEFAULT NULL AFTER `summons_expires_at`,
  ADD COLUMN IF NOT EXISTS `stipend_paid` DECIMAL(10,2) NOT NULL DEFAULT 0.00 AFTER `secret_ballot`;

-- ----------------------------------------------------------------------------
-- 3. Immutable Jury Service History & Cooldown Ledger
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_judiciary_jury_service_logs` (
  `log_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `docket_id` VARCHAR(32) NOT NULL,
  `citizen_id` VARCHAR(16) NOT NULL,
  `seat_index` TINYINT UNSIGNED NULL,
  `verdict_ruling` VARCHAR(32) NULL,
  `stipend_amount` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `served_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_jury_service_citizen` (`citizen_id`, `served_at`),
  INDEX `idx_jury_service_docket` (`docket_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;
