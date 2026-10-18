-- ============================================================================
-- Nyxframework: nyx_judiciary
-- Migration: 006_judiciary_system.sql
-- Description: Formal court dockets, cryptographic chain-of-custody evidence,
--              judicial warrants, and automated civic jury assignment registries.
-- ============================================================================

-- Formal court cases and legal proceedings
CREATE TABLE IF NOT EXISTS `nyx_judiciary_dockets` (
  `docket_id` VARCHAR(32) PRIMARY KEY,
  `title` VARCHAR(128) NOT NULL,
  `plaintiff_citizen_id` VARCHAR(16) NOT NULL,
  `defendant_citizen_id` VARCHAR(16) NOT NULL,
  `presiding_judge_id` VARCHAR(16) NULL,
  `case_type` ENUM('civil', 'criminal_misdemeanor', 'criminal_felony', 'constitutional') NOT NULL,
  `status` ENUM('filed', 'scheduled', 'deliberation', 'concluded', 'dismissed') DEFAULT 'filed',
  `verdict` JSON NULL,
  `scheduled_for` TIMESTAMP NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_defendant` (`defendant_citizen_id`),
  INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Cryptographic forensic evidence items linked to proceedings
CREATE TABLE IF NOT EXISTS `nyx_judiciary_evidence` (
  `evidence_id` VARCHAR(36) PRIMARY KEY,
  `docket_id` VARCHAR(32) NULL,
  `type` ENUM('casing', 'blood', 'fingerprint', 'photo', 'document', 'ballistics') NOT NULL,
  `evidence_hash` VARCHAR(64) NOT NULL UNIQUE,
  `collector_citizen_id` VARCHAR(16) NOT NULL,
  `is_contaminated` TINYINT(1) DEFAULT 0,
  `contamination_source` VARCHAR(16) NULL,
  `metadata` JSON NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`docket_id`) REFERENCES `nyx_judiciary_dockets`(`docket_id`) ON DELETE SET NULL,
  INDEX `idx_evidence_hash` (`evidence_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Active judicial warrants (search & arrest)
CREATE TABLE IF NOT EXISTS `nyx_judiciary_warrants` (
  `warrant_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `target_citizen_id` VARCHAR(16) NOT NULL,
  `issuing_judge_id` VARCHAR(16) NOT NULL,
  `type` ENUM('arrest', 'search_property', 'search_vehicle') NOT NULL,
  `target_entity_id` VARCHAR(64) NULL,
  `probable_cause_summary` TEXT NOT NULL,
  `status` ENUM('active', 'executed', 'expired', 'rescinded') DEFAULT 'active',
  `expires_at` TIMESTAMP NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_warrant_target` (`target_citizen_id`),
  INDEX `idx_warrant_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Civic jury duty assignment registry
CREATE TABLE IF NOT EXISTS `nyx_judiciary_juries` (
  `jury_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `docket_id` VARCHAR(32) NOT NULL,
  `citizen_id` VARCHAR(16) NOT NULL,
  `selection_status` ENUM('summoned', 'excused', 'seated', 'voted') DEFAULT 'summoned',
  `secret_ballot` ENUM('guilty', 'not_guilty', 'abstain') NULL,
  `assigned_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_juror_per_case` (`docket_id`, `citizen_id`),
  FOREIGN KEY (`docket_id`) REFERENCES `nyx_judiciary_dockets`(`docket_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
