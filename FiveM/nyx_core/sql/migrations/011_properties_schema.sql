-- ============================================================================
-- Nyxframework Real Estate & Property Engine Database Migration
-- File: 011_properties_schema.sql
-- Description: Authoritative Real Estate Registry, 5-Tier RFID Access Control,
--              Utility Meter Binding, and Millage Tax Assessment.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Fő Ingatlan Nyilvántartás (Properties Registry)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_properties` (
  `property_id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `property_code` VARCHAR(64) NOT NULL,
  `label` VARCHAR(128) NOT NULL,
  `type` ENUM('residential', 'commercial', 'industrial') NOT NULL DEFAULT 'residential',
  `owner_citizen_id` VARCHAR(16) NULL,
  
  -- Pénzügyi Számítások (Kizárólag DECIMAL(15, 2) pozitív megszorítással)
  `price` DECIMAL(15, 2) NOT NULL CHECK (`price` >= 0.00),
  `millage_tax_rate` DECIMAL(6, 4) NOT NULL DEFAULT 0.0150 CHECK (`millage_tax_rate` >= 0.0000),
  `last_tax_billed_at` TIMESTAMP NULL DEFAULT NULL,
  
  -- Térbeli Koordináták és Virtuális Routing Bucket
  `entrance_coords` JSON NOT NULL,
  `interior_coords` JSON NOT NULL,
  `routing_bucket` INT UNSIGNED NOT NULL DEFAULT 0,
  
  -- Biztonsági Állapot és Csatolt Szolgáltatások
  `is_locked` TINYINT(1) NOT NULL DEFAULT 1,
  `stash_inventory_id` VARCHAR(64) NOT NULL,
  `utility_meter_id` VARCHAR(64) NOT NULL,
  `linked_substation_id` VARCHAR(64) NOT NULL DEFAULT 'substation_central',
  
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  
  CONSTRAINT `uq_property_code` UNIQUE (`property_code`),
  CONSTRAINT `fk_prop_owner` FOREIGN KEY (`owner_citizen_id`) REFERENCES `nyx_characters` (`citizen_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 2. 5-Szintű RFID és Kulcs Hozzáférési Mátrix (Property Access Keys)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_property_keys` (
  `key_id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `property_id` INT UNSIGNED NOT NULL,
  `citizen_id` VARCHAR(16) NOT NULL,
  `tier` TINYINT UNSIGNED NOT NULL DEFAULT 1 CHECK (`tier` BETWEEN 1 AND 5),
  `label` VARCHAR(64) NOT NULL DEFAULT 'Kulcskártya',
  `issued_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT `uq_property_citizen_key` UNIQUE (`property_id`, `citizen_id`),
  CONSTRAINT `fk_prop_key_property` FOREIGN KEY (`property_id`) REFERENCES `nyx_properties` (`property_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_prop_key_citizen` FOREIGN KEY (`citizen_id`) REFERENCES `nyx_characters` (`citizen_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 3. Ingatlan Audit és Tranzakciós Napló (Property Audit Ledger)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_property_audit` (
  `audit_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `property_id` INT UNSIGNED NOT NULL,
  `action` ENUM('PURCHASE', 'SALE', 'MILLAGE_TAX_DEBIT', 'LOCK_TOGGLE', 'KEY_ISSUED', 'KEY_REVOKED', 'POLICE_BREACH') NOT NULL,
  `actor_citizen_id` VARCHAR(16) NULL,
  `amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00 CHECK (`amount` >= 0.00),
  `treasury_tx_uuid` VARCHAR(36) NULL,
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT `fk_prop_audit_property` FOREIGN KEY (`property_id`) REFERENCES `nyx_properties` (`property_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- 4. B-Fa Indexek a Gyors Kereséshez
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS `idx_prop_owner` ON `nyx_properties` (`owner_citizen_id`);
CREATE INDEX IF NOT EXISTS `idx_prop_type` ON `nyx_properties` (`type`);
CREATE INDEX IF NOT EXISTS `idx_prop_bucket` ON `nyx_properties` (`routing_bucket`);
CREATE INDEX IF NOT EXISTS `idx_prop_key_lookup` ON `nyx_property_keys` (`citizen_id`, `tier`);
CREATE INDEX IF NOT EXISTS `idx_prop_audit_timeline` ON `nyx_property_audit` (`property_id`, `created_at` DESC);
