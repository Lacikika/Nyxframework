-- Nyxframework Logistics & Warehousing Schema Update
-- Migration: 019_logistics_warehouses_and_shelf_matrices.sql
-- Description: Physical 3D shelf matrices, grid snapping nodes, and virtual routing bucket isolation.

-- 1. Extend nyx_inventories with virtual routing bucket and shelf node linkage
ALTER TABLE `nyx_inventories`
ADD COLUMN `routing_bucket` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `model`,
ADD COLUMN `shelf_node_id` VARCHAR(64) NULL AFTER `routing_bucket`,
ADD INDEX `idx_routing_bucket` (`routing_bucket`),
ADD INDEX `idx_shelf_node` (`shelf_node_id`);

-- 2. Storage warehouses and logistics hubs
CREATE TABLE IF NOT EXISTS `nyx_logistics_warehouses` (
  `warehouse_id` VARCHAR(64) PRIMARY KEY,
  `name` VARCHAR(128) NOT NULL,
  `owner_faction_id` VARCHAR(64) NULL,
  `zone_id` VARCHAR(64) NOT NULL DEFAULT 'zone_ls_metro',
  `exterior_coords` JSON NOT NULL,
  `interior_coords` JSON NOT NULL,
  `routing_bucket` INT UNSIGNED NOT NULL,
  `is_locked` TINYINT(1) DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_zone` (`zone_id`),
  INDEX `idx_bucket` (`routing_bucket`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Physical 3D shelf rack units placed inside warehouses
CREATE TABLE IF NOT EXISTS `nyx_logistics_warehouse_shelves` (
  `shelf_id` VARCHAR(64) PRIMARY KEY,
  `warehouse_id` VARCHAR(64) NOT NULL,
  `label` VARCHAR(64) NOT NULL DEFAULT 'Shelf Unit',
  `model` VARCHAR(64) NOT NULL DEFAULT 'prop_rub_cabinet02',
  `coords` JSON NOT NULL,
  `rotation` JSON NOT NULL,
  `tiers` INT UNSIGNED NOT NULL DEFAULT 3,
  `slots_per_tier` INT UNSIGNED NOT NULL DEFAULT 3,
  `tier_spacing` DECIMAL(4, 2) NOT NULL DEFAULT 0.50,
  `slot_spacing` DECIMAL(4, 2) NOT NULL DEFAULT 0.55,
  `tier_base_z` DECIMAL(4, 2) NOT NULL DEFAULT 0.35,
  `depth_offset` DECIMAL(4, 2) NOT NULL DEFAULT 0.05,
  `routing_bucket` INT UNSIGNED NOT NULL DEFAULT 0,
  FOREIGN KEY (`warehouse_id`) REFERENCES `nyx_logistics_warehouses`(`warehouse_id`) ON DELETE CASCADE,
  INDEX `idx_wh` (`warehouse_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Precalculated / persisted grid snap nodes
CREATE TABLE IF NOT EXISTS `nyx_logistics_shelf_nodes` (
  `node_id` VARCHAR(64) PRIMARY KEY,
  `shelf_id` VARCHAR(64) NOT NULL,
  `warehouse_id` VARCHAR(64) NOT NULL,
  `tier` INT UNSIGNED NOT NULL,
  `slot` INT UNSIGNED NOT NULL,
  `world_coords` JSON NOT NULL,
  `heading` DECIMAL(6, 2) NOT NULL,
  `occupied_drop_id` VARCHAR(64) NULL,
  `routing_bucket` INT UNSIGNED NOT NULL DEFAULT 0,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_shelf` (`shelf_id`),
  INDEX `idx_warehouse` (`warehouse_id`),
  INDEX `idx_drop` (`occupied_drop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 5. Seed Initial High-Capacity Warehouses & Physical Shelf Matrices
INSERT IGNORE INTO `nyx_logistics_warehouses` 
(`warehouse_id`, `name`, `zone_id`, `exterior_coords`, `interior_coords`, `routing_bucket`, `is_locked`)
VALUES
('wh_dock_ls_01', 'Port of Los Santos Terminal Warehouse 4', 'zone_port_industrial', 
 '{"x": 899.6, "y": -2982.5, "z": -4.0, "h": 90.0}', 
 '{"x": 1048.5, "y": -3100.0, "z": -39.0, "h": 90.0}', 
 3001, 0),
('wh_sandy_dist_01', 'Sandy Shores Industrial Freight Depot', 'zone_sandy_shores', 
 '{"x": 1700.2, "y": 3780.5, "z": 34.5, "h": 210.0}', 
 '{"x": 1048.5, "y": -3100.0, "z": -39.0, "h": 90.0}', 
 3002, 0);

INSERT IGNORE INTO `nyx_logistics_warehouse_shelves`
(`shelf_id`, `warehouse_id`, `label`, `model`, `coords`, `rotation`, `tiers`, `slots_per_tier`, `tier_spacing`, `slot_spacing`, `tier_base_z`, `depth_offset`, `routing_bucket`)
VALUES
('wh_dock_shelf_01', 'wh_dock_ls_01', 'Bay A - Heavy Pallet Rack', 'prop_rub_cabinet02',
 '{"x": 1052.0, "y": -3096.0, "z": -39.0}', '{"heading": 90.0}', 3, 3, 0.50, 0.55, 0.35, 0.05, 3001),
('wh_dock_shelf_02', 'wh_dock_ls_01', 'Bay B - Parts & Tools Rack', 'prop_rub_cabinet02',
 '{"x": 1052.0, "y": -3104.0, "z": -39.0}', '{"heading": 90.0}', 3, 3, 0.50, 0.55, 0.35, 0.05, 3001),
('wh_sandy_shelf_01', 'wh_sandy_dist_01', 'Section 1 - Raw Ore Rack', 'prop_rub_cabinet02',
 '{"x": 1052.0, "y": -3096.0, "z": -39.0}', '{"heading": 90.0}', 3, 3, 0.50, 0.55, 0.35, 0.05, 3002),
('wh_sandy_shelf_02', 'wh_sandy_dist_01', 'Section 2 - Refining Supplies Rack', 'prop_rub_cabinet02',
 '{"x": 1052.0, "y": -3104.0, "z": -39.0}', '{"heading": 90.0}', 3, 3, 0.50, 0.55, 0.35, 0.05, 3002);
