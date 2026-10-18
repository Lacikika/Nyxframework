-- ============================================================================
-- Nyxframework Judiciary & Forensic Engine Database Migration
-- File: 035_judiciary_courtroom_terminal_and_evidence_audit.sql
-- Description: Courtroom Terminal Support, Immutable SHA-256 Evidence Chain
--              Verification Audit Logs, and Docket Annotation Fields.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Immutable Forensic Evidence Verification Audit Trail
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_judiciary_evidence_verifications` (
  `verification_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `evidence_id` VARCHAR(36) NOT NULL,
  `verifier_citizen_id` VARCHAR(64) NOT NULL,
  `status` VARCHAR(64) NOT NULL, -- e.g. 'CHAIN_VERIFIED_AUTHENTIC', 'ROOT_EVIDENCE_TAMPERED', 'BLOCK_TAMPER_DETECTED'
  `is_valid` TINYINT(1) NOT NULL DEFAULT 1,
  `chain_length` INT UNSIGNED NOT NULL DEFAULT 0,
  `root_hash` VARCHAR(64) NOT NULL,
  `current_chain_hash` VARCHAR(64) NOT NULL,
  `verified_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_verif_evidence` (`evidence_id`),
  INDEX `idx_verif_citizen` (`verifier_citizen_id`),
  INDEX `idx_verif_time` (`verified_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- 2. Extend Dockets Table with Case Brief & Session Notes
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_judiciary_dockets`
  ADD COLUMN IF NOT EXISTS `case_brief` TEXT NULL DEFAULT NULL AFTER `verdict`,
  ADD COLUMN IF NOT EXISTS `court_notes` TEXT NULL DEFAULT NULL AFTER `case_brief`;

-- ----------------------------------------------------------------------------
-- 3. Extend Evidence Table with Judicial Verification Timestamp
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_judiciary_evidence`
  ADD COLUMN IF NOT EXISTS `verified_by_judge_at` TIMESTAMP NULL DEFAULT NULL AFTER `exhibit_label`;

SET FOREIGN_KEY_CHECKS = 1;
