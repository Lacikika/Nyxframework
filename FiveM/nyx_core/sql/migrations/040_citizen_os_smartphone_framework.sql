-- Migration 040: Citizen OS Master Smartphone Framework
-- Resources: nyx_ui, nyx_treasury, nyx_logistics, nyx_mdt, nyx_core

-- 1. Citizen Emergency Alerts & Public Broadcast Log
CREATE TABLE IF NOT EXISTS `nyx_phone_emergency_alerts` (
    `alert_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `alert_uuid` VARCHAR(64) NOT NULL UNIQUE,
    `citizen_id` VARCHAR(64) NOT NULL,
    `caller_name` VARCHAR(128) NOT NULL DEFAULT 'Állampolgár',
    `category` VARCHAR(32) NOT NULL DEFAULT 'general',
    `message` TEXT NOT NULL,
    `location_label` VARCHAR(128) NOT NULL DEFAULT 'Los Santos',
    `coords_json` VARCHAR(255) NULL DEFAULT NULL,
    `priority` ENUM('low', 'medium', 'high', 'critical') NOT NULL DEFAULT 'medium',
    `status` ENUM('broadcasted', 'acknowledged', 'resolved') NOT NULL DEFAULT 'broadcasted',
    `created_at` INT UNSIGNED NOT NULL,
    KEY `idx_alert_created` (`created_at`),
    KEY `idx_alert_citizen` (`citizen_id`),
    KEY `idx_alert_priority` (`priority`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Citizen Phone Preferences, Registry & Settings
CREATE TABLE IF NOT EXISTS `nyx_phone_settings` (
    `citizen_id` VARCHAR(64) NOT NULL PRIMARY KEY,
    `phone_number` VARCHAR(32) NOT NULL UNIQUE,
    `wallpaper` VARCHAR(64) NOT NULL DEFAULT 'default_dark',
    `dark_mode` TINYINT(1) NOT NULL DEFAULT 1,
    `airplane_mode` TINYINT(1) NOT NULL DEFAULT 0,
    `notifications_enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `updated_at` INT UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Extend nyx_characters with Phone Number if not present
ALTER TABLE `nyx_characters`
    ADD COLUMN IF NOT EXISTS `phone_number` VARCHAR(32) NULL DEFAULT NULL AFTER `dob`;
