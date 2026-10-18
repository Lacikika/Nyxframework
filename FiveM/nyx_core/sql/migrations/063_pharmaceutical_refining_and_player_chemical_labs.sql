-- ==============================================================================
-- Nyxframework Migration: Step 063
-- Title: Pharmaceutical Refining, Player Chemical Labs & Medical Bio-Synthesis
-- Resource: nyx_services & nyx_logistics
-- Targets: nyx_services_chemical_labs, nyx_services_chemlab_audits, nyx_logistics_nodes
-- ==============================================================================

-- 1. Chemical Synthesis & Autoclave Workstations Table
CREATE TABLE IF NOT EXISTS `nyx_services_chemical_labs` (
  `lab_id` VARCHAR(64) PRIMARY KEY,
  `lab_label` VARCHAR(128) NOT NULL,
  `substation_id` VARCHAR(64) NOT NULL,
  `coords` JSON NOT NULL,
  `heading` DECIMAL(6,2) NOT NULL DEFAULT 0.00,
  `power_draw_kw` DECIMAL(8,2) NOT NULL DEFAULT 15.00,
  `sterility_level` DECIMAL(5,2) NOT NULL DEFAULT 100.00,
  `autoclave_status` ENUM('idle', 'synthesizing', 'sterilizing', 'contaminated', 'offline_power') NOT NULL DEFAULT 'idle',
  `active_batch_recipe` VARCHAR(64) NULL,
  `active_batch_citizen_id` VARCHAR(64) NULL,
  `active_batch_start_time` BIGINT UNSIGNED NULL,
  `active_batch_duration` INT UNSIGNED NOT NULL DEFAULT 0,
  `active_batch_quantity` INT UNSIGNED NOT NULL DEFAULT 1,
  `total_batches_produced` INT UNSIGNED NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_chemlab_substation` (`substation_id`),
  INDEX `idx_chemlab_status` (`autoclave_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Chemical Laboratory Regulatory & Judicial Audit Ledger
CREATE TABLE IF NOT EXISTS `nyx_services_chemlab_audits` (
  `audit_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `lab_id` VARCHAR(64) NOT NULL,
  `citizen_id` VARCHAR(64) NOT NULL,
  `action` ENUM('SYNTHESIS_STARTED', 'SYNTHESIS_COMPLETED', 'SYNTHESIS_ABORTED', 'STERILIZATION_CYCLE', 'CONTAMINATION_OCCURRED', 'POWER_LOST') NOT NULL,
  `recipe_key` VARCHAR(64) NULL,
  `inputs_consumed` JSON NULL,
  `outputs_generated` JSON NULL,
  `sterility_before` DECIMAL(5,2) NOT NULL DEFAULT 100.00,
  `sterility_after` DECIMAL(5,2) NOT NULL DEFAULT 100.00,
  `notes` TEXT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_chemlab_audit_lab` (`lab_id`),
  INDEX `idx_chemlab_audit_citizen` (`citizen_id`),
  INDEX `idx_chemlab_audit_time` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Seed Canonical Chemical & Pharmaceutical Synthesis Workstations
INSERT INTO `nyx_services_chemical_labs`
  (`lab_id`, `lab_label`, `substation_id`, `coords`, `heading`, `power_draw_kw`, `sterility_level`, `autoclave_status`)
VALUES
  ('chemlab_humane_biotech', 'Humane Bio-Research Pharmacological Suite', 'grid_paleto', '{"x": 3538.5, "y": 3660.2, "z": 28.1}', 170.00, 20.00, 100.00, 'idle'),
  ('chemlab_cypress_refinery', 'Cypress Industrial Chemical Processing Lab', 'grid_port_ls', '{"x": 922.5, "y": -2148.0, "z": 30.5}', 90.00, 25.00, 95.00, 'idle'),
  ('chemlab_pillbox_pharmacy', 'Pillbox Hill Clinical Synthesis Laboratory', 'grid_city_01', '{"x": 356.2, "y": -598.4, "z": 43.3}', 250.00, 15.00, 100.00, 'idle'),
  ('chemlab_sandy_lab', 'Senora Desert Remote Bio-Synthesis Station', 'grid_sandy_01', '{"x": 1852.3, "y": 3680.1, "z": 34.2}', 30.00, 12.00, 85.00, 'idle')
ON DUPLICATE KEY UPDATE
  `lab_label` = VALUES(`lab_label`),
  `substation_id` = VALUES(`substation_id`),
  `coords` = VALUES(`coords`),
  `heading` = VALUES(`heading`),
  `power_draw_kw` = VALUES(`power_draw_kw`);

-- 4. Seed Chemical & Botanical Natural Resource Harvest Nodes in nyx_logistics_nodes
INSERT INTO `nyx_logistics_nodes`
  (`node_id`, `resource_item`, `current_reserve`, `max_reserve`, `regen_rate_per_hour`, `coords`)
VALUES
  ('node_humane_botanicals', 'organic_compounds', 600, 600, 60, '{"x": 3558.2, "y": 3672.4, "z": 28.1}'),
  ('node_el_burro_petrochem', 'chemical_precursors', 800, 800, 80, '{"x": 1390.5, "y": -2080.2, "z": 52.0}'),
  ('node_zancudo_brine', 'raw_saline_brine', 1000, 1000, 100, '{"x": -2210.4, "y": 2775.8, "z": 2.8}')
ON DUPLICATE KEY UPDATE
  `resource_item` = VALUES(`resource_item`),
  `max_reserve` = VALUES(`max_reserve`),
  `regen_rate_per_hour` = VALUES(`regen_rate_per_hour`),
  `coords` = VALUES(`coords`);
