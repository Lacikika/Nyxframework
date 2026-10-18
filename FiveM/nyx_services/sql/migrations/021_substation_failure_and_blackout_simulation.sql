-- ============================================================================
-- Nyxframework: nyx_services
-- Migration: 021_substation_failure_and_blackout_simulation.sql
-- Description: Extend substations with breaker trip states, failure telemetry,
--              peak load ratings, and blackout incident audit logs.
-- ============================================================================

-- 1. Extend substations table with failure and circuit breaker fields
ALTER TABLE `nyx_services_substations`
  ADD COLUMN IF NOT EXISTS `failure_reason` VARCHAR(64) NULL AFTER `is_blackout`,
  ADD COLUMN IF NOT EXISTS `blackout_started_at` TIMESTAMP NULL AFTER `failure_reason`,
  ADD COLUMN IF NOT EXISTS `peak_load_mw` DECIMAL(8, 2) NOT NULL DEFAULT 45.00 AFTER `blackout_started_at`,
  ADD COLUMN IF NOT EXISTS `breaker_tripped` TINYINT(1) NOT NULL DEFAULT 0 AFTER `peak_load_mw`,
  ADD COLUMN IF NOT EXISTS `total_blackouts_count` INT NOT NULL DEFAULT 0 AFTER `breaker_tripped`;

-- 2. Create immutable blackout event audit logging table
CREATE TABLE IF NOT EXISTS `nyx_services_blackout_logs` (
  `log_id` INT AUTO_INCREMENT PRIMARY KEY,
  `substation_id` VARCHAR(32) NOT NULL,
  `failure_reason` VARCHAR(64) NOT NULL,
  `started_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `restored_at` TIMESTAMP NULL,
  `duration_seconds` INT NULL,
  `restored_by_citizen_id` VARCHAR(16) NULL,
  INDEX `idx_blackout_substation` (`substation_id`),
  INDEX `idx_blackout_active` (`restored_at`),
  FOREIGN KEY (`substation_id`) REFERENCES `nyx_services_substations`(`substation_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
