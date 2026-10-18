-- ============================================================================
-- Nyxframework: nyx_properties & nyx_factions
-- Migration: 058_commercial_real_estate_leasing_and_storefront_cycles.sql
-- Description: Commercial Real Estate Leasing, Public Storefront Lease Cycles,
--              Security Deposit Escrow, Rental Tax Distribution, 4-Tier Delinquency
--              Interlocks, and Automated Eviction Relisting.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Ensure Municipal Lease Escrow Account Exists in Treasury
-- ----------------------------------------------------------------------------
INSERT IGNORE INTO `nyx_treasury_accounts` (`account_id`, `label`, `balance`, `type`, `circuit_exempt`) VALUES
('pool:property:lease_escrow', 'Municipal Commercial Lease Security Deposit Escrow Pool', 0.00, 'grant_pool', 1);

-- ----------------------------------------------------------------------------
-- 2. Extend Properties Schema with Commercial Leasing Columns
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_properties`
  ADD COLUMN IF NOT EXISTS `is_leased` TINYINT(1) NOT NULL DEFAULT 0 AFTER `is_locked`,
  ADD COLUMN IF NOT EXISTS `active_lease_id` VARCHAR(64) NULL DEFAULT NULL AFTER `is_leased`,
  ADD COLUMN IF NOT EXISTS `commercial_zoning` ENUM('retail_storefront', 'corporate_office', 'industrial_warehouse', 'hospitality_venue', 'medical_clinic', 'none') NOT NULL DEFAULT 'none' AFTER `active_lease_id`,
  ADD COLUMN IF NOT EXISTS `base_rental_rate` DECIMAL(15, 2) NOT NULL DEFAULT 0.00 AFTER `commercial_zoning`,
  ADD COLUMN IF NOT EXISTS `lease_status` ENUM('not_leased', 'available_for_lease', 'leased_active', 'in_grace_period', 'lease_lapsed', 'evicted_relisting') NOT NULL DEFAULT 'not_leased' AFTER `base_rental_rate`;

-- ----------------------------------------------------------------------------
-- 3. Commercial Real Estate Leases Table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_property_commercial_leases` (
  `lease_id` VARCHAR(64) NOT NULL PRIMARY KEY,
  `lease_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `property_id` INT UNSIGNED NOT NULL,
  `lessor_type` ENUM('municipal', 'private_citizen', 'corporation') NOT NULL DEFAULT 'municipal',
  `lessor_account_id` VARCHAR(64) NOT NULL DEFAULT 'gov:city:master',
  `lessee_type` ENUM('faction', 'citizen') NOT NULL DEFAULT 'faction',
  `lessee_id` VARCHAR(64) NOT NULL,
  `lessee_account_id` VARCHAR(64) NOT NULL,
  `authorized_signer_citizen_id` VARCHAR(16) NOT NULL,
  `zoning_usage` ENUM('retail_storefront', 'corporate_office', 'industrial_warehouse', 'hospitality_venue', 'medical_clinic') NOT NULL DEFAULT 'retail_storefront',
  `cycle_rent` DECIMAL(15, 2) NOT NULL CHECK (`cycle_rent` > 0.00),
  `security_deposit_held` DECIMAL(15, 2) NOT NULL DEFAULT 0.00 CHECK (`security_deposit_held` >= 0.00),
  `rental_tax_rate` DECIMAL(6, 4) NOT NULL DEFAULT 0.0500 CHECK (`rental_tax_rate` >= 0.0000 AND `rental_tax_rate` <= 0.3000),
  `lease_term_cycles` INT UNSIGNED NOT NULL DEFAULT 4,
  `cycles_completed` INT UNSIGNED NOT NULL DEFAULT 0,
  `consecutive_missed_cycles` INT UNSIGNED NOT NULL DEFAULT 0,
  `delinquency_tier` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `arrears_balance` DECIMAL(15, 2) NOT NULL DEFAULT 0.00 CHECK (`arrears_balance` >= 0.00),
  `late_penalty_rate` DECIMAL(6, 4) NOT NULL DEFAULT 0.1000,
  `lease_status` ENUM('active', 'grace_period', 'lapsed', 'terminated', 'evicted', 'expired') NOT NULL DEFAULT 'active',
  `next_billing_due_at` TIMESTAMP NOT NULL,
  `grace_period_expires_at` TIMESTAMP NULL DEFAULT NULL,
  `eviction_deadline_at` TIMESTAMP NULL DEFAULT NULL,
  `last_billed_at` TIMESTAMP NULL DEFAULT NULL,
  `last_settled_at` TIMESTAMP NULL DEFAULT NULL,
  `escrow_deposit_tx_id` VARCHAR(64) NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT `fk_lease_property` FOREIGN KEY (`property_id`) REFERENCES `nyx_properties` (`property_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 4. Immutable Commercial Lease Audit Ledger
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_property_lease_audits` (
  `audit_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(36) NOT NULL UNIQUE,
  `lease_id` VARCHAR(64) NOT NULL,
  `property_id` INT UNSIGNED NOT NULL,
  `action` ENUM('LEASE_SIGNED', 'RENT_DEBITED', 'RENT_PAID_MANUAL', 'TAX_REMITTED', 'GRACE_ENTERED', 'LEASE_LAPSED_LOCKOUT', 'ARREARS_SETTLED', 'EVICTION_EXECUTED', 'DEPOSIT_FORFEITED', 'DEPOSIT_REFUNDED', 'LEASE_EXPIRED_RELISTED') NOT NULL,
  `actor_citizen_id` VARCHAR(16) NULL,
  `amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `tax_amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
  `treasury_tx_uuid` VARCHAR(64) NULL,
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_lease_audit_prop` FOREIGN KEY (`property_id`) REFERENCES `nyx_properties` (`property_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 5. Seed Canonical Storefronts & Commercial Warehouses into Lease Catalog
-- ----------------------------------------------------------------------------
UPDATE `nyx_properties`
SET `commercial_zoning` = 'retail_storefront',
    `base_rental_rate` = 3500.00,
    `lease_status` = 'available_for_lease'
WHERE `property_code` = 'store_vinewood_24' OR `type` = 'commercial';

UPDATE `nyx_properties`
SET `commercial_zoning` = 'industrial_warehouse',
    `base_rental_rate` = 6500.00,
    `lease_status` = 'available_for_lease'
WHERE `property_code` = 'wh_elysian_04' OR `type` = 'industrial';

SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- 6. B-Tree Indexes for Real-Time Querying
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS `idx_lease_prop_lookup` ON `nyx_property_commercial_leases` (`property_id`, `lease_status`);
CREATE INDEX IF NOT EXISTS `idx_lease_lessee` ON `nyx_property_commercial_leases` (`lessee_id`, `lease_status`);
CREATE INDEX IF NOT EXISTS `idx_lease_billing` ON `nyx_property_commercial_leases` (`next_billing_due_at`, `lease_status`);
CREATE INDEX IF NOT EXISTS `idx_lease_audit_timeline` ON `nyx_property_lease_audits` (`lease_id`, `created_at` DESC);
CREATE INDEX IF NOT EXISTS `idx_lease_audit_action` ON `nyx_property_lease_audits` (`action`, `created_at` DESC);
