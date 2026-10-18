-- ============================================================================
-- Nyxframework: nyx_services
-- Migration: 041_anatomical_trauma_and_medical_injury_engine.sql
-- Description: Limb-specific anatomical trauma, dynamic hemodynamics,
--              hypovolemic shock, and field medical stabilization logs.
-- ============================================================================

-- 1. Persistent Anatomical Trauma State
CREATE TABLE IF NOT EXISTS `nyx_medical_trauma` (
  `citizen_id` VARCHAR(16) PRIMARY KEY,
  `blood_volume_ml` INT NOT NULL DEFAULT 5000,
  `bleeding_rate` DECIMAL(6, 2) NOT NULL DEFAULT 0.00,
  `pain_level` INT NOT NULL DEFAULT 0,
  `wounds_json` JSON NOT NULL,
  `is_unconscious` TINYINT(1) NOT NULL DEFAULT 0,
  `last_updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_citizen_trauma` (`citizen_id`),
  INDEX `idx_trauma_unconscious` (`is_unconscious`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Immutable Field Medical Treatments & Diagnostics Audit Log
CREATE TABLE IF NOT EXISTS `nyx_medical_treatments_log` (
  `log_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `treatment_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `patient_citizen_id` VARCHAR(16) NOT NULL,
  `medic_citizen_id` VARCHAR(16) NOT NULL,
  `item_used` VARCHAR(48) NOT NULL,
  `target_limb` VARCHAR(24) NOT NULL,
  `treatment_type` VARCHAR(32) NOT NULL,
  `blood_volume_before` INT NOT NULL,
  `blood_volume_after` INT NOT NULL,
  `treated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_patient` (`patient_citizen_id`),
  INDEX `idx_medic` (`medic_citizen_id`),
  INDEX `idx_treated_at` (`treated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
