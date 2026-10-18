-- ============================================================================
-- Nyxframework Judiciary & Forensic Engine Database Migration
-- File: 015_judiciary_evidence_chain_of_custody.sql
-- Description: Immutable Cryptographic Evidence Chain-of-Custody Ledger,
--              Block Hash Chaining (SHA-256), Forensic Lab Analysis Results,
--              and Secure Vault / Evidence Locker Depository.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Enhance Base Evidence Table with Extended Types and Custody Tracking
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_judiciary_evidence`
  MODIFY COLUMN `type` ENUM('casing', 'blood', 'fingerprint', 'swab', 'photo', 'document', 'ballistics') NOT NULL,
  ADD COLUMN IF NOT EXISTS `current_custodian_id` VARCHAR(16) NULL AFTER `collector_citizen_id`,
  ADD COLUMN IF NOT EXISTS `current_facility` VARCHAR(64) NULL AFTER `current_custodian_id`,
  ADD COLUMN IF NOT EXISTS `current_chain_hash` VARCHAR(64) NULL AFTER `evidence_hash`,
  ADD COLUMN IF NOT EXISTS `chain_length` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `current_chain_hash`,
  ADD COLUMN IF NOT EXISTS `is_sealed` TINYINT(1) NOT NULL DEFAULT 1 AFTER `is_contaminated`,
  ADD COLUMN IF NOT EXISTS `lab_analysis` JSON NULL AFTER `metadata`,
  ADD COLUMN IF NOT EXISTS `exhibit_label` VARCHAR(32) NULL AFTER `docket_id`;

-- ----------------------------------------------------------------------------
-- 2. Cryptographic Chain-of-Custody Ledger (Immutable Audit Blocks)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_judiciary_chain_of_custody` (
  `log_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `evidence_id` VARCHAR(36) NOT NULL,
  `sequence_id` INT UNSIGNED NOT NULL,
  `action` ENUM('COLLECTED', 'TRANSFERRED', 'SECURED_IN_LOCKER', 'CHECKED_OUT_LAB', 'LAB_ANALYZED', 'SUBMITTED_EXHIBIT', 'RELEASED_TO_OWNER', 'DESTROYED') NOT NULL,
  `custodian_citizen_id` VARCHAR(16) NOT NULL,
  `recipient_citizen_id` VARCHAR(16) NULL,
  `facility_id` VARCHAR(64) NULL,
  `previous_hash` VARCHAR(64) NOT NULL,
  `entry_hash` VARCHAR(64) NOT NULL UNIQUE,
  `notes` VARCHAR(255) NULL,
  `metadata` JSON NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT `fk_custody_evidence` FOREIGN KEY (`evidence_id`) REFERENCES `nyx_judiciary_evidence` (`evidence_id`) ON DELETE CASCADE,
  UNIQUE KEY `uk_evidence_seq` (`evidence_id`, `sequence_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- 3. B-Tree Indexes for Real-Time Hash Verification & Audit Queries
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS `idx_custody_evidence` ON `nyx_judiciary_chain_of_custody` (`evidence_id`, `sequence_id`);
CREATE INDEX IF NOT EXISTS `idx_custody_custodian` ON `nyx_judiciary_chain_of_custody` (`custodian_citizen_id`);
CREATE INDEX IF NOT EXISTS `idx_custody_entry_hash` ON `nyx_judiciary_chain_of_custody` (`entry_hash`);
CREATE INDEX IF NOT EXISTS `idx_evidence_custodian` ON `nyx_judiciary_evidence` (`current_custodian_id`);
CREATE INDEX IF NOT EXISTS `idx_evidence_facility` ON `nyx_judiciary_evidence` (`current_facility`);
