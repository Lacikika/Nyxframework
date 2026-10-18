-- Nyxframework: nyx_properties & nyx_ui
-- Migration: 037_property_blind_auction_and_stewardship_portal.sql
-- Description: Immutable blind-auction bid ledger, auction confidentiality flags,
--              and stewardship proxy revocation audit annotations.

-- 1. Extend nyx_property_auctions with blind-auction confidentiality & bid counter
ALTER TABLE `nyx_property_auctions`
    ADD COLUMN IF NOT EXISTS `is_blind` TINYINT(1) NOT NULL DEFAULT 1 AFTER `auction_status`,
    ADD COLUMN IF NOT EXISTS `total_bids_placed` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `highest_bid`;

-- 2. Create immutable blind-auction sealed bid ledger
CREATE TABLE IF NOT EXISTS `nyx_property_auction_bids` (
    `bid_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `auction_id` INT UNSIGNED NOT NULL,
    `bidder_citizen_id` VARCHAR(16) NOT NULL,
    `bid_amount` DECIMAL(15, 2) NOT NULL,
    `is_refunded` TINYINT(1) NOT NULL DEFAULT 0,
    `is_sealed` TINYINT(1) NOT NULL DEFAULT 1,
    `placed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `refunded_at` TIMESTAMP NULL DEFAULT NULL,
    `treasury_tx_uuid` VARCHAR(36) NULL DEFAULT NULL,
    INDEX `idx_auction_bids_auction` (`auction_id`),
    INDEX `idx_auction_bids_bidder` (`bidder_citizen_id`),
    INDEX `idx_auction_bids_placed` (`placed_at`),
    CONSTRAINT `fk_auction_bids_auction` FOREIGN KEY (`auction_id`) REFERENCES `nyx_property_auctions` (`auction_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Extend nyx_stewardship_delegates with revocation reason notes
ALTER TABLE `nyx_stewardship_delegates`
    ADD COLUMN IF NOT EXISTS `revocation_reason` VARCHAR(255) NULL DEFAULT NULL AFTER `revoked_at`;
