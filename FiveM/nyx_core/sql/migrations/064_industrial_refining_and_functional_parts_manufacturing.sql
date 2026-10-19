-- ==============================================================================
-- Nyxframework Migration: Step 064
-- Title: Industrial Refining Plants, Forestry Timber Harvesting & Functional Parts Manufacturing
-- Resource: nyx_logistics, nyx_services & nyx_inventory
-- Targets: nyx_logistics_refining_audits, nyx_logistics_facilities, nyx_logistics_nodes, nyx_inventories
-- ==============================================================================

-- 1. Industrial Refining & Fabrication Regulatory Audit Ledger
CREATE TABLE IF NOT EXISTS `nyx_logistics_refining_audits` (
  `audit_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `facility_id` VARCHAR(64) NOT NULL,
  `citizen_id` VARCHAR(64) NOT NULL,
  `action` ENUM('REFINING_STARTED', 'REFINING_COMPLETED', 'REFINING_HALTED_BLACKOUT', 'REFINING_RESUMED', 'PALLET_DISPATCHED') NOT NULL,
  `recipe_key` VARCHAR(64) NOT NULL,
  `batch_count` INT UNSIGNED NOT NULL DEFAULT 1,
  `inputs_consumed` JSON NULL,
  `outputs_generated` JSON NULL,
  `power_kwh_consumed` DECIMAL(10, 4) NOT NULL DEFAULT 0.0000,
  `substation_id` VARCHAR(64) NULL,
  `notes` TEXT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_refining_audit_facility` (`facility_id`),
  INDEX `idx_refining_audit_citizen` (`citizen_id`),
  INDEX `idx_refining_audit_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Seed Forestry and Agricultural Natural Resource Extraction Nodes in nyx_logistics_nodes
INSERT INTO `nyx_logistics_nodes`
  (`node_id`, `resource_item`, `current_reserve`, `max_reserve`, `regen_rate_per_hour`, `coords`)
VALUES
  ('node_paleto_forest_timber', 'raw_timber_logs', 600, 600, 60, '{"x": -570.4, "y": 5320.1, "z": 70.2}'),
  ('node_chiliad_redwood', 'raw_timber_logs', 500, 500, 50, '{"x": -790.6, "y": 5450.4, "z": 34.5}'),
  ('node_san_chianski_cotton', 'raw_cotton', 700, 700, 70, '{"x": 2580.4, "y": 4690.2, "z": 34.0}')
ON DUPLICATE KEY UPDATE
  `resource_item` = VALUES(`resource_item`),
  `max_reserve` = VALUES(`max_reserve`),
  `regen_rate_per_hour` = VALUES(`regen_rate_per_hour`),
  `coords` = VALUES(`coords`);

-- 3. Register Industrial Processing & Refining Facilities in nyx_logistics_facilities
ALTER TABLE `nyx_logistics_facilities`
  MODIFY COLUMN `type` ENUM('refinery', 'smelter', 'assembly', 'chemical', 'sawmill', 'foundry', 'textile', 'penal_workshop') NOT NULL;

INSERT INTO `nyx_logistics_facilities`
  (`facility_id`, `type`, `coords`, `input_inventory_id`, `output_inventory_id`, `power_grid_id`, `power_status`, `pallet_dock_coords`, `pallet_dock_heading`, `output_mode`)
VALUES
  ('fac_paleto_sawmill', 'sawmill', '{"x": -552.4, "y": 5324.8, "z": 73.6}', 'stash:sawmill_in', 'stash:sawmill_out', 'grid_paleto', 'online', '{"x": -546.0, "y": 5328.0, "z": 73.6}', 160.0, 'pallet'),
  ('fac_elysian_foundry', 'foundry', '{"x": 1088.5, "y": -2004.2, "z": 31.5}', 'stash:foundry_in', 'stash:foundry_out', 'grid_port_ls', 'online', '{"x": 1094.0, "y": -2008.0, "z": 31.5}', 90.0, 'pallet'),
  ('fac_davis_textile', 'textile', '{"x": 716.2, "y": -962.4, "z": 30.4}', 'stash:textile_in', 'stash:textile_out', 'grid_city_01', 'online', '{"x": 720.0, "y": -966.0, "z": 30.4}', 270.0, 'inventory')
ON DUPLICATE KEY UPDATE
  `type` = VALUES(`type`),
  `coords` = VALUES(`coords`),
  `input_inventory_id` = VALUES(`input_inventory_id`),
  `output_inventory_id` = VALUES(`output_inventory_id`),
  `power_grid_id` = VALUES(`power_grid_id`),
  `pallet_dock_coords` = VALUES(`pallet_dock_coords`),
  `pallet_dock_heading` = VALUES(`pallet_dock_heading`),
  `output_mode` = VALUES(`output_mode`);

-- 4. Seed Storage Inventories for Industrial Facilities in nyx_inventories
INSERT INTO `nyx_inventories` (`id`, `type`, `max_weight`, `max_slots`, `coords`)
VALUES
  ('stash:sawmill_in', 'stash', 2000000, 120, '{"x": -552.4, "y": 5324.8, "z": 73.6}'),
  ('stash:sawmill_out', 'stash', 2000000, 120, '{"x": -550.0, "y": 5326.0, "z": 73.6}'),
  ('stash:foundry_in', 'stash', 3000000, 150, '{"x": 1088.5, "y": -2004.2, "z": 31.5}'),
  ('stash:foundry_out', 'stash', 3000000, 150, '{"x": 1092.0, "y": -2006.0, "z": 31.5}'),
  ('stash:textile_in', 'stash', 1200000, 80, '{"x": 716.2, "y": -962.4, "z": 30.4}'),
  ('stash:textile_out', 'stash', 1200000, 80, '{"x": 718.0, "y": -964.0, "z": 30.4}')
ON DUPLICATE KEY UPDATE
  `type` = VALUES(`type`),
  `max_weight` = VALUES(`max_weight`),
  `max_slots` = VALUES(`max_slots`),
  `coords` = VALUES(`coords`);
