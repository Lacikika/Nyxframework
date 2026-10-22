-- ============================================================================
-- Nyxframework: nyx_vehicles, nyx_logistics, nyx_treasury & nyx_services
-- Migration: 068_commercial_transit_permits_and_overweight_surcharges.sql
-- Description: Commercial heavy-haul transit permits, municipal oversized load licensing,
--              weight surcharge tiers, active permit validation, and MDT bypass citation logging.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Create commercial transit permits table
CREATE TABLE IF NOT EXISTS `nyx_commercial_transit_permits` (
  `permit_id` VARCHAR(64) NOT NULL PRIMARY KEY,
  `vehicle_plate` VARCHAR(16) NOT NULL,
  `applicant_identifier` VARCHAR(64) NOT NULL,
  `faction_id` VARCHAR(64) NULL DEFAULT NULL,
  `permit_type` ENUM('SINGLE_TRIP', 'DAILY_PASS', 'ANNUAL_HEAVY_HAUL') NOT NULL DEFAULT 'SINGLE_TRIP',
  `max_weight_capacity_kg` DECIMAL(10, 2) NOT NULL DEFAULT 25000.00,
  `fee_paid` DECIMAL(10, 2) NOT NULL DEFAULT 150.00,
  `issued_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at` TIMESTAMP NOT NULL,
  `status` ENUM('ACTIVE', 'EXPIRED', 'REVOKED') NOT NULL DEFAULT 'ACTIVE',
  INDEX `idx_permit_plate` (`vehicle_plate`),
  INDEX `idx_permit_applicant` (`applicant_identifier`),
  INDEX `idx_permit_faction` (`faction_id`),
  INDEX `idx_permit_status` (`status`),
  INDEX `idx_permit_expiry` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Create transit permit violation audit log table
CREATE TABLE IF NOT EXISTS `nyx_permit_violation_logs` (
  `violation_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `vehicle_plate` VARCHAR(16) NOT NULL,
  `driver_identifier` VARCHAR(64) NULL DEFAULT NULL,
  `measured_weight_kg` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `permitted_weight_kg` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `violation_type` ENUM('NO_PERMIT', 'WEIGHT_EXCEEDED', 'PERMIT_EXPIRED', 'BYPASS_UNLICENSED') NOT NULL DEFAULT 'NO_PERMIT',
  `assessed_fine` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_viol_plate` (`vehicle_plate`),
  INDEX `idx_viol_driver` (`driver_identifier`),
  INDEX `idx_viol_type` (`violation_type`),
  INDEX `idx_viol_timestamp` (`timestamp` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Seed municipal permit issuing terminals
INSERT INTO `nyx_commercial_transit_permits`
  (`permit_id`, `vehicle_plate`, `applicant_identifier`, `faction_id`, `permit_type`, `max_weight_capacity_kg`, `fee_paid`, `issued_at`, `expires_at`, `status`)
VALUES
  ('permit_seed_001', 'HEAVY01', 'CIT_SEED_01', 'corp_elysian_logistics', 'ANNUAL_HEAVY_HAUL', 50000.00, 2500.00, CURRENT_TIMESTAMP, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 365 DAY), 'ACTIVE')
ON DUPLICATE KEY UPDATE `vehicle_plate` = VALUES(`vehicle_plate`);

SET FOREIGN_KEY_CHECKS = 1;
