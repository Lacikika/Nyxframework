-- Migration 047: Investigative Press Subscriptions, Delivery Routing & Whistleblower Bounty Escrow
-- Resources: nyx_press & nyx_treasury

-- 1. Press Subscription Plans
CREATE TABLE IF NOT EXISTS `nyx_press_subscription_plans` (
    `plan_id` VARCHAR(64) PRIMARY KEY,
    `outlet_id` VARCHAR(64) NOT NULL,
    `name` VARCHAR(128) NOT NULL,
    `plan_type` ENUM('digital', 'print_delivery', 'syndication') NOT NULL DEFAULT 'digital',
    `billing_period_sec` INT UNSIGNED NOT NULL DEFAULT 604800,
    `price` DECIMAL(10, 2) NOT NULL DEFAULT 25.00,
    `publisher_share_ratio` DECIMAL(5, 4) NOT NULL DEFAULT 0.7500,
    `whistleblower_pool_ratio` DECIMAL(5, 4) NOT NULL DEFAULT 0.1500,
    `municipal_tax_ratio` DECIMAL(5, 4) NOT NULL DEFAULT 0.1000,
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_plan_outlet` (`outlet_id`),
    KEY `idx_plan_active` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Citizen & Corporate Press Subscriptions
CREATE TABLE IF NOT EXISTS `nyx_press_subscriptions` (
    `subscription_id` VARCHAR(64) PRIMARY KEY,
    `citizen_id` VARCHAR(64) NOT NULL,
    `outlet_id` VARCHAR(64) NOT NULL,
    `plan_id` VARCHAR(64) NOT NULL,
    `delivery_property_id` VARCHAR(64) NULL DEFAULT NULL,
    `status` ENUM('active', 'past_due', 'cancelled', 'expired') NOT NULL DEFAULT 'active',
    `auto_renew` TINYINT(1) NOT NULL DEFAULT 1,
    `started_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `current_period_start` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `current_period_end` TIMESTAMP NOT NULL,
    `last_billed_at` TIMESTAMP NULL DEFAULT NULL,
    `consecutive_failures` INT UNSIGNED NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_sub_citizen` (`citizen_id`),
    KEY `idx_sub_outlet` (`outlet_id`),
    KEY `idx_sub_status` (`status`),
    KEY `idx_sub_period_end` (`current_period_end`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Subscription Double-Entry Billing & Revenue Split Audit Logs
CREATE TABLE IF NOT EXISTS `nyx_press_subscription_billing_logs` (
    `log_id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `log_uuid` VARCHAR(64) NOT NULL UNIQUE,
    `subscription_id` VARCHAR(64) NOT NULL,
    `citizen_id` VARCHAR(64) NOT NULL,
    `outlet_id` VARCHAR(64) NOT NULL,
    `amount` DECIMAL(10, 2) NOT NULL,
    `publisher_share` DECIMAL(10, 2) NOT NULL,
    `whistleblower_escrow_share` DECIMAL(10, 2) NOT NULL,
    `municipal_tax_share` DECIMAL(10, 2) NOT NULL,
    `treasury_tx_id` VARCHAR(64) NULL DEFAULT NULL,
    `status` ENUM('success', 'failed_insufficient_funds', 'failed_account_error') NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_bill_sub` (`subscription_id`),
    KEY `idx_bill_citizen` (`citizen_id`),
    KEY `idx_bill_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Whistleblower Bounty Escrow & Anonymous Claims
CREATE TABLE IF NOT EXISTS `nyx_press_whistleblower_bounties` (
    `bounty_id` VARCHAR(64) PRIMARY KEY,
    `leak_id` VARCHAR(64) NOT NULL,
    `outlet_id` VARCHAR(64) NOT NULL,
    `awarded_by_journalist_id` VARCHAR(64) NOT NULL,
    `source_hash` VARCHAR(64) NOT NULL,
    `bounty_amount` DECIMAL(15, 2) NOT NULL,
    `is_claimed` TINYINT(1) NOT NULL DEFAULT 0,
    `claimed_at` TIMESTAMP NULL DEFAULT NULL,
    `claimed_dropbox_id` VARCHAR(64) NULL DEFAULT NULL,
    `claim_tx_id` VARCHAR(64) NULL DEFAULT NULL,
    `status` ENUM('escrowed', 'claimed', 'forfeited') NOT NULL DEFAULT 'escrowed',
    `awarded_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_bounty_leak` (`leak_id`),
    KEY `idx_bounty_source` (`source_hash`),
    KEY `idx_bounty_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Seed Canonical Subscription Plans
INSERT INTO `nyx_press_subscription_plans`
    (`plan_id`, `outlet_id`, `name`, `plan_type`, `billing_period_sec`, `price`, `publisher_share_ratio`, `whistleblower_pool_ratio`, `municipal_tax_ratio`, `is_active`)
VALUES
    ('plan_daily_globe_digital', 'press:daily_globe', 'Daily Globe Digital Wire', 'digital', 604800, 25.00, 0.7500, 0.1500, 0.1000, 1),
    ('plan_daily_globe_print', 'press:daily_globe', 'Daily Globe Home Print Delivery', 'print_delivery', 604800, 60.00, 0.7500, 0.1500, 0.1000, 1),
    ('plan_weazel_digital', 'press:weazel_news', 'Weazel News Flash Digital', 'digital', 604800, 35.00, 0.7500, 0.1500, 0.1000, 1),
    ('plan_weazel_print', 'press:weazel_news', 'Weazel News Weekly Courier Delivery', 'print_delivery', 604800, 75.00, 0.7500, 0.1500, 0.1000, 1),
    ('plan_underground_digital', 'press:underground_post', 'The Underground Leak Dispatch', 'digital', 604800, 10.00, 0.7500, 0.1500, 0.1000, 1)
ON DUPLICATE KEY UPDATE
    `name` = VALUES(`name`),
    `price` = VALUES(`price`),
    `billing_period_sec` = VALUES(`billing_period_sec`);

-- 6. Seed Press Escrow & Faction Accounts in Treasury
INSERT INTO `nyx_treasury_accounts`
    (`account_id`, `label`, `balance`, `type`)
VALUES
    ('pool:whistleblower:press:daily_globe', 'Daily Globe Whistleblower Bounty Escrow', 5000.00, 'reserve'),
    ('pool:whistleblower:press:weazel_news', 'Weazel News Whistleblower Bounty Escrow', 5000.00, 'reserve'),
    ('pool:whistleblower:press:underground_post', 'Underground Whistleblower Bounty Escrow', 1000.00, 'reserve'),
    ('faction:press:daily_globe', 'Los Santos Daily Globe Treasury', 25000.00, 'reserve'),
    ('faction:press:weazel_news', 'Weazel News Corporate Treasury', 35000.00, 'reserve'),
    ('faction:press:underground_post', 'Underground Post Independent Treasury', 5000.00, 'reserve')
ON DUPLICATE KEY UPDATE
    `label` = VALUES(`label`);
