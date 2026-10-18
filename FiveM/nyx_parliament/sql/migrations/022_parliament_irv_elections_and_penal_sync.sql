-- ============================================================================
-- Nyxframework: nyx_parliament
-- Migration: 022_parliament_irv_elections_and_penal_sync.sql
-- Description: Instant-Runoff Voting (IRV) election candidate registry,
--              elected officials tracking, tabulation audit logs, recall
--              petitions, and comprehensive statutory penal code catalog.
-- ============================================================================

-- 1. Candidate registration and qualification ledger
CREATE TABLE IF NOT EXISTS `nyx_parliament_candidates` (
  `candidate_id` VARCHAR(64) PRIMARY KEY,
  `session_id` VARCHAR(64) NOT NULL,
  `citizen_id` VARCHAR(64) NOT NULL,
  `display_name` VARCHAR(96) NOT NULL,
  `party_affiliation` VARCHAR(96) DEFAULT 'Independent',
  `platform_summary` TEXT NULL,
  `collateral_deposited` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  `endorsements_count` INT UNSIGNED NOT NULL DEFAULT 0,
  `status` ENUM('nominated', 'qualified', 'withdrawn', 'disqualified') DEFAULT 'nominated',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_cand_per_session` (`session_id`, `citizen_id`),
  INDEX `idx_cand_session` (`session_id`),
  INDEX `idx_cand_citizen` (`citizen_id`),
  FOREIGN KEY (`session_id`) REFERENCES `nyx_parliament_sessions`(`session_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Candidate endorsement ledger (prevents double endorsement)
CREATE TABLE IF NOT EXISTS `nyx_parliament_candidate_endorsements` (
  `endorsement_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `candidate_id` VARCHAR(64) NOT NULL,
  `citizen_id` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_endorsement` (`candidate_id`, `citizen_id`),
  INDEX `idx_endorsement_cand` (`candidate_id`),
  FOREIGN KEY (`candidate_id`) REFERENCES `nyx_parliament_candidates`(`candidate_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Elected civic officials and term lifecycle
CREATE TABLE IF NOT EXISTS `nyx_parliament_officials` (
  `office_id` VARCHAR(32) PRIMARY KEY,
  `title` VARCHAR(64) NOT NULL,
  `citizen_id` VARCHAR(64) NOT NULL,
  `display_name` VARCHAR(96) NOT NULL,
  `elected_session_id` VARCHAR(64) NOT NULL,
  `term_start` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `term_end` TIMESTAMP NOT NULL,
  `status` ENUM('active', 'expired', 'recalled', 'resigned') DEFAULT 'active',
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_official_citizen` (`citizen_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Multi-round Instant-Runoff Voting (IRV) tabulation logs
CREATE TABLE IF NOT EXISTS `nyx_parliament_tabulation_logs` (
  `log_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `session_id` VARCHAR(64) NOT NULL,
  `round_number` INT UNSIGNED NOT NULL,
  `continuing_ballots` INT UNSIGNED NOT NULL,
  `exhausted_ballots` INT UNSIGNED NOT NULL,
  `tally_breakdown` JSON NOT NULL,
  `eliminated_candidate` VARCHAR(64) NULL,
  `winner_declared` VARCHAR(64) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_tabulation_session` (`session_id`),
  FOREIGN KEY (`session_id`) REFERENCES `nyx_parliament_sessions`(`session_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 5. Civic recall petitions and signatures
CREATE TABLE IF NOT EXISTS `nyx_parliament_recall_petitions` (
  `petition_id` VARCHAR(64) PRIMARY KEY,
  `office_id` VARCHAR(32) NOT NULL,
  `initiator_citizen_id` VARCHAR(64) NOT NULL,
  `reason` TEXT NOT NULL,
  `signatures_count` INT UNSIGNED NOT NULL DEFAULT 1,
  `required_signatures` INT UNSIGNED NOT NULL DEFAULT 5,
  `status` ENUM('active', 'certified', 'rejected', 'expired') DEFAULT 'active',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `expires_at` TIMESTAMP NOT NULL,
  INDEX `idx_petition_office` (`office_id`),
  FOREIGN KEY (`office_id`) REFERENCES `nyx_parliament_officials`(`office_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nyx_parliament_recall_signatures` (
  `sig_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `petition_id` VARCHAR(64) NOT NULL,
  `citizen_id` VARCHAR(64) NOT NULL,
  `signed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_petition_sig` (`petition_id`, `citizen_id`),
  FOREIGN KEY (`petition_id`) REFERENCES `nyx_parliament_recall_petitions`(`petition_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 6. Comprehensive Statutory Penal Code Expansion
INSERT IGNORE INTO `nyx_parliament_laws` (`law_id`, `title`, `category`, `current_value`, `min_allowed`, `max_allowed`) VALUES
('penal:armed_robbery', 'Armed Robbery & Weapon Brandishing', 'penal_felony', '{"fine": 10000, "months": 25}', '{"fine": 5000, "months": 10}', '{"fine": 30000, "months": 60}'),
('penal:grand_theft_auto', 'Grand Theft Auto & Chop Shop Operation', 'penal_felony', '{"fine": 5000, "months": 15}', '{"fine": 2000, "months": 5}', '{"fine": 20000, "months": 40}'),
('penal:evading_police', 'Evading Law Enforcement in Motor Vehicle', 'penal_misdemeanor', '{"fine": 1500, "months": 10}', '{"fine": 500, "months": 2}', '{"fine": 5000, "months": 20}'),
('penal:trespassing', 'Unlawful Trespassing on Municipal or Corporate Grounds', 'penal_infraction', '{"fine": 300, "months": 0}', '{"fine": 100, "months": 0}', '{"fine": 1000, "months": 0}'),
('penal:jaywalking', 'Disruptive Pedestrian Traffic Hazard', 'penal_infraction', '{"fine": 150, "months": 0}', '{"fine": 50, "months": 0}', '{"fine": 500, "months": 0}');
