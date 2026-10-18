-- ============================================================================
-- Nyxframework: nyx_services & nyx_inventory
-- Migration: 061_hospital_bed_maintenance_and_clinical_recovery.sql
-- Description: Physical hospital bed infrastructure, clinical triage admission,
--              hemodynamic vital monitors, bed maintenance/soiling cycles,
--              and automated IV infusion from finite hospital supply stashes.
-- ============================================================================

-- 1. Create table for physical hospital beds
CREATE TABLE IF NOT EXISTS `nyx_services_hospital_beds` (
  `bed_id` VARCHAR(64) NOT NULL PRIMARY KEY,
  `bed_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `hospital_id` VARCHAR(32) NOT NULL,
  `bed_label` VARCHAR(64) NOT NULL,
  `bed_type` ENUM('icu_trauma', 'general_ward', 'emergency_cot') NOT NULL DEFAULT 'general_ward',
  `coords` JSON NOT NULL,
  `occupied_by_citizen_id` VARCHAR(64) NULL DEFAULT NULL,
  `is_occupied` TINYINT(1) NOT NULL DEFAULT 0,
  `bed_cleanliness` DECIMAL(5,2) NOT NULL DEFAULT 100.00,
  `maintenance_status` ENUM('clean', 'occupied', 'soiled', 'sanitizing', 'offline_power') NOT NULL DEFAULT 'clean',
  `vital_monitor_active` TINYINT(1) NOT NULL DEFAULT 1,
  `iv_drip_active` TINYINT(1) NOT NULL DEFAULT 0,
  `current_infusion_item` VARCHAR(64) NULL DEFAULT NULL,
  `admission_timestamp` TIMESTAMP NULL DEFAULT NULL,
  `last_sanitized_at` TIMESTAMP NULL DEFAULT NULL,
  `total_patients_treated` INT NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_hospital_beds_hospital` (`hospital_id`),
  INDEX `idx_hospital_beds_status` (`maintenance_status`),
  INDEX `idx_hospital_beds_occupied` (`is_occupied`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Create immutable audit ledger for hospital bed events and treatment records
CREATE TABLE IF NOT EXISTS `nyx_services_hospital_bed_audits` (
  `audit_id` INT AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `bed_id` VARCHAR(64) NOT NULL,
  `hospital_id` VARCHAR(32) NOT NULL,
  `citizen_id` VARCHAR(64) NULL,
  `action` ENUM('ADMITTED', 'DISCHARGED', 'TREATMENT_APPLIED', 'CONSUMABLE_INFUSED', 'SOILED', 'SANITIZED', 'POWER_LOST', 'POWER_RESTORED') NOT NULL,
  `item_consumed` VARCHAR(64) NULL,
  `quantity` INT NULL DEFAULT 0,
  `vital_telemetry` JSON NULL,
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_bed_audit_bed` (`bed_id`),
  INDEX `idx_bed_audit_cit` (`citizen_id`),
  INDEX `idx_bed_audit_action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Seed canonical hospital beds across Los Santos and Blaine County
INSERT INTO `nyx_services_hospital_beds`
  (`bed_id`, `bed_uuid`, `hospital_id`, `bed_label`, `bed_type`, `coords`, `is_occupied`, `bed_cleanliness`, `maintenance_status`, `vital_monitor_active`)
VALUES
  ('bed:pillbox:01', 'bed-pillbox-icu-01', 'pillbox_hill', 'Pillbox ICU Trauma Bed #01', 'icu_trauma', '{"x": 348.0, "y": -1445.0, "z": 32.5, "w": 90.0}', 0, 100.00, 'clean', 1),
  ('bed:pillbox:02', 'bed-pillbox-icu-02', 'pillbox_hill', 'Pillbox ICU Trauma Bed #02', 'icu_trauma', '{"x": 352.0, "y": -1445.0, "z": 32.5, "w": 90.0}', 0, 100.00, 'clean', 1),
  ('bed:pillbox:03', 'bed-pillbox-ward-03', 'pillbox_hill', 'Pillbox General Ward Bed #03', 'general_ward', '{"x": 356.0, "y": -1445.0, "z": 32.5, "w": 90.0}', 0, 100.00, 'clean', 1),
  ('bed:pillbox:04', 'bed-pillbox-ward-04', 'pillbox_hill', 'Pillbox General Ward Bed #04', 'general_ward', '{"x": 360.0, "y": -1445.0, "z": 32.5, "w": 90.0}', 0, 100.00, 'clean', 1),
  ('bed:sandy:01', 'bed-sandy-ward-01', 'sandy_shores_clinic', 'Sandy Shores Clinic Ward Bed #01', 'general_ward', '{"x": 1835.0, "y": 3678.0, "z": 34.3, "w": 180.0}', 0, 100.00, 'clean', 1),
  ('bed:sandy:02', 'bed-sandy-cot-02', 'sandy_shores_clinic', 'Sandy Shores Emergency Cot #02', 'emergency_cot', '{"x": 1838.0, "y": 3678.0, "z": 34.3, "w": 180.0}', 0, 100.00, 'clean', 0),
  ('bed:paleto:01', 'bed-paleto-ward-01', 'paleto_bay_hospital', 'Paleto Bay General Bed #01', 'general_ward', '{"x": -252.0, "y": 6325.0, "z": 32.4, "w": 270.0}', 0, 100.00, 'clean', 1),
  ('bed:paleto:02', 'bed-paleto-cot-02', 'paleto_bay_hospital', 'Paleto Bay Emergency Cot #02', 'emergency_cot', '{"x": -255.0, "y": 6325.0, "z": 32.4, "w": 270.0}', 0, 100.00, 'clean', 0)
ON DUPLICATE KEY UPDATE `coords` = VALUES(`coords`), `bed_label` = VALUES(`bed_label`);
