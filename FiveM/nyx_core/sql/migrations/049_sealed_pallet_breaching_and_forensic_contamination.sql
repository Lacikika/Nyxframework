-- ============================================================================
-- Nyxframework Logistics & Judiciary Engine Migration
-- Migration: 049_sealed_pallet_breaching_and_forensic_contamination.sql
-- Description: Tamper-evident freight pallet security seals, physical crowbar
--              breach tracking, microscopic toolmark evidence ('toolmark'),
--              latent fingerprint & DNA contamination, and breach audit ledger.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Extend nyx_judiciary_evidence with 'toolmark' Forensic Evidence Type
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_judiciary_evidence`
  MODIFY COLUMN `type` ENUM('casing', 'blood', 'fingerprint', 'swab', 'photo', 'document', 'ballistics', 'toolmark') NOT NULL;

-- ----------------------------------------------------------------------------
-- 2. Extend nyx_logistics_pallets with Tamper & Security Seal Columns
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_logistics_pallets`
  ADD COLUMN IF NOT EXISTS `is_tampered` TINYINT(1) NOT NULL DEFAULT 0 AFTER `is_sealed`,
  ADD COLUMN IF NOT EXISTS `seal_serial` VARCHAR(32) NULL AFTER `is_tampered`,
  ADD COLUMN IF NOT EXISTS `sealed_at` TIMESTAMP NULL AFTER `seal_serial`,
  ADD COLUMN IF NOT EXISTS `sealed_by_citizen_id` VARCHAR(64) NULL AFTER `sealed_at`,
  ADD COLUMN IF NOT EXISTS `breached_at` TIMESTAMP NULL AFTER `sealed_by_citizen_id`,
  ADD COLUMN IF NOT EXISTS `breached_by_citizen_id` VARCHAR(64) NULL AFTER `breached_at`,
  ADD COLUMN IF NOT EXISTS `tamper_tool` VARCHAR(32) NULL AFTER `breached_by_citizen_id`,
  ADD COLUMN IF NOT EXISTS `forensic_evidence_ids` JSON NULL AFTER `tamper_tool`;

-- ----------------------------------------------------------------------------
-- 3. Create Immutable Audit Ledger for Pallet Breaches & Forensic Events
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_logistics_pallet_breach_audits` (
  `audit_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `pallet_id` VARCHAR(64) NOT NULL,
  `citizen_id` VARCHAR(64) NOT NULL,
  `tool_used` VARCHAR(32) NOT NULL,
  `tool_serial` VARCHAR(64) NULL,
  `success` TINYINT(1) NOT NULL DEFAULT 1,
  `alarm_triggered` TINYINT(1) NOT NULL DEFAULT 0,
  `dna_left` TINYINT(1) NOT NULL DEFAULT 0,
  `fingerprint_left` TINYINT(1) NOT NULL DEFAULT 0,
  `toolmark_left` TINYINT(1) NOT NULL DEFAULT 1,
  `evidence_hashes` JSON NULL,
  `coords` JSON NULL,
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  INDEX `idx_pba_pallet` (`pallet_id`),
  INDEX `idx_pba_citizen` (`citizen_id`),
  INDEX `idx_pba_tool` (`tool_used`),
  INDEX `idx_pba_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;
