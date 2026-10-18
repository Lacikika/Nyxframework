-- Nyxframework Inventory & Storage Schema Update
-- Migration: 017_inventory_world_placement_rotation.sql
-- Description: Add rotation column to nyx_inventories to support orientation persistence
--              for placed world objects, ground drops, and containers.

ALTER TABLE `nyx_inventories`
ADD COLUMN `rotation` JSON NULL AFTER `coords`;
