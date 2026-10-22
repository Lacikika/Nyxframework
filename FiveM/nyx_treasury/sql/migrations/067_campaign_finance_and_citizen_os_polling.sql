-- ============================================================================
-- Nyxframework: nyx_parliament, nyx_treasury, nyx_ui
-- Migration: 067_campaign_finance_and_citizen_os_polling.sql
-- Description: Political Action Committees (PACs), statutory campaign finance donation
--              caps, independent PAC compliance auditing & statutory fines, and
--              Citizen OS mobile opinion surveys & voter sentiment polling.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Political Action Committees (PACs) Registry
CREATE TABLE IF NOT EXISTS `nyx_parliament_pacs` (
  `pac_id` VARCHAR(64) PRIMARY KEY,
  `candidate_id` VARCHAR(64) NULL,
  `office_id` VARCHAR(32) NULL,
  `title` VARCHAR(128) NOT NULL,
  `treasurer_citizen_id` VARCHAR(16) NOT NULL,
  `balance` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `total_donations_collected` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `status` ENUM('active', 'audited', 'suspended', 'dissolved') NOT NULL DEFAULT 'active',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_pac_candidate` (`candidate_id`),
  INDEX `idx_pac_office` (`office_id`),
  INDEX `idx_pac_treasurer` (`treasurer_citizen_id`),
  INDEX `idx_pac_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Campaign Finance Donations Ledger
CREATE TABLE IF NOT EXISTS `nyx_parliament_donations` (
  `donation_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `donation_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `pac_id` VARCHAR(64) NOT NULL,
  `donor_citizen_id` VARCHAR(16) NOT NULL,
  `donor_faction_id` VARCHAR(64) NULL,
  `amount` DECIMAL(15, 2) NOT NULL,
  `cap_limit_applied` DECIMAL(15, 2) NOT NULL DEFAULT 5000.00,
  `compliance_status` ENUM('compliant', 'flagged_over_cap', 'refunded', 'audited') NOT NULL DEFAULT 'compliant',
  `treasury_tx_uuid` VARCHAR(36) NULL,
  `donated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_donation_pac` (`pac_id`),
  INDEX `idx_donation_donor` (`donor_citizen_id`),
  INDEX `idx_donation_compliance` (`compliance_status`),
  INDEX `idx_donation_created` (`donated_at` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. PAC Statutory Compliance Audits Ledger
CREATE TABLE IF NOT EXISTS `nyx_parliament_pac_audits` (
  `audit_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `pac_id` VARCHAR(64) NOT NULL,
  `auditor_citizen_id` VARCHAR(16) NOT NULL DEFAULT 'SYSTEM_PAC_AUDITOR',
  `total_audited_contributions` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `flagged_excess_amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `fine_assessed` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `audit_status` ENUM('passed', 'violations_found', 'fines_assessed', 'cleared') NOT NULL DEFAULT 'passed',
  `notes` VARCHAR(255) NULL,
  `audited_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_pac_audit_pac` (`pac_id`),
  INDEX `idx_pac_audit_status` (`audit_status`),
  INDEX `idx_pac_audit_created` (`audited_at` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Citizen OS Mobile Opinion Surveys & Sentiment Polls
CREATE TABLE IF NOT EXISTS `nyx_parliament_polls` (
  `poll_id` VARCHAR(64) PRIMARY KEY,
  `title` VARCHAR(128) NOT NULL,
  `description` TEXT NOT NULL,
  `creator_citizen_id` VARCHAR(16) NOT NULL DEFAULT 'SYSTEM_GOV',
  `poll_type` ENUM('approval_rating', 'policy_survey', 'civic_referendum') NOT NULL DEFAULT 'policy_survey',
  `office_id` VARCHAR(32) NULL,
  `options_json` JSON NOT NULL,
  `total_responses` INT UNSIGNED NOT NULL DEFAULT 0,
  `starts_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ends_at` TIMESTAMP NOT NULL,
  `status` ENUM('active', 'concluded', 'archived') NOT NULL DEFAULT 'active',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_poll_status` (`status`),
  INDEX `idx_poll_office` (`office_id`),
  INDEX `idx_poll_ends` (`ends_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 5. Citizen OS Mobile Poll Responses Registry
CREATE TABLE IF NOT EXISTS `nyx_parliament_poll_responses` (
  `response_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `poll_id` VARCHAR(64) NOT NULL,
  `citizen_id` VARCHAR(16) NOT NULL,
  `voter_hash` VARCHAR(64) NOT NULL,
  `selected_option` VARCHAR(64) NOT NULL,
  `device_os` VARCHAR(32) NOT NULL DEFAULT 'CitizenOS_Mobile',
  `submitted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_poll_citizen` (`poll_id`, `citizen_id`),
  UNIQUE KEY `uk_poll_hash` (`poll_id`, `voter_hash`),
  INDEX `idx_poll_resp_poll` (`poll_id`),
  INDEX `idx_poll_resp_citizen` (`citizen_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 6. Seed Campaign Finance PAC Escrow Account in nyx_treasury_accounts
INSERT INTO `nyx_treasury_accounts`
  (`account_id`, `label`, `balance`, `type`, `signatories_required`)
VALUES
  ('gov:escrow:pac', 'Municipal Campaign Finance PAC Reserve Account', 0.00, 'reserve', 1)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

SET FOREIGN_KEY_CHECKS = 1;
