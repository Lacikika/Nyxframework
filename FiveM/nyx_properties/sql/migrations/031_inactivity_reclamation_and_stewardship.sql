-- Migration 031: Anti-Monopoly Inactivity Reclamation Engine, Stewardship Delegates & Public Blind-Auction Liquidation
-- Resources: nyx_properties, nyx_factions, nyx_treasury, nyx_core

-- 1. Extend nyx_characters with Last Activity Timestamp
ALTER TABLE `nyx_characters`
    ADD COLUMN IF NOT EXISTS `last_active_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `is_dead`;

-- 2. Extend nyx_properties with Stewardship Delegate & Inactivity Lifecycle
ALTER TABLE `nyx_properties`
    ADD COLUMN IF NOT EXISTS `steward_delegate_citizen_id` VARCHAR(16) NULL DEFAULT NULL AFTER `owner_citizen_id`,
    ADD COLUMN IF NOT EXISTS `inactivity_status` ENUM('active', 'delegated', 'grace_period', 'reclaimed_for_auction') NOT NULL DEFAULT 'active' AFTER `reclaimed_for_auction`,
    ADD COLUMN IF NOT EXISTS `inactivity_warning_at` TIMESTAMP NULL DEFAULT NULL AFTER `inactivity_status`,
    ADD COLUMN IF NOT EXISTS `reclaimed_at` TIMESTAMP NULL DEFAULT NULL AFTER `inactivity_warning_at`;

-- 3. Extend nyx_factions_registry with Founder Citizen, Delegate & Inactivity Status
ALTER TABLE `nyx_factions_registry`
    ADD COLUMN IF NOT EXISTS `founder_citizen_id` VARCHAR(16) NULL DEFAULT NULL AFTER `legal_name`,
    ADD COLUMN IF NOT EXISTS `steward_delegate_citizen_id` VARCHAR(16) NULL DEFAULT NULL AFTER `founder_citizen_id`,
    ADD COLUMN IF NOT EXISTS `inactivity_status` ENUM('active', 'delegated', 'grace_period', 'succession_pending', 'liquidated') NOT NULL DEFAULT 'active' AFTER `is_active`,
    ADD COLUMN IF NOT EXISTS `inactivity_warning_at` TIMESTAMP NULL DEFAULT NULL AFTER `inactivity_status`,
    ADD COLUMN IF NOT EXISTS `liquidated_at` TIMESTAMP NULL DEFAULT NULL AFTER `inactivity_warning_at`;

-- 4. Stewardship Delegate Proxy Authorization Registry
CREATE TABLE IF NOT EXISTS `nyx_stewardship_delegates` (
    `delegate_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `owner_citizen_id` VARCHAR(16) NOT NULL,
    `delegate_citizen_id` VARCHAR(16) NOT NULL,
    `scope` ENUM('all', 'properties', 'factions') NOT NULL DEFAULT 'all',
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    `authorized_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `revoked_at` TIMESTAMP NULL DEFAULT NULL,
    `notes` VARCHAR(255) NULL DEFAULT NULL,
    KEY `idx_steward_owner` (`owner_citizen_id`),
    KEY `idx_steward_delegate` (`delegate_citizen_id`),
    KEY `idx_steward_active` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Immutable Inactivity Reclamation & Liquidation Audit History
CREATE TABLE IF NOT EXISTS `nyx_inactivity_reclamation_logs` (
    `log_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `asset_type` ENUM('property', 'faction_charter', 'commercial_license') NOT NULL,
    `asset_id` VARCHAR(64) NOT NULL,
    `previous_owner_citizen_id` VARCHAR(16) NOT NULL,
    `delegate_citizen_id` VARCHAR(16) NULL DEFAULT NULL,
    `action` ENUM('warning_issued', 'warning_cleared', 'forfeited_to_auction', 'succession_executed', 'charter_liquidated') NOT NULL,
    `auction_id` INT UNSIGNED NULL DEFAULT NULL,
    `liquidated_funds` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
    `treasury_tx_uuid` VARCHAR(36) NULL DEFAULT NULL,
    `notes` TEXT NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_reclaim_asset` (`asset_type`, `asset_id`),
    KEY `idx_reclaim_owner` (`previous_owner_citizen_id`),
    KEY `idx_reclaim_action` (`action`),
    KEY `idx_reclaim_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
