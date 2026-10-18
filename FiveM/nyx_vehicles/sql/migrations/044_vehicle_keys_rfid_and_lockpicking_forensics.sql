-- ============================================================================
-- Nyxframework: nyx_vehicles & nyx_inventory & nyx_judiciary
-- Migration: 044_vehicle_keys_rfid_and_lockpicking_forensics.sql
-- Description: Physical metadata vehicle keys, corporate fleet RFID tokens,
--              lockpicking attempts audit, and latent fingerprint evidence forensics.
-- ============================================================================

-- Corporate & organizational RFID fleet access tokens
CREATE TABLE IF NOT EXISTS `nyx_vehicles_rfid_tokens` (
  `token_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `token_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `faction_id` VARCHAR(32) NOT NULL,
  `holder_citizen_id` VARCHAR(16) NULL,
  `access_level` ENUM('driver', 'manager', 'executive', 'admin') DEFAULT 'driver',
  `label` VARCHAR(64) NOT NULL DEFAULT 'Corporate Fleet Keycard',
  `is_revoked` TINYINT(1) NOT NULL DEFAULT 0,
  `revoked_by` VARCHAR(16) NULL,
  `revocation_reason` VARCHAR(255) NULL,
  `expires_at` TIMESTAMP NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_rfid_faction` (`faction_id`),
  INDEX `idx_rfid_holder` (`holder_citizen_id`),
  INDEX `idx_rfid_uuid` (`token_uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Audit trail for vehicle lockpicking, hotwiring, and forensic fingerprint linkage
CREATE TABLE IF NOT EXISTS `nyx_vehicles_lockpick_attempts` (
  `attempt_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `attempt_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `vin` VARCHAR(32) NOT NULL,
  `plate` VARCHAR(12) NOT NULL,
  `citizen_id` VARCHAR(16) NOT NULL,
  `action_type` ENUM('door_lockpick', 'ignition_hotwire') DEFAULT 'door_lockpick',
  `success` TINYINT(1) NOT NULL DEFAULT 0,
  `alarm_triggered` TINYINT(1) NOT NULL DEFAULT 0,
  `tool_used` VARCHAR(32) NOT NULL DEFAULT 'tool_lockpick',
  `tool_broken` TINYINT(1) NOT NULL DEFAULT 0,
  `had_gloves` TINYINT(1) NOT NULL DEFAULT 0,
  `fingerprint_evidence_id` VARCHAR(64) NULL,
  `fingerprint_hash` VARCHAR(64) NULL,
  `coords` JSON NULL,
  `notes` VARCHAR(255) NULL,
  `attempted_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_lp_vin` (`vin`),
  INDEX `idx_lp_plate` (`plate`),
  INDEX `idx_lp_citizen` (`citizen_id`),
  INDEX `idx_lp_evidence` (`fingerprint_evidence_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Alter nyx_vehicles_owned to store transient hotwire and alarm states if needed
ALTER TABLE `nyx_vehicles_owned`
  ADD COLUMN IF NOT EXISTS `hotwired` TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `alarm_state` TINYINT(1) NOT NULL DEFAULT 0;

-- Seed default corporate RFID tokens
INSERT INTO `nyx_vehicles_rfid_tokens`
  (`token_uuid`, `faction_id`, `holder_citizen_id`, `access_level`, `label`, `is_revoked`, `expires_at`)
VALUES
  ('rfid-corp-logistics-master', 'corp_logistics', NULL, 'executive', 'OmniLogistics Master Fleet Keycard', 0, NULL),
  ('rfid-police-patrol-fleet', 'police', NULL, 'driver', 'LSPD Patrol Vehicle Proximity Token', 0, NULL),
  ('rfid-ems-ambulance-fleet', 'ems', NULL, 'driver', 'Pillbox EMS Emergency Vehicle Transponder', 0, NULL)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);
