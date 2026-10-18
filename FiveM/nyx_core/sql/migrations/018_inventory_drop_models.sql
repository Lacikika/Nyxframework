-- Nyxframework Inventory Schema Update
-- Migration: 018_inventory_drop_models.sql
-- Description: Add model column to nyx_inventories to persist smart fallback and custom 3D container props.

ALTER TABLE `nyx_inventories`
ADD COLUMN `model` VARCHAR(64) NULL AFTER `rotation`;
