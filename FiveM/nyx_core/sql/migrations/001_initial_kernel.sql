-- Nyxframework Kernel Database Schema
-- Migration: 001_initial_kernel.sql

-- 1. Master player accounts (identifiers & global bans)
CREATE TABLE IF NOT EXISTS `nyx_accounts` (
  `account_id` INT AUTO_INCREMENT PRIMARY KEY,
  `license` VARCHAR(64) NOT NULL UNIQUE,
  `discord_id` VARCHAR(32) NULL,
  `steam_id` VARCHAR(32) NULL,
  `hwid_hash` VARCHAR(64) NOT NULL,
  `global_permissions` JSON DEFAULT ('["player"]'),
  `is_banned` TINYINT(1) DEFAULT 0,
  `ban_reason` TEXT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `last_seen` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_license` (`license`),
  INDEX `idx_hwid` (`hwid_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Character entities (per-player personas)
CREATE TABLE IF NOT EXISTS `nyx_characters` (
  `char_id` INT AUTO_INCREMENT PRIMARY KEY,
  `account_id` INT NOT NULL,
  `citizen_id` VARCHAR(16) NOT NULL UNIQUE,
  `first_name` VARCHAR(48) NOT NULL,
  `last_name` VARCHAR(48) NOT NULL,
  `dob` DATE NOT NULL,
  `gender` VARCHAR(16) NOT NULL,
  `wallets` JSON NOT NULL,
  `position` JSON NOT NULL,
  `metadata` JSON NOT NULL,
  `is_dead` TINYINT(1) DEFAULT 0,
  `deleted_at` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`account_id`) REFERENCES `nyx_accounts`(`account_id`) ON DELETE CASCADE,
  INDEX `idx_citizen_id` (`citizen_id`),
  INDEX `idx_account_id` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Audit ledger for critical transactions (anti-cheat & economy tracing)
CREATE TABLE IF NOT EXISTS `nyx_audit_log` (
  `log_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `citizen_id` VARCHAR(16) NULL,
  `action` VARCHAR(64) NOT NULL,
  `payload` JSON NOT NULL,
  `ip_address` VARCHAR(45) NOT NULL,
  `timestamp` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_char_action` (`citizen_id`, `action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
