-- Migration 028: Trade Unionization Framework, Collective Bargaining Agreements & Binding Labor Arbitration
-- Resources: nyx_factions, nyx_treasury, nyx_judiciary

-- 1. Trade Unions Registry
CREATE TABLE IF NOT EXISTS `nyx_factions_unions` (
    `union_id` VARCHAR(64) NOT NULL,
    `legal_name` VARCHAR(128) NOT NULL,
    `industry_sector` VARCHAR(32) NOT NULL DEFAULT 'general',
    `treasury_account_id` VARCHAR(64) NOT NULL,
    `founder_citizen_id` VARCHAR(64) NOT NULL,
    `dues_amount` DECIMAL(10,2) NOT NULL DEFAULT 50.00,
    `dues_rate` DECIMAL(5,4) NOT NULL DEFAULT 0.0250,
    `dues_mode` ENUM('flat', 'percentage') NOT NULL DEFAULT 'flat',
    `strike_fund_balance` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    `strike_pay_rate` DECIMAL(10,2) NOT NULL DEFAULT 150.00,
    `status` ENUM('active', 'sanctioned', 'dissolved') NOT NULL DEFAULT 'active',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`union_id`),
    UNIQUE KEY `uq_union_legal_name` (`legal_name`),
    UNIQUE KEY `uq_union_treasury` (`treasury_account_id`),
    KEY `idx_union_sector` (`industry_sector`),
    KEY `idx_union_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Union Membership Registry
CREATE TABLE IF NOT EXISTS `nyx_factions_union_members` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `union_id` VARCHAR(64) NOT NULL,
    `citizen_id` VARCHAR(64) NOT NULL,
    `enterprise_faction_id` VARCHAR(64) NULL,
    `role` ENUM('steward', 'delegate', 'member') NOT NULL DEFAULT 'member',
    `standing` ENUM('good_standing', 'arrears', 'exempt') NOT NULL DEFAULT 'good_standing',
    `unpaid_dues` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    `last_dues_paid_at` TIMESTAMP NULL,
    `last_strike_pay_at` TIMESTAMP NULL,
    `joined_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_union_member` (`union_id`, `citizen_id`),
    KEY `idx_union_cit` (`citizen_id`),
    KEY `idx_union_enterprise` (`enterprise_faction_id`),
    KEY `idx_member_standing` (`standing`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Collective Bargaining Agreements (CBAs)
CREATE TABLE IF NOT EXISTS `nyx_factions_cba` (
    `cba_id` VARCHAR(64) NOT NULL,
    `union_id` VARCHAR(64) NOT NULL,
    `enterprise_faction_id` VARCHAR(64) NOT NULL,
    `cba_title` VARCHAR(128) NOT NULL,
    `wage_floor` DECIMAL(10,2) NOT NULL DEFAULT 35.00,
    `overtime_multiplier` DECIMAL(4,2) NOT NULL DEFAULT 1.50,
    `hazard_pay_bonus` DECIMAL(10,2) NOT NULL DEFAULT 15.00,
    `strike_grace_period_hours` INT NOT NULL DEFAULT 24,
    `ratified_at` TIMESTAMP NULL,
    `expires_at` TIMESTAMP NULL,
    `status` ENUM('draft', 'proposed', 'ratified', 'breached', 'expired', 'arbitration') NOT NULL DEFAULT 'proposed',
    `created_by` VARCHAR(64) NOT NULL,
    `ratified_by_enterprise` VARCHAR(64) NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`cba_id`),
    KEY `idx_cba_union_enterprise` (`union_id`, `enterprise_faction_id`),
    KEY `idx_cba_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Industrial Strikes Registry (Picket Locks & State Tracking)
CREATE TABLE IF NOT EXISTS `nyx_factions_strikes` (
    `strike_id` VARCHAR(64) NOT NULL,
    `union_id` VARCHAR(64) NOT NULL,
    `enterprise_faction_id` VARCHAR(64) NOT NULL,
    `cba_id` VARCHAR(64) NULL,
    `reason` VARCHAR(255) NOT NULL,
    `vote_passed_ratio` DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    `status` ENUM('voting', 'active', 'settled', 'broken', 'arbitration') NOT NULL DEFAULT 'voting',
    `voting_deadline` TIMESTAMP NULL,
    `started_at` TIMESTAMP NULL,
    `ended_at` TIMESTAMP NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`strike_id`),
    KEY `idx_strike_enterprise` (`enterprise_faction_id`, `status`),
    KEY `idx_strike_union` (`union_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Strike Member Ballots
CREATE TABLE IF NOT EXISTS `nyx_factions_strike_votes` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `strike_id` VARCHAR(64) NOT NULL,
    `citizen_id` VARCHAR(64) NOT NULL,
    `vote` ENUM('yes', 'no', 'abstain') NOT NULL,
    `voted_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_strike_voter` (`strike_id`, `citizen_id`),
    KEY `idx_strike_vote_ref` (`strike_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. Binding Labor Arbitration Awards
CREATE TABLE IF NOT EXISTS `nyx_factions_arbitration_awards` (
    `award_id` VARCHAR(64) NOT NULL,
    `strike_id` VARCHAR(64) NULL,
    `cba_id` VARCHAR(64) NULL,
    `docket_id` INT NULL,
    `arbitrator_citizen_id` VARCHAR(64) NOT NULL,
    `union_id` VARCHAR(64) NOT NULL,
    `enterprise_faction_id` VARCHAR(64) NOT NULL,
    `restitution_damages` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    `statutory_penalty` DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    `revised_wage_floor` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    `award_summary` TEXT NOT NULL,
    `settlement_status` ENUM('awarded', 'settled', 'defaulted') NOT NULL DEFAULT 'awarded',
    `tx_uuid` VARCHAR(64) NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`award_id`),
    KEY `idx_award_strike` (`strike_id`),
    KEY `idx_award_parties` (`union_id`, `enterprise_faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 7. Seed Default Trade Unions
INSERT INTO `nyx_factions_unions`
    (`union_id`, `legal_name`, `industry_sector`, `treasury_account_id`, `founder_citizen_id`, `dues_amount`, `dues_rate`, `dues_mode`, `strike_fund_balance`, `strike_pay_rate`, `status`)
VALUES
    ('union:transport_workers', 'Amalgamated Transport & Logistics Guild', 'logistics', 'union:transport_workers', 'CIT-UNION-001', 50.00, 0.0250, 'flat', 50000.00, 150.00, 'active'),
    ('union:industrial_miners', 'United Industrial & Mining Workers Local 404', 'manufacturing', 'union:industrial_miners', 'CIT-UNION-002', 45.00, 0.0200, 'flat', 75000.00, 160.00, 'active'),
    ('union:public_servants', 'Federation of Civic & Public Employees', 'services', 'union:public_servants', 'CIT-UNION-003', 35.00, 0.0150, 'percentage', 120000.00, 140.00, 'active')
ON DUPLICATE KEY UPDATE `status` = VALUES(`status`);
