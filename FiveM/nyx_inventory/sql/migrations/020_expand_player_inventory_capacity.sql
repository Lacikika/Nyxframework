-- Nyxframework Inventory Schema Migration: 020_expand_player_inventory_capacity.sql
-- Description: Expand baseline player inventory carry capacity from 30kg to 60kg (60,000g).

-- 1. Alter default column constraint for nyx_inventories table
ALTER TABLE `nyx_inventories`
    MODIFY COLUMN `max_weight` INT UNSIGNED NOT NULL DEFAULT 60000;

-- 2. Upgrade all existing player character inventories to 60kg limit
UPDATE `nyx_inventories`
SET `max_weight` = 60000
WHERE `type` = 'player' AND `max_weight` = 30000;
