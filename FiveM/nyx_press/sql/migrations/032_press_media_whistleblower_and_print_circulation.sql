-- Migration 032: Decentralized Broadcast Printing, Encrypted Whistleblower Dropboxes & Trade Union Media Accreditation
-- Resource: nyx_press

-- 1. Registered Media Outlets & Publishing Houses
CREATE TABLE IF NOT EXISTS `nyx_press_outlets` (
    `outlet_id` VARCHAR(64) PRIMARY KEY,
    `faction_id` VARCHAR(64) NULL DEFAULT NULL,
    `name` VARCHAR(128) NOT NULL,
    `license_status` ENUM('active', 'suspended', 'unaccredited') NOT NULL DEFAULT 'active',
    `accredited_union_id` VARCHAR(64) NULL DEFAULT 'union:press_guild',
    `press_coords` JSON NULL DEFAULT NULL,
    `print_cost_per_copy` DECIMAL(10, 2) NOT NULL DEFAULT 2.50,
    `cover_price_default` DECIMAL(10, 2) NOT NULL DEFAULT 10.00,
    `revenue_balance` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_outlet_faction` (`faction_id`),
    KEY `idx_outlet_status` (`license_status`),
    KEY `idx_outlet_union` (`accredited_union_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Published Articles & Newspaper Issues
CREATE TABLE IF NOT EXISTS `nyx_press_publications` (
    `publication_id` VARCHAR(64) PRIMARY KEY,
    `outlet_id` VARCHAR(64) NOT NULL,
    `headline` VARCHAR(255) NOT NULL,
    `subheading` VARCHAR(255) NULL DEFAULT NULL,
    `author_citizen_id` VARCHAR(64) NULL DEFAULT NULL,
    `author_byline` VARCHAR(96) NOT NULL,
    `category` ENUM('investigative', 'business', 'politics', 'whistleblower', 'general') NOT NULL DEFAULT 'general',
    `content` MEDIUMTEXT NOT NULL,
    `edition_number` INT UNSIGNED NOT NULL DEFAULT 1,
    `circulation_count` INT UNSIGNED NOT NULL DEFAULT 0,
    `copies_sold` INT UNSIGNED NOT NULL DEFAULT 0,
    `price_per_copy` DECIMAL(10, 2) NOT NULL DEFAULT 10.00,
    `is_retracted` TINYINT(1) NOT NULL DEFAULT 0,
    `retraction_reason` TEXT NULL DEFAULT NULL,
    `retracted_by_judge_id` VARCHAR(64) NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_pub_outlet` (`outlet_id`),
    KEY `idx_pub_author` (`author_citizen_id`),
    KEY `idx_pub_category` (`category`),
    KEY `idx_pub_retracted` (`is_retracted`),
    KEY `idx_pub_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Encrypted Whistleblower Dropboxes
CREATE TABLE IF NOT EXISTS `nyx_press_whistleblower_dropboxes` (
    `dropbox_id` VARCHAR(64) PRIMARY KEY,
    `label` VARCHAR(128) NOT NULL,
    `coords` JSON NOT NULL,
    `public_pgp_fingerprint` VARCHAR(64) NOT NULL,
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_dropbox_active` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Anonymous Whistleblower Leaks
CREATE TABLE IF NOT EXISTS `nyx_press_leaks` (
    `leak_id` VARCHAR(64) PRIMARY KEY,
    `dropbox_id` VARCHAR(64) NOT NULL,
    `target_outlet_id` VARCHAR(64) NULL DEFAULT NULL,
    `title` VARCHAR(255) NOT NULL,
    `leak_category` ENUM('treasury_fraud', 'police_brutality', 'corporate_bribery', 'election_tampering', 'general_corruption') NOT NULL,
    `encrypted_payload` MEDIUMTEXT NOT NULL,
    `source_hash` VARCHAR(64) NOT NULL,
    `evidence_fingerprint` VARCHAR(64) NULL DEFAULT NULL,
    `claimed_by_journalist_id` VARCHAR(64) NULL DEFAULT NULL,
    `status` ENUM('unclaimed', 'under_investigation', 'published', 'quashed') NOT NULL DEFAULT 'unclaimed',
    `submitted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `claimed_at` TIMESTAMP NULL DEFAULT NULL,
    KEY `idx_leak_dropbox` (`dropbox_id`),
    KEY `idx_leak_target` (`target_outlet_id`),
    KEY `idx_leak_journalist` (`claimed_by_journalist_id`),
    KEY `idx_leak_status` (`status`),
    KEY `idx_leak_submitted` (`submitted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Public Newsstands & Distribution Kiosks
CREATE TABLE IF NOT EXISTS `nyx_press_newsstands` (
    `stand_id` VARCHAR(64) PRIMARY KEY,
    `label` VARCHAR(128) NOT NULL,
    `coords` JSON NOT NULL,
    `heading` FLOAT NOT NULL DEFAULT 0.0,
    `current_publication_id` VARCHAR(64) NULL DEFAULT NULL,
    `copies_inventory` INT UNSIGNED NOT NULL DEFAULT 50,
    `total_sold` INT UNSIGNED NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_stand_pub` (`current_publication_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. Seed Recognized Media Outlets
INSERT INTO `nyx_press_outlets`
    (`outlet_id`, `faction_id`, `name`, `license_status`, `accredited_union_id`, `press_coords`, `print_cost_per_copy`, `cover_price_default`)
VALUES
    ('press:daily_globe', 'fact:daily_globe', 'Los Santos Daily Globe', 'active', 'union:press_guild', '{"x": -1067.8, "y": -244.6, "z": 39.7}', 2.50, 10.00),
    ('press:weazel_news', 'fact:weazel_news', 'Weazel News Media Group', 'active', 'union:press_guild', '{"x": -589.2, "y": -930.5, "z": 23.8}', 3.00, 12.00),
    ('press:underground_post', NULL, 'The Underground Whistleblower', 'active', 'union:press_guild', '{"x": 725.1, "y": -968.4, "z": 24.5}', 1.50, 5.00)
ON DUPLICATE KEY UPDATE
    `name` = VALUES(`name`),
    `license_status` = VALUES(`license_status`);

-- 7. Seed Encrypted Whistleblower Dropboxes
INSERT INTO `nyx_press_whistleblower_dropboxes`
    (`dropbox_id`, `label`, `coords`, `public_pgp_fingerprint`, `is_active`)
VALUES
    ('drop_metro_subway', 'Burton Metro Tunnel Anonymous Terminal', '{"x": -287.4, "y": -331.2, "z": 10.1}', 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 1),
    ('drop_docks_elysian', 'Elysian Island Pier 400 Dead Drop Box', '{"x": 154.2, "y": -3198.6, "z": 5.9}', 'ca978112ca1bbdcafac231b39a23dc4da786081cd1e14eed647241cb65ae9144', 1),
    ('drop_sandy_motel', 'Sandy Shores Abandoned Motel Locker', '{"x": 1985.4, "y": 3740.1, "z": 32.3}', '4e07408562bedb8b60ce05c1decfe3ad16b72230967de01f640b7e4729b49fce', 1)
ON DUPLICATE KEY UPDATE
    `label` = VALUES(`label`),
    `coords` = VALUES(`coords`);

-- 8. Seed Canonical Public Newsstands
INSERT INTO `nyx_press_newsstands`
    (`stand_id`, `label`, `coords`, `heading`, `current_publication_id`, `copies_inventory`, `total_sold`)
VALUES
    ('stand_legion_square', 'Legion Square Central Newspaper Kiosk', '{"x": 172.5, "y": -935.2, "z": 30.6}', 140.0, NULL, 50, 0),
    ('stand_city_hall', 'Los Santos City Hall Civic Newsstand', '{"x": -541.2, "y": -208.5, "z": 37.6}', 30.0, NULL, 50, 0),
    ('stand_sandy_shores', 'Sandy Shores General Store Kiosk', '{"x": 1888.2, "y": 3754.6, "z": 32.9}', 210.0, NULL, 50, 0),
    ('stand_paleto_bay', 'Paleto Bay Boulevard News Stand', '{"x": -102.4, "y": 6468.1, "z": 31.6}', 45.0, NULL, 50, 0)
ON DUPLICATE KEY UPDATE
    `label` = VALUES(`label`),
    `coords` = VALUES(`coords`);
