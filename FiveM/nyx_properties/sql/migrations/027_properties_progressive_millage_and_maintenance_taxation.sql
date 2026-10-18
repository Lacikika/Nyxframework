-- Nyxframework: nyx_properties / nyx_treasury
-- Migration: 027_properties_progressive_millage_and_maintenance_taxation.sql
-- Description: Progressive property millage holding multipliers (1.5^(N-1)),
--              dynamic land footprint maintenance taxation, delinquency state machine,
--              and municipal foreclosure blind-auction reclamation engine.

-- 1. Extend nyx_properties with land footprint, maintenance condition, delinquency tier & auction status
ALTER TABLE `nyx_properties`
  ADD COLUMN IF NOT EXISTS `land_area_sqm` DECIMAL(10, 2) NOT NULL DEFAULT 150.00 AFTER `type`,
  ADD COLUMN IF NOT EXISTS `maintenance_condition` DECIMAL(5, 2) NOT NULL DEFAULT 100.00 AFTER `land_area_sqm`,
  ADD COLUMN IF NOT EXISTS `last_maintenance_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `maintenance_condition`,
  ADD COLUMN IF NOT EXISTS `delinquency_tier` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `last_tax_billed_at`,
  ADD COLUMN IF NOT EXISTS `delinquent_amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00 AFTER `delinquency_tier`,
  ADD COLUMN IF NOT EXISTS `consecutive_missed_cycles` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `delinquent_amount`,
  ADD COLUMN IF NOT EXISTS `zone_id` VARCHAR(64) NOT NULL DEFAULT 'zone_ls_metro' AFTER `consecutive_missed_cycles`,
  ADD COLUMN IF NOT EXISTS `reclaimed_for_auction` TINYINT(1) NOT NULL DEFAULT 0 AFTER `zone_id`;

-- 2. Update existing default properties with realistic land footprints and economic zone mappings
UPDATE `nyx_properties`
SET
  `land_area_sqm` = 120.00,
  `zone_id` = 'zone_ls_metro',
  `maintenance_condition` = 100.00
WHERE `property_code` = 'apt_integrity_101';

UPDATE `nyx_properties`
SET
  `land_area_sqm` = 320.00,
  `zone_id` = 'zone_ls_metro',
  `maintenance_condition` = 100.00
WHERE `property_code` = 'store_vinewood_24';

UPDATE `nyx_properties`
SET
  `land_area_sqm` = 1250.00,
  `zone_id` = 'zone_port_industrial',
  `maintenance_condition` = 100.00
WHERE `property_code` = 'wh_elysian_04';

-- 3. Create immutable tax assessment history table
CREATE TABLE IF NOT EXISTS `nyx_property_tax_assessments` (
  `assessment_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `property_id` INT UNSIGNED NOT NULL,
  `owner_citizen_id` VARCHAR(16) NOT NULL,
  `cycle_timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `properties_owned_count` INT UNSIGNED NOT NULL DEFAULT 1,
  `base_millage_rate` DECIMAL(6, 4) NOT NULL DEFAULT 0.0150,
  `progressive_holding_multiplier` DECIMAL(8, 4) NOT NULL DEFAULT 1.0000,
  `effective_millage_rate` DECIMAL(8, 4) NOT NULL DEFAULT 0.0150,
  `millage_tax_amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `land_area_sqm` DECIMAL(10, 2) NOT NULL DEFAULT 150.00,
  `maintenance_tax_amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `penalty_amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `total_tax_due` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `status` ENUM('paid', 'delinquent', 'waived', 'forfeited') NOT NULL DEFAULT 'paid',
  `treasury_tx_uuid` VARCHAR(36) NULL,
  `payment_method` ENUM('online_bank', 'offline_bank', 'cash', 'delinquency_ledger') NOT NULL DEFAULT 'online_bank',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_prop_tax_property` (`property_id`),
  INDEX `idx_prop_tax_citizen` (`owner_citizen_id`),
  INDEX `idx_prop_tax_status` (`status`),
  INDEX `idx_prop_tax_cycle` (`cycle_timestamp`),
  CONSTRAINT `fk_prop_tax_property` FOREIGN KEY (`property_id`) REFERENCES `nyx_properties` (`property_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Create municipal foreclosure & blind-auction ledger
CREATE TABLE IF NOT EXISTS `nyx_property_auctions` (
  `auction_id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `property_id` INT UNSIGNED NOT NULL,
  `previous_owner_citizen_id` VARCHAR(16) NULL,
  `minimum_bid` DECIMAL(15, 2) NOT NULL,
  `highest_bid` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `highest_bidder_citizen_id` VARCHAR(16) NULL,
  `auction_status` ENUM('active', 'completed', 'cancelled') NOT NULL DEFAULT 'active',
  `started_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ends_at` TIMESTAMP NOT NULL,
  `settled_at` TIMESTAMP NULL,
  INDEX `idx_auction_status` (`auction_status`),
  INDEX `idx_auction_property` (`property_id`),
  INDEX `idx_auction_bidder` (`highest_bidder_citizen_id`),
  CONSTRAINT `fk_auction_property` FOREIGN KEY (`property_id`) REFERENCES `nyx_properties` (`property_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
