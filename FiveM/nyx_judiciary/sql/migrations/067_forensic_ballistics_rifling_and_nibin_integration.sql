-- ============================================================================
-- Nyxframework: nyx_judiciary & nyx_mdt
-- Migration: 067_forensic_ballistics_rifling_and_nibin_integration.sql
-- Description: Forensic ballistics engine, barrel rifling microstriation profiles,
--              ejected shell casing firing pin / breech face signature hashing,
--              and National Integrated Ballistic Information Network (NIBIN) database.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Create weapon barrel rifling and mechanical signature profiles table
CREATE TABLE IF NOT EXISTS `nyx_ballistics_rifling_profiles` (
  `weapon_serial` VARCHAR(64) NOT NULL PRIMARY KEY,
  `weapon_model` VARCHAR(64) NOT NULL,
  `caliber` VARCHAR(32) NOT NULL,
  `rifling_twist` VARCHAR(32) NOT NULL DEFAULT '1:10_RIGHT',
  `groove_count` INT NOT NULL DEFAULT 6,
  `breech_face_hash` VARCHAR(64) NOT NULL,
  `firing_pin_hash` VARCHAR(64) NOT NULL,
  `rifling_microstriation_hash` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_ballistics_model` (`weapon_model`),
  INDEX `idx_ballistics_caliber` (`caliber`),
  INDEX `idx_ballistics_rifling_hash` (`rifling_microstriation_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Create National Integrated Ballistic Information Network (NIBIN) correlation database
CREATE TABLE IF NOT EXISTS `nyx_nibin_database` (
  `entry_id` VARCHAR(64) NOT NULL PRIMARY KEY,
  `evidence_id` VARCHAR(64) NOT NULL,
  `weapon_serial` VARCHAR(64) NULL,
  `casing_ejection_hash` VARCHAR(64) NOT NULL,
  `rifling_hash` VARCHAR(64) NOT NULL,
  `caliber` VARCHAR(32) NOT NULL,
  `crime_scene_docket_id` VARCHAR(64) NULL,
  `registered_by_citizen_id` VARCHAR(64) NOT NULL,
  `match_status` ENUM('UNMATCHED', 'CANDIDATE_MATCH', 'CONFIRMED_MATCH') NOT NULL DEFAULT 'UNMATCHED',
  `matched_entry_id` VARCHAR(64) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_nibin_evidence` (`evidence_id`),
  INDEX `idx_nibin_serial` (`weapon_serial`),
  INDEX `idx_nibin_casing_hash` (`casing_ejection_hash`),
  INDEX `idx_nibin_rifling_hash` (`rifling_hash`),
  INDEX `idx_nibin_status` (`match_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;
