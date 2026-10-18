-- ============================================================================
-- Nyxframework: nyx_services & nyx_properties
-- Migration: 055_municipal_utility_metering_and_automated_grid_billing.sql
-- Description: Municipal utility metering, automated grid billing cycles,
--              consumption invoices, delinquency enforcement, and power cut-off state machine.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Extend nyx_services_utility_meters with property bindings and delinquency tracking
ALTER TABLE `nyx_services_utility_meters`
  ADD COLUMN IF NOT EXISTS `property_id` INT UNSIGNED NULL AFTER `owner_citizen_id`,
  ADD COLUMN IF NOT EXISTS `last_billed_at` TIMESTAMP NULL AFTER `unpaid_balance`,
  ADD COLUMN IF NOT EXISTS `last_reading_kwh` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 AFTER `last_billed_at`,
  ADD COLUMN IF NOT EXISTS `last_reading_water` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 AFTER `last_reading_kwh`,
  ADD COLUMN IF NOT EXISTS `consecutive_unpaid_cycles` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `last_reading_water`,
  ADD COLUMN IF NOT EXISTS `delinquency_tier` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `consecutive_unpaid_cycles`,
  ADD COLUMN IF NOT EXISTS `meter_status` ENUM('active', 'grace_notice', 'late_warning', 'disconnected', 'lien_referred') NOT NULL DEFAULT 'active' AFTER `delinquency_tier`,
  ADD COLUMN IF NOT EXISTS `disconnection_notice_at` TIMESTAMP NULL AFTER `is_service_suspended`,
  ADD COLUMN IF NOT EXISTS `disconnected_at` TIMESTAMP NULL AFTER `disconnection_notice_at`,
  ADD COLUMN IF NOT EXISTS `reconnected_at` TIMESTAMP NULL AFTER `disconnected_at`;

-- 2. Create immutable municipal utility invoices ledger
CREATE TABLE IF NOT EXISTS `nyx_services_utility_invoices` (
  `invoice_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `invoice_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `meter_id` VARCHAR(32) NOT NULL,
  `property_id` INT UNSIGNED NULL,
  `owner_citizen_id` VARCHAR(16) NOT NULL,
  `substation_id` VARCHAR(32) NOT NULL,
  `cycle_period_start` TIMESTAMP NOT NULL,
  `cycle_period_end` TIMESTAMP NOT NULL,
  `kwh_consumed` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  `water_consumed` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  `kwh_tariff` DECIMAL(8, 4) NOT NULL DEFAULT 0.1500,
  `water_tariff` DECIMAL(8, 4) NOT NULL DEFAULT 0.0500,
  `energy_charge` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `water_charge` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `late_penalty` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `reconnect_fee` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `total_due` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `amount_paid` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `status` ENUM('issued', 'paid', 'overdue', 'delinquent_cutoff', 'settled_post_cutoff') NOT NULL DEFAULT 'issued',
  `treasury_tx_uuid` VARCHAR(36) NULL,
  `paid_at` TIMESTAMP NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_util_inv_meter` (`meter_id`),
  INDEX `idx_util_inv_citizen` (`owner_citizen_id`),
  INDEX `idx_util_inv_status` (`status`),
  INDEX `idx_util_inv_created` (`created_at` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Create immutable utility delinquency and enforcement audit ledger
CREATE TABLE IF NOT EXISTS `nyx_services_utility_delinquency_logs` (
  `log_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `log_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `meter_id` VARCHAR(32) NOT NULL,
  `property_id` INT UNSIGNED NULL,
  `owner_citizen_id` VARCHAR(16) NOT NULL,
  `action` ENUM('NOTICE_ISSUED', 'LATE_PENALIZED', 'POWER_CUTOFF_ENFORCED', 'RECONNECTED', 'LIEN_REFERRED') NOT NULL,
  `arrears_amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `actor_citizen_id` VARCHAR(16) NULL,
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_util_delinq_meter` (`meter_id`),
  INDEX `idx_util_delinq_citizen` (`owner_citizen_id`),
  INDEX `idx_util_delinq_action` (`action`),
  INDEX `idx_util_delinq_created` (`created_at` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Extend nyx_properties with utility disconnection status
ALTER TABLE `nyx_properties`
  ADD COLUMN IF NOT EXISTS `is_utility_suspended` TINYINT(1) NOT NULL DEFAULT 0 AFTER `has_backup_generator`,
  ADD COLUMN IF NOT EXISTS `utility_status` ENUM('normal', 'cut_off', 'backup_power') NOT NULL DEFAULT 'normal' AFTER `is_utility_suspended`;

-- 5. Extend nyx_property_audit with utility action enum values
ALTER TABLE `nyx_property_audit`
  MODIFY COLUMN `action` ENUM('PURCHASE', 'SALE', 'MILLAGE_TAX_DEBIT', 'LOCK_TOGGLE', 'KEY_ISSUED', 'KEY_REVOKED', 'POLICE_BREACH', 'BLACKOUT_BREACH', 'ALARM_BREACH', 'UTILITY_BILL_PAID', 'UTILITY_CUTOFF_ENFORCED', 'UTILITY_RECONNECTED') NOT NULL;

-- 6. Link default properties to valid canonical substations and update meters
UPDATE `nyx_properties`
SET `linked_substation_id` = 'grid_central_ls'
WHERE `property_code` = 'apt_integrity_101';

UPDATE `nyx_properties`
SET `linked_substation_id` = 'grid_central_ls'
WHERE `property_code` = 'store_vinewood_24';

UPDATE `nyx_properties`
SET `linked_substation_id` = 'grid_port_ls'
WHERE `property_code` = 'wh_elysian_04';

SET FOREIGN_KEY_CHECKS = 1;
