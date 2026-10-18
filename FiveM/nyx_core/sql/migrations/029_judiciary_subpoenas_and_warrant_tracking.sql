-- Migration 029: Judicial Subpoenas, Probable Cause Warrants & Live MDT Dispatch Tracking Integration
-- Resources: nyx_judiciary, nyx_mdt, nyx_treasury, nyx_core

-- 1. Probable Cause Warrant Petitions Registry
CREATE TABLE IF NOT EXISTS `nyx_judiciary_warrant_petitions` (
    `petition_id` VARCHAR(36) NOT NULL,
    `petitioner_citizen_id` VARCHAR(64) NOT NULL,
    `target_citizen_id` VARCHAR(64) NOT NULL,
    `warrant_type` VARCHAR(32) NOT NULL DEFAULT 'arrest',
    `subpoena_scope` VARCHAR(32) NULL DEFAULT NULL,
    `target_entity_id` VARCHAR(64) NULL DEFAULT NULL,
    `probable_cause_summary` TEXT NOT NULL,
    `requested_duration_hours` INT UNSIGNED NOT NULL DEFAULT 72,
    `status` ENUM('pending_review', 'approved', 'rejected', 'withdrawn') NOT NULL DEFAULT 'pending_review',
    `reviewed_by_judge_id` VARCHAR(64) NULL DEFAULT NULL,
    `review_notes` TEXT NULL,
    `reviewed_at` TIMESTAMP NULL DEFAULT NULL,
    `judicial_signature` VARCHAR(64) NULL DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`petition_id`),
    KEY `idx_pet_target` (`target_citizen_id`),
    KEY `idx_pet_petitioner` (`petitioner_citizen_id`),
    KEY `idx_pet_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Extend nyx_judiciary_warrants with Petition Ref, Subpoena Scope, Judicial Seal & Live Tracking
ALTER TABLE `nyx_judiciary_warrants`
    MODIFY COLUMN `type` VARCHAR(32) NOT NULL,
    ADD COLUMN IF NOT EXISTS `petition_id` VARCHAR(36) NULL DEFAULT NULL AFTER `target_entity_id`,
    ADD COLUMN IF NOT EXISTS `subpoena_scope` VARCHAR(32) NULL DEFAULT NULL AFTER `petition_id`,
    ADD COLUMN IF NOT EXISTS `judicial_signature` VARCHAR(64) NULL DEFAULT NULL AFTER `probable_cause_summary`,
    ADD COLUMN IF NOT EXISTS `tracking_active` TINYINT(1) NOT NULL DEFAULT 0 AFTER `status`,
    ADD COLUMN IF NOT EXISTS `last_ping_at` TIMESTAMP NULL DEFAULT NULL AFTER `tracking_active`;

-- 3. Live MDT Dispatch Suspect Tracking & Cellular Triangulation Audit Logs
CREATE TABLE IF NOT EXISTS `nyx_judiciary_tracking_logs` (
    `ping_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `warrant_id` BIGINT NOT NULL,
    `target_citizen_id` VARCHAR(64) NOT NULL,
    `coords` JSON NOT NULL,
    `accuracy_radius` DECIMAL(6,2) NOT NULL DEFAULT 35.00,
    `source_type` ENUM('cellular_triangulation', 'vehicle_alpr', 'financial_terminal') NOT NULL DEFAULT 'cellular_triangulation',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_track_warrant` (`warrant_id`),
    KEY `idx_track_citizen` (`target_citizen_id`),
    KEY `idx_track_time` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Seed Canonical Initial Judicial Warrant & Subpoena Fixtures
INSERT INTO `nyx_judiciary_warrant_petitions`
    (`petition_id`, `petitioner_citizen_id`, `target_citizen_id`, `warrant_type`, `subpoena_scope`, `target_entity_id`, `probable_cause_summary`, `requested_duration_hours`, `status`, `reviewed_by_judge_id`, `review_notes`, `reviewed_at`, `judicial_signature`)
VALUES
    ('pet-seed-001', 'CIT-POLICE-01', 'CIT-SUSPECT-77', 'subpoena', 'financial', 'citizen:CIT-SUSPECT-77', 'Subpoena financial ledgers and treasury transfer history for suspected grand embezzlement.', 120, 'approved', 'CIT-JUDGE-01', 'Probable cause established via sworn affidavit.', CURRENT_TIMESTAMP, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
ON DUPLICATE KEY UPDATE `status` = VALUES(`status`);
