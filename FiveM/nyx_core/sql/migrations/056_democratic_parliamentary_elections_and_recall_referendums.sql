-- ============================================================================
-- Nyxframework: nyx_parliament & nyx_ui
-- Migration: 056_democratic_parliamentary_elections_and_recall_referendums.sql
-- Description: Democratic parliamentary elections lifecycle (nomination & voting phases),
--              candidate signatures, collateral escrow tracking, physical voting
--              booth terminals, automated term limit expiration, and recall referendums.
-- ============================================================================

-- 1. Extend sessions table with election lifecycle phases, targeted office, and nomination deadlines
ALTER TABLE `nyx_parliament_sessions`
  ADD COLUMN IF NOT EXISTS `election_phase` ENUM('nomination', 'voting', 'tallying', 'concluded') DEFAULT 'voting' AFTER `type`,
  ADD COLUMN IF NOT EXISTS `office_id` VARCHAR(32) NULL AFTER `category`,
  ADD COLUMN IF NOT EXISTS `nomination_ends_at` TIMESTAMP NULL AFTER `starts_at`,
  ADD COLUMN IF NOT EXISTS `total_turnout` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `winner_option`;

-- 2. Extend candidates table with collateral status, refund ledger tracking, and vote counts
ALTER TABLE `nyx_parliament_candidates`
  ADD COLUMN IF NOT EXISTS `collateral_status` ENUM('escrowed', 'refunded', 'forfeited') DEFAULT 'escrowed' AFTER `collateral_deposited`,
  ADD COLUMN IF NOT EXISTS `refund_treasury_tx_id` VARCHAR(64) NULL AFTER `collateral_status`,
  ADD COLUMN IF NOT EXISTS `vote_count` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `endorsements_count`,
  ADD COLUMN IF NOT EXISTS `vote_percentage` DECIMAL(5, 2) NOT NULL DEFAULT 0.00 AFTER `vote_count`;

-- 3. Extend ballots with physical voting booth terminal provenance
ALTER TABLE `nyx_parliament_ballots`
  ADD COLUMN IF NOT EXISTS `booth_id` VARCHAR(32) DEFAULT 'remote' AFTER `ballot_hash`,
  ADD COLUMN IF NOT EXISTS `booth_label` VARCHAR(96) DEFAULT 'Remote Terminal' AFTER `booth_id`;

-- 4. Extend officials with recall immunity cooldown and consecutive term tracking
ALTER TABLE `nyx_parliament_officials`
  ADD COLUMN IF NOT EXISTS `cooldown_until` TIMESTAMP NULL AFTER `term_end`,
  ADD COLUMN IF NOT EXISTS `consecutive_terms` INT UNSIGNED NOT NULL DEFAULT 1 AFTER `status`;

-- 5. Extend recall petitions with target citizen and immunity cooldown tracking
ALTER TABLE `nyx_parliament_recall_petitions`
  ADD COLUMN IF NOT EXISTS `target_citizen_id` VARCHAR(64) NULL AFTER `office_id`,
  ADD COLUMN IF NOT EXISTS `cooldown_expires_at` TIMESTAMP NULL AFTER `expires_at`;

-- 6. Immutable official term and civic succession audit ledger
CREATE TABLE IF NOT EXISTS `nyx_parliament_term_audits` (
  `audit_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `office_id` VARCHAR(32) NOT NULL,
  `citizen_id` VARCHAR(64) NOT NULL,
  `display_name` VARCHAR(96) NOT NULL,
  `event_type` ENUM('instated', 'term_expired', 'recalled', 'resigned', 'election_scheduled') NOT NULL,
  `session_id` VARCHAR(64) NULL,
  `reason` VARCHAR(255) NULL,
  `notes` TEXT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_term_audit_office` (`office_id`),
  INDEX `idx_term_audit_citizen` (`citizen_id`),
  INDEX `idx_term_audit_event` (`event_type`),
  INDEX `idx_term_audit_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 7. Physical civic voting booth terminals registry
CREATE TABLE IF NOT EXISTS `nyx_parliament_booth_terminals` (
  `booth_id` VARCHAR(32) PRIMARY KEY,
  `label` VARCHAR(96) NOT NULL,
  `location_zone` VARCHAR(64) NOT NULL,
  `coords` JSON NOT NULL,
  `total_ballots_cast` INT UNSIGNED NOT NULL DEFAULT 0,
  `is_active` TINYINT NOT NULL DEFAULT 1,
  `last_ping_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_booth_active` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 8. Seed canonical voting booth terminals
INSERT IGNORE INTO `nyx_parliament_booth_terminals` (`booth_id`, `label`, `location_zone`, `coords`, `is_active`) VALUES
('booth:city_hall', 'City Hall Council Voting Booth', 'Downtown Los Santos', '{"x": -540.9, "y": -199.3, "z": 47.5}', 1),
('booth:sandy_shores', 'Sandy Shores Regional Ballot Station', 'Sandy Shores', '{"x": 1853.2, "y": 3686.9, "z": 34.3}', 1),
('booth:paleto_bay', 'Paleto Bay Justice Center Ballot Station', 'Paleto Bay', '{"x": -448.2, "y": 6012.3, "z": 31.7}', 1);

-- 9. Seed canonical initial Mayoral election session binding to office 'mayor'
UPDATE `nyx_parliament_sessions`
  SET `office_id` = 'mayor', `election_phase` = 'voting'
  WHERE `session_id` = 'election:mayor_2026';
