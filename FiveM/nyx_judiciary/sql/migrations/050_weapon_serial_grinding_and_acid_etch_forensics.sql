-- ============================================================================
-- Nyxframework Inventory & Judiciary Engine Migration
-- Migration: 050_weapon_serial_grinding_and_acid_etch_forensics.sql
-- Description: Weapon serial grinding tracking, forensic acid-etch laboratory
--              restoration ('weapon' evidence type, etching audits & cold cases).
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Extend nyx_judiciary_evidence with 'weapon' Forensic Evidence Type
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_judiciary_evidence`
  MODIFY COLUMN `type` ENUM('casing', 'blood', 'fingerprint', 'swab', 'photo', 'document', 'ballistics', 'toolmark', 'weapon') NOT NULL;

-- ----------------------------------------------------------------------------
-- 2. Create Ground Weapons Registry (Persistent Record for Obliterated Serials)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_inventory_ground_weapons` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `weapon_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `weapon_item` VARCHAR(64) NOT NULL,
  `original_serial` VARCHAR(64) NOT NULL,
  `restored_serial` VARCHAR(64) NULL,
  `restoration_status` ENUM('UNETCHED', 'FULL', 'PARTIAL', 'FAILED') NOT NULL DEFAULT 'UNETCHED',
  `grind_quality` INT NOT NULL DEFAULT 85,
  `grinded_by_citizen_id` VARCHAR(64) NULL,
  `grinded_at` TIMESTAMP NULL,
  `tool_serial` VARCHAR(64) NULL,
  `etched_by_citizen_id` VARCHAR(64) NULL,
  `etched_at` TIMESTAMP NULL,
  `evidence_id` VARCHAR(64) NULL,
  `lab_notes` TEXT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  INDEX `idx_gw_weapon_uuid` (`weapon_uuid`),
  INDEX `idx_gw_original_serial` (`original_serial`),
  INDEX `idx_gw_restored_serial` (`restored_serial`),
  INDEX `idx_gw_grinded_by` (`grinded_by_citizen_id`),
  INDEX `idx_gw_etched_by` (`etched_by_citizen_id`),
  INDEX `idx_gw_status` (`restoration_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 3. Create Immutable Audit Ledger for Forensic Acid-Etch Restorations
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_judiciary_acid_etch_audits` (
  `audit_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `weapon_uuid` VARCHAR(64) NOT NULL,
  `weapon_item` VARCHAR(64) NOT NULL,
  `technician_citizen_id` VARCHAR(64) NOT NULL,
  `facility_id` VARCHAR(64) NOT NULL,
  `original_serial` VARCHAR(64) NOT NULL,
  `restored_serial` VARCHAR(64) NOT NULL,
  `outcome` ENUM('FULL', 'PARTIAL', 'FAILED') NOT NULL,
  `ballistics_hit_count` INT NOT NULL DEFAULT 0,
  `ballistics_evidence_ids` JSON NULL,
  `report_hash` VARCHAR(64) NULL,
  `lab_notes` TEXT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  INDEX `idx_aea_weapon` (`weapon_uuid`),
  INDEX `idx_aea_technician` (`technician_citizen_id`),
  INDEX `idx_aea_outcome` (`outcome`),
  INDEX `idx_aea_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;
