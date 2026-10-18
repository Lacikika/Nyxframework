-- ============================================================================
-- Nyxframework Logistics Engine Database Migration
-- File: 010_logistics_freight_board.sql
-- Description: Authoritative Freight Hauling Exchange, Dynamic Shortage Dispatch,
--              Escrow Bond Locking, and Transactional Chain-of-Custody Audit Ledger.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Fő Fuvarozási Szerződés Nyilvántartás (Freight Contracts Board)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_logistics_freight_contracts` (
  `contract_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `contract_uuid` VARCHAR(36) NOT NULL,
  `contract_type` ENUM('shortage_auto', 'facility_transfer', 'corporate_dispatch') NOT NULL DEFAULT 'shortage_auto',
  `issuer_type` ENUM('system_shortage', 'municipal_store', 'corporate_faction', 'private_merchant') NOT NULL DEFAULT 'system_shortage',
  `issuer_id` VARCHAR(64) NOT NULL,
  `title` VARCHAR(128) NOT NULL,
  
  -- Leltári forrás- és célhivatkozások (Zero-Trust tároló integritás)
  `source_inventory_id` VARCHAR(64) NOT NULL,
  `dest_inventory_id` VARCHAR(64) NOT NULL,
  `source_coords` JSON NOT NULL,
  `dest_coords` JSON NOT NULL,
  
  -- Rakomány és Mennyiségi Megszorítások
  `item_id` VARCHAR(64) NOT NULL,
  `quantity` INT UNSIGNED NOT NULL CHECK (`quantity` > 0),
  
  -- Pénzügyi Számítások (Kizárólag DECIMAL(15, 2) pozitív megszorítással)
  `payout_per_unit` DECIMAL(15, 2) NOT NULL CHECK (`payout_per_unit` >= 0.00),
  `total_payout` DECIMAL(15, 2) NOT NULL CHECK (`total_payout` >= 0.00),
  `escrow_deposit` DECIMAL(15, 2) NOT NULL DEFAULT 0.00 CHECK (`escrow_deposit` >= 0.00),
  
  -- Életciklus és Sofőr Hozzárendelés
  `status` ENUM('available', 'in_transit', 'completed', 'expired', 'cancelled', 'forfeited') NOT NULL DEFAULT 'available',
  `claimed_by_char_id` INT NULL,
  `claimed_by_citizen_id` VARCHAR(16) NULL,
  
  -- Időzítési és Lejárati Határidők
  `deadline_seconds` INT UNSIGNED NOT NULL DEFAULT 1800,
  `claimed_at` TIMESTAMP NULL DEFAULT NULL,
  `expires_at` TIMESTAMP NULL DEFAULT NULL,
  `completed_at` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  
  -- Idempotens Egyediségi és Idegen Kulcs Megszorítások
  CONSTRAINT `uq_contract_uuid` UNIQUE (`contract_uuid`),
  CONSTRAINT `fk_freight_src_inv` FOREIGN KEY (`source_inventory_id`) REFERENCES `nyx_inventories` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `fk_freight_dst_inv` FOREIGN KEY (`dest_inventory_id`) REFERENCES `nyx_inventories` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `fk_freight_claimed_char` FOREIGN KEY (`claimed_by_char_id`) REFERENCES `nyx_characters` (`char_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `fk_freight_claimed_cit` FOREIGN KEY (`claimed_by_citizen_id`) REFERENCES `nyx_characters` (`citizen_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 2. Fuvarozási Tranzakciós és Letéti Audit Főkönyv (Chain-of-Custody Ledger)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_logistics_freight_audit` (
  `audit_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `contract_id` BIGINT UNSIGNED NOT NULL,
  `action` ENUM('CONTRACT_CREATED', 'ESCROW_LOCKED', 'FREIGHT_LOADED', 'DELIVERY_FULFILLED', 'ESCROW_REFUNDED', 'ESCROW_FORFEITED', 'CONTRACT_ABANDONED', 'CONTRACT_EXPIRED') NOT NULL,
  `carrier_citizen_id` VARCHAR(16) NULL,
  `amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00 CHECK (`amount` >= 0.00),
  `debit_account` VARCHAR(64) NOT NULL,
  `credit_account` VARCHAR(64) NOT NULL,
  `treasury_tx_uuid` VARCHAR(36) NULL,
  `vehicle_net_id` INT NULL,
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT `fk_freight_audit_contract` FOREIGN KEY (`contract_id`) REFERENCES `nyx_logistics_freight_contracts` (`contract_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- 3. B-Fa Indexelési Stratégia
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS `idx_freight_board_feed` 
  ON `nyx_logistics_freight_contracts` (`status`, `contract_type`, `created_at` DESC);

CREATE INDEX IF NOT EXISTS `idx_freight_expiry_sweep` 
  ON `nyx_logistics_freight_contracts` (`status`, `expires_at`);

CREATE INDEX IF NOT EXISTS `idx_freight_active_carrier` 
  ON `nyx_logistics_freight_contracts` (`claimed_by_citizen_id`, `status`);

CREATE INDEX IF NOT EXISTS `idx_freight_dest_dedup` 
  ON `nyx_logistics_freight_contracts` (`dest_inventory_id`, `status`);

CREATE INDEX IF NOT EXISTS `idx_freight_audit_contract_timeline` 
  ON `nyx_logistics_freight_audit` (`contract_id`, `created_at` ASC);

CREATE INDEX IF NOT EXISTS `idx_freight_audit_carrier_action` 
  ON `nyx_logistics_freight_audit` (`carrier_citizen_id`, `action`);
