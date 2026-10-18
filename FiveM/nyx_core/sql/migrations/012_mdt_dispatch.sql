-- ============================================================================
-- Nyxframework Emergency Services Mobile Data Terminal (MDT) Migration
-- File: 012_mdt_dispatch.sql
-- Description: Emergency Dispatch (911/CAD), Criminal Citations, Fines,
--              Incident Reporting & Inter-Agency Coordination.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Segélyhívási & CAD Esemény Nyilvántartás (Emergency Dispatch Feed)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_mdt_calls` (
  `call_id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `code` VARCHAR(16) NOT NULL DEFAULT '10-99',
  `title` VARCHAR(128) NOT NULL,
  `description` TEXT NULL,
  `caller` VARCHAR(64) NOT NULL DEFAULT 'Anonymus',
  `coords` JSON NOT NULL,
  `location_label` VARCHAR(128) NOT NULL,
  `priority` ENUM('low', 'medium', 'high', 'critical') NOT NULL DEFAULT 'medium',
  `status` ENUM('active', 'assigned', 'closed') NOT NULL DEFAULT 'active',
  `assigned_unit` VARCHAR(32) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `closed_at` TIMESTAMP NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 2. Hatósági Bírságok & Pénzügyi Követelések (Citations & Direct Debits)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_mdt_fines` (
  `fine_id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `target_citizen_id` VARCHAR(16) NOT NULL,
  `officer_citizen_id` VARCHAR(16) NOT NULL,
  `charge_title` VARCHAR(128) NOT NULL,
  `amount` DECIMAL(15, 2) NOT NULL CHECK (`amount` >= 0.00),
  `treasury_tx_uuid` VARCHAR(36) NULL,
  `status` ENUM('paid', 'debited', 'delinquent') NOT NULL DEFAULT 'debited',
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT `fk_mdt_fine_target` FOREIGN KEY (`target_citizen_id`) REFERENCES `nyx_characters` (`citizen_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_mdt_fine_officer` FOREIGN KEY (`officer_citizen_id`) REFERENCES `nyx_characters` (`citizen_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 3. Rendőrségi & Bírósági Eseménynaplók (Incident Reports)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_mdt_reports` (
  `report_id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `title` VARCHAR(128) NOT NULL,
  `author_citizen_id` VARCHAR(16) NOT NULL,
  `incident_type` VARCHAR(64) NOT NULL DEFAULT 'felony',
  `summary` TEXT NOT NULL,
  `involved_citizens` JSON NULL,
  `evidence_hashes` JSON NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT `fk_mdt_report_author` FOREIGN KEY (`author_citizen_id`) REFERENCES `nyx_characters` (`citizen_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- 4. B-Fa Indexek a Valós Idejű Lekérdezésekhez
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS `idx_mdt_call_feed` ON `nyx_mdt_calls` (`status`, `priority`, `created_at` DESC);
CREATE INDEX IF NOT EXISTS `idx_mdt_fine_target` ON `nyx_mdt_fines` (`target_citizen_id`, `status`);
CREATE INDEX IF NOT EXISTS `idx_mdt_report_timeline` ON `nyx_mdt_reports` (`incident_type`, `created_at` DESC);
