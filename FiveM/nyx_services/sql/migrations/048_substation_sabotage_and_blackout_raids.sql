-- ============================================================================
-- Nyxframework: nyx_services & nyx_properties
-- Migration: 048_substation_sabotage_and_blackout_raids.sql
-- Description: Substation physical sabotage tracking, blackout raid mechanics,
--              commercial warehouse magnetic lock failures, and alarm auditing.
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Extend regional substations with physical sabotage states and cooldowns
ALTER TABLE `nyx_services_substations`
  ADD COLUMN IF NOT EXISTS `is_sabotaged` TINYINT(1) NOT NULL DEFAULT 0 AFTER `breaker_tripped`,
  ADD COLUMN IF NOT EXISTS `last_sabotaged_at` TIMESTAMP NULL AFTER `is_sabotaged`,
  ADD COLUMN IF NOT EXISTS `sabotage_cooldown_until` TIMESTAMP NULL AFTER `last_sabotaged_at`;

-- 2. Create immutable substation sabotage incident ledger
CREATE TABLE IF NOT EXISTS `nyx_services_substation_sabotage_logs` (
  `sabotage_id` INT AUTO_INCREMENT PRIMARY KEY,
  `sabotage_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `substation_id` VARCHAR(32) NOT NULL,
  `saboteur_citizen_id` VARCHAR(16) NULL,
  `tool_used` VARCHAR(32) NOT NULL,
  `success` TINYINT(1) NOT NULL DEFAULT 1,
  `alarm_triggered` TINYINT(1) NOT NULL DEFAULT 1,
  `shock_injury_inflicted` TINYINT(1) NOT NULL DEFAULT 0,
  `police_alerted` TINYINT(1) NOT NULL DEFAULT 1,
  `coords` JSON NOT NULL,
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_sabotage_substation` (`substation_id`),
  INDEX `idx_sabotage_citizen` (`saboteur_citizen_id`),
  INDEX `idx_sabotage_time` (`created_at` DESC),
  CONSTRAINT `fk_sabotage_substation` FOREIGN KEY (`substation_id`) REFERENCES `nyx_services_substations`(`substation_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Extend properties with electronic alarm security and backup power generators
ALTER TABLE `nyx_properties`
  ADD COLUMN IF NOT EXISTS `has_alarm` TINYINT(1) NOT NULL DEFAULT 1 AFTER `is_locked`,
  ADD COLUMN IF NOT EXISTS `has_backup_generator` TINYINT(1) NOT NULL DEFAULT 0 AFTER `has_alarm`,
  ADD COLUMN IF NOT EXISTS `alarm_status` ENUM('armed', 'tripped', 'offline', 'disabled') NOT NULL DEFAULT 'armed' AFTER `has_backup_generator`;

-- 4. Extend property audit ledger actions with blackout and alarm breach events
ALTER TABLE `nyx_property_audit`
  MODIFY COLUMN `action` ENUM('PURCHASE', 'SALE', 'MILLAGE_TAX_DEBIT', 'LOCK_TOGGLE', 'KEY_ISSUED', 'KEY_REVOKED', 'POLICE_BREACH', 'BLACKOUT_BREACH', 'ALARM_BREACH') NOT NULL;

-- 5. Extend logistics commercial warehouses with security alarms and backup generator support
ALTER TABLE `nyx_logistics_warehouses`
  ADD COLUMN IF NOT EXISTS `has_alarm` TINYINT(1) NOT NULL DEFAULT 1 AFTER `is_locked`,
  ADD COLUMN IF NOT EXISTS `has_backup_generator` TINYINT(1) NOT NULL DEFAULT 0 AFTER `has_alarm`,
  ADD COLUMN IF NOT EXISTS `alarm_status` ENUM('armed', 'tripped', 'offline', 'disabled') NOT NULL DEFAULT 'armed' AFTER `has_backup_generator`;

SET FOREIGN_KEY_CHECKS = 1;
