-- Migration 039: Mechanical Diagnostics, OBD-II Scans & Civic Impound Terminal
-- Resources: nyx_vehicles, nyx_ui, nyx_treasury, nyx_core

-- 1. Vehicle Diagnostic Scans & OBD-II DTC Fault History
CREATE TABLE IF NOT EXISTS `nyx_vehicles_diagnostic_scans` (
    `scan_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `scan_uuid` VARCHAR(64) NOT NULL UNIQUE,
    `vin` VARCHAR(17) NOT NULL,
    `plate` VARCHAR(12) NOT NULL,
    `mechanic_citizen_id` VARCHAR(64) NOT NULL,
    `mileage` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `engine_health` DECIMAL(6, 2) NOT NULL DEFAULT 1000.00,
    `oil_quality` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
    `brake_pad_wear` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
    `transmission_wear` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
    `suspension_wear` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
    `overall_grade` ENUM('pristine', 'good', 'fair', 'critical', 'hazardous') NOT NULL DEFAULT 'pristine',
    `diagnostic_trouble_codes` JSON NULL DEFAULT NULL,
    `notes` VARCHAR(255) NULL DEFAULT NULL,
    `scanned_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_diag_vin` (`vin`),
    KEY `idx_diag_plate` (`plate`),
    KEY `idx_diag_mechanic` (`mechanic_citizen_id`),
    KEY `idx_diag_scanned_at` (`scanned_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Extend nyx_vehicles_wear with Inspection Certification & Notes
ALTER TABLE `nyx_vehicles_wear`
    ADD COLUMN IF NOT EXISTS `inspection_status` ENUM('passed', 'warning', 'failed', 'uninspected') NOT NULL DEFAULT 'uninspected' AFTER `service_notes`,
    ADD COLUMN IF NOT EXISTS `last_inspection_at` INT UNSIGNED NULL DEFAULT NULL AFTER `inspection_status`,
    ADD COLUMN IF NOT EXISTS `inspector_citizen_id` VARCHAR(64) NULL DEFAULT NULL AFTER `last_inspection_at`,
    ADD COLUMN IF NOT EXISTS `inspection_notes` VARCHAR(255) NULL DEFAULT NULL AFTER `inspector_citizen_id`;

-- 3. Extend nyx_vehicles_impound_lots with Capacity and Automated Kiosk Flag
ALTER TABLE `nyx_vehicles_impound_lots`
    ADD COLUMN IF NOT EXISTS `capacity` INT UNSIGNED NOT NULL DEFAULT 50 AFTER `daily_storage_fee`,
    ADD COLUMN IF NOT EXISTS `is_automated_kiosk` TINYINT(1) NOT NULL DEFAULT 1 AFTER `capacity`;
