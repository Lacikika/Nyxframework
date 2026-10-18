-- Migration 030: Municipal Infrastructure Degradation Mode, Impound Reclamation & Vehicle Registration Revenue
-- Resources: nyx_treasury, nyx_vehicles, nyx_services, nyx_mdt, nyx_core

-- 1. Municipal Fiscal Solvency State Tracking Table
CREATE TABLE IF NOT EXISTS `nyx_treasury_fiscal_states` (
    `state_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `master_account_id` VARCHAR(64) NOT NULL DEFAULT 'gov:city:master',
    `liquid_balance` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    `fiscal_tier` ENUM('solvent', 'fiscal_stress', 'degraded', 'bankrupt') NOT NULL DEFAULT 'solvent',
    `auto_repair_status` ENUM('subsidized', 'at_cost', 'emergency_only', 'offline') NOT NULL DEFAULT 'subsidized',
    `impound_lot_status` ENUM('standard', 'surcharged', 'emergency_only', 'locked') NOT NULL DEFAULT 'standard',
    `ai_dispatch_latency_sec` INT UNSIGNED NOT NULL DEFAULT 0,
    `notes` VARCHAR(255) NULL DEFAULT NULL,
    `evaluated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_fiscal_tier` (`fiscal_tier`),
    KEY `idx_fiscal_evaluated` (`evaluated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Extend nyx_vehicles_owned with Registration & Impound State
ALTER TABLE `nyx_vehicles_owned`
    ADD COLUMN IF NOT EXISTS `registration_status` ENUM('valid', 'expired', 'suspended') NOT NULL DEFAULT 'valid' AFTER `lock_state`,
    ADD COLUMN IF NOT EXISTS `registration_expires_at` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `registration_status`,
    ADD COLUMN IF NOT EXISTS `impound_lot_id` VARCHAR(64) NULL DEFAULT NULL AFTER `storage_state`,
    ADD COLUMN IF NOT EXISTS `impound_fee` DECIMAL(10,2) NOT NULL DEFAULT 0.00 AFTER `impound_lot_id`,
    ADD COLUMN IF NOT EXISTS `impound_reason` VARCHAR(255) NULL DEFAULT NULL AFTER `impound_fee`,
    ADD COLUMN IF NOT EXISTS `impounded_by` VARCHAR(64) NULL DEFAULT NULL AFTER `impound_reason`,
    ADD COLUMN IF NOT EXISTS `impounded_at` INT UNSIGNED NULL DEFAULT NULL AFTER `impounded_by`;

-- 3. Municipal Impound Lots Registry
CREATE TABLE IF NOT EXISTS `nyx_vehicles_impound_lots` (
    `lot_id` VARCHAR(64) NOT NULL PRIMARY KEY,
    `label` VARCHAR(100) NOT NULL,
    `coords` JSON NOT NULL,
    `release_coords` JSON NOT NULL,
    `base_fee` DECIMAL(10,2) NOT NULL DEFAULT 500.00,
    `daily_storage_fee` DECIMAL(10,2) NOT NULL DEFAULT 150.00,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Immutable Audit Ledger of Impounds & Releases
CREATE TABLE IF NOT EXISTS `nyx_vehicles_impound_logs` (
    `log_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `vin` VARCHAR(17) NOT NULL,
    `plate` VARCHAR(12) NOT NULL,
    `action` ENUM('impounded', 'released', 'auctioned', 'fee_adjusted') NOT NULL,
    `citizen_id` VARCHAR(64) NOT NULL,
    `officer_citizen_id` VARCHAR(64) NULL DEFAULT NULL,
    `impound_lot_id` VARCHAR(64) NOT NULL,
    `base_fee` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    `emergency_surcharge` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    `total_paid` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    `treasury_tx_id` VARCHAR(64) NULL DEFAULT NULL,
    `notes` VARCHAR(255) NULL DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_imp_vin` (`vin`),
    KEY `idx_imp_plate` (`plate`),
    KEY `idx_imp_citizen` (`citizen_id`),
    KEY `idx_imp_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Municipal Public Auto-Repair Stations
CREATE TABLE IF NOT EXISTS `nyx_services_repair_stations` (
    `station_id` VARCHAR(64) NOT NULL PRIMARY KEY,
    `label` VARCHAR(100) NOT NULL,
    `coords` JSON NOT NULL,
    `base_labor_fee` DECIMAL(10,2) NOT NULL DEFAULT 150.00,
    `parts_cost_multiplier` DECIMAL(4,2) NOT NULL DEFAULT 1.00,
    `status` ENUM('operational', 'degraded', 'offline') NOT NULL DEFAULT 'operational',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. Seed Municipal Impound Lots & Repair Stations
INSERT INTO `nyx_vehicles_impound_lots` (`lot_id`, `label`, `coords`, `release_coords`, `base_fee`, `daily_storage_fee`)
VALUES
    ('impound_lot_ls', 'Los Santos Municipal Auto Impound', '{"x": 401.2, "y": -1631.5, "z": 29.3}', '{"x": 405.0, "y": -1640.0, "z": 29.3, "w": 230.0}', 500.00, 150.00),
    ('impound_lot_sandy', 'Blaine County Sheriff Impound Compound', '{"x": 1853.2, "y": 3685.4, "z": 34.2}', '{"x": 1860.0, "y": 3678.0, "z": 34.0, "w": 30.0}', 350.00, 100.00)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

INSERT INTO `nyx_services_repair_stations` (`station_id`, `label`, `coords`, `base_labor_fee`, `parts_cost_multiplier`, `status`)
VALUES
    ('repair_depot_ls', 'Los Santos Municipal Public Works Repair Depot', '{"x": -338.4, "y": -136.2, "z": 39.0}', 150.00, 1.00, 'operational'),
    ('repair_sandy_shores', 'Sandy Shores Municipal Auto Maintenance Bay', '{"x": 1735.6, "y": 3311.2, "z": 41.2}', 120.00, 1.10, 'operational'),
    ('repair_paleto_bay', 'Paleto Bay Public Service Maintenance Stall', '{"x": 110.8, "y": 6626.5, "z": 31.8}', 130.00, 1.15, 'operational')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);
