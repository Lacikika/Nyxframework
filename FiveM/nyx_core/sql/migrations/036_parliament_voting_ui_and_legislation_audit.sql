-- ============================================================================
-- Nyxframework: nyx_parliament & nyx_ui
-- Migration: 036_parliament_voting_ui_and_legislation_audit.sql
-- Description: Immutable legislative amendment audit history, session categories,
--              campaign metadata, and voting station terminal integration.
-- ============================================================================

-- 1. Immutable audit ledger of all enacted legislative and penal amendments
CREATE TABLE IF NOT EXISTS `nyx_parliament_amendment_audit` (
  `audit_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `session_id` VARCHAR(64) NOT NULL,
  `law_id` VARCHAR(32) NOT NULL,
  `field` VARCHAR(32) NOT NULL,
  `old_value` DECIMAL(12, 4) NULL,
  `new_value` DECIMAL(12, 4) NOT NULL,
  `enacted_by_session_title` VARCHAR(128) NOT NULL,
  `enacted_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_amend_law` (`law_id`),
  INDEX `idx_amend_session` (`session_id`),
  FOREIGN KEY (`session_id`) REFERENCES `nyx_parliament_sessions`(`session_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Enhance sessions with sponsoring citizen and legislative classification
ALTER TABLE `nyx_parliament_sessions`
  ADD COLUMN IF NOT EXISTS `sponsor_citizen_id` VARCHAR(64) NULL AFTER `description`,
  ADD COLUMN IF NOT EXISTS `category` VARCHAR(32) DEFAULT 'general' AFTER `type`;

-- 3. Enhance candidates with campaign slogan
ALTER TABLE `nyx_parliament_candidates`
  ADD COLUMN IF NOT EXISTS `campaign_slogan` VARCHAR(128) NULL AFTER `party_affiliation`;
