-- ============================================================================
-- Nyxframework Core Engine Migration
-- Migration: 054_end_to_end_stress_simulation_audits.sql
-- Description: Automated test harness executing concurrent multi-actor stress
--              simulations across all 14 resources to verify 0.00ms baseline idle
--              performance, zero entity/mutex leaks, and double-entry conservation.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. End-to-End Stress Test Run Audit History
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_core_stress_test_runs` (
  `run_id` INT AUTO_INCREMENT PRIMARY KEY,
  `run_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `concurrency_level` INT NOT NULL DEFAULT 50,
  `total_transactions` INT NOT NULL DEFAULT 0,
  `resources_tested` INT NOT NULL DEFAULT 14,
  `idle_tick_ms` DECIMAL(6, 4) NOT NULL DEFAULT 0.0000,
  `economic_conservation_delta` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `entity_leaks_count` INT NOT NULL DEFAULT 0,
  `mutex_leaks_count` INT NOT NULL DEFAULT 0,
  `duration_ms` INT NOT NULL DEFAULT 0,
  `status` ENUM('passed', 'failed', 'running') NOT NULL DEFAULT 'running',
  `diagnostics_json` LONGTEXT NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  INDEX `idx_stress_runs_status` (`status`),
  INDEX `idx_stress_runs_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
