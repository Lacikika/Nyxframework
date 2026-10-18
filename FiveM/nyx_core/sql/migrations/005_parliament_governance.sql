-- Nyxframework Governance & Legislative Engine Schema
-- Migration: 005_parliament_governance.sql

-- 1. Legislative sessions, referendums, and general elections
CREATE TABLE IF NOT EXISTS `nyx_parliament_sessions` (
  `session_id` VARCHAR(64) PRIMARY KEY,
  `title` VARCHAR(128) NOT NULL,
  `description` TEXT NOT NULL,
  `type` ENUM('election', 'referendum', 'bill_vote') NOT NULL,
  `required_quorum` INT UNSIGNED NOT NULL DEFAULT 5,
  `starts_at` TIMESTAMP NOT NULL,
  `ends_at` TIMESTAMP NOT NULL,
  `status` ENUM('scheduled', 'active', 'tallying', 'concluded', 'invalidated') DEFAULT 'scheduled',
  `metadata` JSON NOT NULL,
  `winner_option` VARCHAR(64) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_session_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Voter participation ledger (prevents duplicate voting and Sybil attacks)
CREATE TABLE IF NOT EXISTS `nyx_parliament_voter_registry` (
  `registry_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `session_id` VARCHAR(64) NOT NULL,
  `hardware_hash` VARCHAR(64) NOT NULL,
  `voted_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_hardware_per_session` (`session_id`, `hardware_hash`),
  FOREIGN KEY (`session_id`) REFERENCES `nyx_parliament_sessions`(`session_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Anonymized ballot receipts (disconnected from citizen identity)
CREATE TABLE IF NOT EXISTS `nyx_parliament_ballots` (
  `ballot_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `session_id` VARCHAR(64) NOT NULL,
  `ballot_hash` VARCHAR(64) NOT NULL,
  `preferences` JSON NOT NULL,
  `submitted_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_session_ballots` (`session_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Authoritative active penal and statutory laws
CREATE TABLE IF NOT EXISTS `nyx_parliament_laws` (
  `law_id` VARCHAR(32) PRIMARY KEY,
  `title` VARCHAR(96) NOT NULL,
  `category` ENUM('penal_infraction', 'penal_misdemeanor', 'penal_felony', 'fiscal_policy', 'zoning') NOT NULL,
  `current_value` JSON NOT NULL,
  `min_allowed` JSON NOT NULL,
  `max_allowed` JSON NOT NULL,
  `last_amended_by_session` VARCHAR(64) NULL,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_law_cat` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 5. Initial Seed: Constitutional Baseline Laws
INSERT IGNORE INTO `nyx_parliament_laws` (`law_id`, `title`, `category`, `current_value`, `min_allowed`, `max_allowed`) VALUES
('tax:sales_rate', 'Municipal Sales Tax Rate', 'fiscal_policy', '{"rate": 0.08}', '{"rate": 0.00}', '{"rate": 0.15}'),
('tax:transfer_rate', 'Electronic Wire Duty Rate', 'fiscal_policy', '{"rate": 0.02}', '{"rate": 0.00}', '{"rate": 0.05}'),
('penal:felony_speeding', 'Aggravated Reckless Speeding (>140mph)', 'penal_felony', '{"fine": 2500, "months": 15}', '{"fine": 1000, "months": 5}', '{"fine": 10000, "months": 60}'),
('penal:commercial_fraud', 'Commercial Fraud & Tax Evasion', 'penal_felony', '{"fine": 15000, "months": 30}', '{"fine": 5000, "months": 10}', '{"fine": 50000, "months": 120}'),
('penal:reckless_driving', 'Reckless Endangerment in Motor Vehicle', 'penal_misdemeanor', '{"fine": 750, "months": 5}', '{"fine": 250, "months": 0}', '{"fine": 2500, "months": 15}');

-- 6. Initial Seed: Sample Active Election Session
INSERT IGNORE INTO `nyx_parliament_sessions` (`session_id`, `title`, `description`, `type`, `required_quorum`, `starts_at`, `ends_at`, `status`, `metadata`) VALUES
('election:mayor_2026', 'Mayoral General Election', 'Ranked-choice popular election for the office of City Mayor.', 'election', 1, CURRENT_TIMESTAMP, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 7 DAY), 'active', '{"candidates": [{"id": "candidate_a", "name": "Elena Vance (Civic Coalition)"}, {"id": "candidate_b", "name": "Marcus Sterling (Enterprise Party)"}, {"id": "candidate_c", "name": "Tara Cole (Worker Front)"}]}'),
('referendum:commerce_stimulus', 'Commerce Stimulus & Tax Reduction Bill', 'Citizen initiative proposing a 3% sales tax reduction to spur retail trade.', 'bill_vote', 1, CURRENT_TIMESTAMP, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 7 DAY), 'active', '{"options": [{"id": "PASS", "name": "Yes / Enact Bill"}, {"id": "REJECT", "name": "No / Preserve Current Tax"}], "actions": [{"targetLawId": "tax:sales_rate", "field": "rate", "newValue": 0.05}]}');
