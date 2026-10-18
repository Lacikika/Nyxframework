-- ============================================================================
-- Nyxframework: nyx_judiciary & nyx_logistics
-- Migration: 045_penal_labor_processing_and_sentence_reductions.sql
-- Description: Bolingbroke penitentiary industrial work benches, penal labor records,
--              sentence reduction tracking, civic treasury reserve contributions,
--              and workshop inventory stashes.
-- ============================================================================

-- 1. Penal Inmate Custodial & Labor Records
CREATE TABLE IF NOT EXISTS `nyx_judiciary_penal_records` (
  `record_id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizen_id` VARCHAR(64) NOT NULL UNIQUE,
  `original_sentence_months` INT NOT NULL DEFAULT 0,
  `current_sentence_months` INT NOT NULL DEFAULT 0,
  `labor_cycles_completed` INT NOT NULL DEFAULT 0,
  `total_reduction_months` INT NOT NULL DEFAULT 0,
  `total_civic_value_generated` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  `status` ENUM('incarcerated', 'paroled', 'released', 'escaped') NOT NULL DEFAULT 'incarcerated',
  `cell_assigned` VARCHAR(32) NULL DEFAULT 'cell_block_a',
  `last_labor_at` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_penal_status` (`status`),
  INDEX `idx_penal_cit` (`citizen_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Immutable Penal Labor Activity & Sentence Reduction Log
CREATE TABLE IF NOT EXISTS `nyx_judiciary_penal_labor_logs` (
  `log_id` INT AUTO_INCREMENT PRIMARY KEY,
  `log_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `citizen_id` VARCHAR(64) NOT NULL,
  `workstation_id` VARCHAR(64) NOT NULL,
  `recipe_id` VARCHAR(64) NOT NULL,
  `sentence_reduced_months` INT NOT NULL DEFAULT 0,
  `sentence_remaining_months` INT NOT NULL DEFAULT 0,
  `civic_funds_generated` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  `items_consumed_json` TEXT NULL,
  `items_produced_json` TEXT NULL,
  `destination_stash` VARCHAR(64) NOT NULL DEFAULT 'stash:bolingbroke_civic_output',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_labor_cit` (`citizen_id`),
  INDEX `idx_labor_recipe` (`recipe_id`),
  INDEX `idx_labor_workstation` (`workstation_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Seed Corrections Labor Account in Municipal Treasury
INSERT IGNORE INTO `nyx_treasury_accounts` (`account_id`, `label`, `balance`, `type`)
VALUES ('gov:corrections:penal_labor', 'Bolingbroke Penitentiary Labor Account', 1000000.00, 'reserve');

-- 4. Register Bolingbroke Industrial Stashes in nyx_inventories
INSERT INTO `nyx_inventories` (`id`, `type`, `max_weight`, `max_slots`, `coords`)
VALUES
  ('stash:bolingbroke_workshop', 'stash', 2000000, 100, '{"x": 1692.5, "y": 2568.2, "z": 45.5}'),
  ('stash:bolingbroke_civic_output', 'stash', 2000000, 100, '{"x": 1705.0, "y": 2577.5, "z": 45.5}')
ON DUPLICATE KEY UPDATE `type` = VALUES(`type`), `coords` = VALUES(`coords`);

-- 5. Seed initial raw materials into Bolingbroke Industrial Workshop Stash
INSERT INTO `nyx_inventory_items` (`item_uuid`, `inventory_id`, `item_id`, `slot`, `amount`, `metadata`)
VALUES
  (UUID(), 'stash:bolingbroke_workshop', 'refined_iron', 1, 50, '{"label": "Refined Iron Ingot"}'),
  (UUID(), 'stash:bolingbroke_workshop', 'plastic_polymer', 2, 40, '{"label": "Industrial Polymer"}'),
  (UUID(), 'stash:bolingbroke_workshop', 'raw_fabric', 3, 30, '{"label": "Industrial Cotton/Fabric Roll"}'),
  (UUID(), 'stash:bolingbroke_workshop', 'raw_timber', 4, 30, '{"label": "Industrial Lumber Bundle"}')
ON DUPLICATE KEY UPDATE `amount` = VALUES(`amount`);
