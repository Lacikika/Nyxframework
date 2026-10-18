-- Migration 033: Staggered Resource Bootloader Dispatch & Startup Audit History
-- Persists immutable audit logs of server boot cycles, stage timings, and contention diagnostics.

CREATE TABLE IF NOT EXISTS `nyx_bootloader_logs` (
    `boot_id` INT AUTO_INCREMENT PRIMARY KEY,
    `boot_uuid` VARCHAR(64) NOT NULL UNIQUE,
    `started_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `completed_at` TIMESTAMP NULL DEFAULT NULL,
    `total_duration_ms` INT NOT NULL DEFAULT 0,
    `stagger_delay_ms` INT NOT NULL DEFAULT 50,
    `resources_dispatched` INT NOT NULL DEFAULT 14,
    `stages_json` LONGTEXT NOT NULL,
    `status` VARCHAR(32) NOT NULL DEFAULT 'COMPLETED',
    INDEX `idx_bootloader_started_at` (`started_at`),
    INDEX `idx_bootloader_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
