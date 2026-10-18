-- Nyxframework Logistics & Retail Point of Sale Schema
-- Migration: 062_point_of_sale_physical_stocking_and_empty_shelf_displays.sql
-- Description: In-world physical retail shelves, empty shelf prop swapping/despawning,
--              manual player restocking mechanics, and double-entry wholesale audit trails.

-- 1. Extend nyx_logistics_shelves with spatial coordinates, 3D prop models, and display modes
ALTER TABLE `nyx_logistics_shelves`
ADD COLUMN `coords` JSON NOT NULL DEFAULT '{"x": 0.0, "y": 0.0, "z": 0.0}' AFTER `inventory_id`,
ADD COLUMN `heading` DECIMAL(6,2) NOT NULL DEFAULT 0.00 AFTER `coords`,
ADD COLUMN `shelf_category` ENUM('convenience', 'hardware', 'arms', 'pharmacy', 'electronics', 'general') NOT NULL DEFAULT 'general' AFTER `heading`,
ADD COLUMN `shelf_label` VARCHAR(64) NOT NULL DEFAULT 'Retail Display Shelf' AFTER `shelf_category`,
ADD COLUMN `stocked_model` VARCHAR(64) NOT NULL DEFAULT 'prop_shelves_02' AFTER `shelf_label`,
ADD COLUMN `empty_model` VARCHAR(64) NOT NULL DEFAULT 'prop_rack_empty' AFTER `stocked_model`,
ADD COLUMN `display_mode` ENUM('prop_swap', 'sparse_stock', 'stocked_prop') NOT NULL DEFAULT 'prop_swap' AFTER `empty_model`,
ADD COLUMN `is_restockable` TINYINT(1) NOT NULL DEFAULT 1 AFTER `display_mode`,
ADD INDEX `idx_shelf_category` (`shelf_category`),
ADD INDEX `idx_shelf_restockable` (`is_restockable`);

-- 2. Create immutable audit ledger for manual restocking and physical shelf transitions
CREATE TABLE IF NOT EXISTS `nyx_logistics_shelf_restock_audits` (
  `audit_id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `shelf_id` VARCHAR(64) NOT NULL,
  `store_id` VARCHAR(32) NOT NULL,
  `citizen_id` VARCHAR(64) NOT NULL,
  `action` ENUM('RESTOCK_MANUAL', 'PURCHASE', 'STOCK_TRANSFER', 'SHELF_EMPTIED', 'SHELF_RESTOCKED') NOT NULL,
  `item_id` VARCHAR(64) NOT NULL,
  `quantity` INT NOT NULL,
  `previous_stock` INT NOT NULL,
  `new_stock` INT NOT NULL,
  `unit_price` DECIMAL(10,2) NOT NULL,
  `wholesale_payout` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `treasury_tx_uuid` VARCHAR(64) NULL,
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_shelf_audit` (`shelf_id`),
  INDEX `idx_citizen_audit` (`citizen_id`),
  INDEX `idx_action` (`action`),
  INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Update existing seed shelves with spatial locations and prop models
UPDATE `nyx_logistics_shelves`
SET `coords` = '{"x": 373.8, "y": 325.8, "z": 103.5}',
    `heading` = 255.00,
    `shelf_category` = 'hardware',
    `shelf_label` = 'Vinewood 24/7 Tools & Equipment Rack',
    `stocked_model` = 'prop_rub_cabinet02',
    `empty_model` = 'prop_pallet_01a',
    `display_mode` = 'prop_swap',
    `is_restockable` = 1
WHERE `shelf_id` = 'shelf_vinewood_tools';

UPDATE `nyx_logistics_shelves`
SET `coords` = '{"x": 312.4, "y": -593.2, "z": 43.2}',
    `heading` = 180.00,
    `shelf_category` = 'pharmacy',
    `shelf_label` = 'Pillbox Hill Medical Supplies Rack',
    `stocked_model` = 'prop_med_wall_rack',
    `empty_model` = 'prop_rack_empty',
    `display_mode` = 'prop_swap',
    `is_restockable` = 1
WHERE `shelf_id` = 'shelf_pillbox_meds';

-- 4. Seed Canonical Retail Shelves across Los Santos and Blaine County
INSERT IGNORE INTO `nyx_logistics_shelves`
(`shelf_id`, `store_id`, `zone_id`, `target_capacity`, `item_id`, `base_price`, `current_price`, `inventory_id`, `coords`, `heading`, `shelf_category`, `shelf_label`, `stocked_model`, `empty_model`, `display_mode`, `is_restockable`)
VALUES
('shelf_vinewood_247_groceries', 'store_vinewood_247', 'zone_ls_metro', 80, 'food_bread', 12.00, 12.00, 'stash:vinewood_groceries',
 '{"x": 374.8, "y": 327.9, "z": 103.5}', 75.00, 'convenience', 'Vinewood 24/7 Fresh Bread & Groceries Shelf', 'prop_shelves_02', 'prop_rack_empty', 'prop_swap', 1),

('shelf_vinewood_247_beverages', 'store_vinewood_247', 'zone_ls_metro', 100, 'drink_water', 8.00, 8.00, 'stash:vinewood_beverages',
 '{"x": 375.9, "y": 326.1, "z": 103.5}', 165.00, 'convenience', 'Vinewood 24/7 Cold Beverage Refrigerator', 'prop_fridge_01', 'prop_fridge_empty', 'prop_swap', 1),

('shelf_ammunation_dt_ammo', 'store_ammu_downtown', 'zone_ls_metro', 200, 'ammo_9mm', 25.00, 25.00, 'stash:ammu_dt_ammo',
 '{"x": 22.1, "y": -1107.2, "z": 29.8}', 160.00, 'arms', 'Ammu-Nation Downtown 9mm Ammunition Dispenser', 'prop_gun_rack_01', 'prop_gun_rack_empty', 'prop_swap', 1),

('shelf_sandy_hardware_parts', 'store_sandy_hardware', 'zone_sandy_shores', 60, 'crate_machinery_parts', 120.00, 120.00, 'stash:sandy_parts',
 '{"x": 1845.2, "y": 3782.1, "z": 33.5}', 210.00, 'hardware', 'Sandy Shores Industrial Machine Components', 'prop_rub_cabinet02', 'prop_pallet_01a', 'prop_swap', 1),

('shelf_paleto_general_food', 'store_paleto_general', 'zone_paleto_bay', 75, 'crop_produce', 15.00, 15.00, 'stash:paleto_produce',
 '{"x": -140.5, "y": 6350.2, "z": 31.5}', 45.00, 'convenience', 'Paleto Bay Enclave Farm-Fresh Produce Crate', 'prop_boxpile_05a', 'prop_pallet_01a', 'prop_swap', 1);
