-- ============================================================================
-- Nyxframework: nyx_services & nyx_logistics
-- Migration: 042_pillbox_hospital_supply_depletion_and_emergency_hauls.sql
-- Description: Finite medical inventory container mapping (stash:pillbox_meds),
--              hospital supply threshold tracking, and emergency logistics haul audit.
-- ============================================================================

-- 1. Extend nyx_services_hospitals with stash linkage and dynamic threshold parameters
ALTER TABLE `nyx_services_hospitals`
  ADD COLUMN IF NOT EXISTS `stash_id` VARCHAR(64) NOT NULL DEFAULT 'stash:pillbox_meds' AFTER `substation_id`,
  ADD COLUMN IF NOT EXISTS `critical_threshold` INT NOT NULL DEFAULT 5 AFTER `surgical_packs`,
  ADD COLUMN IF NOT EXISTS `degraded_threshold` INT NOT NULL DEFAULT 15 AFTER `critical_threshold`,
  ADD COLUMN IF NOT EXISTS `last_emergency_contract_at` TIMESTAMP NULL DEFAULT NULL AFTER `status`;

-- 2. Link hospitals to finite containers
UPDATE `nyx_services_hospitals`
SET `stash_id` = 'stash:pillbox_meds',
    `critical_threshold` = 5,
    `degraded_threshold` = 15
WHERE `hospital_id` = 'pillbox_hill';

UPDATE `nyx_services_hospitals`
SET `stash_id` = 'stash:sandy_clinic_meds',
    `critical_threshold` = 3,
    `degraded_threshold` = 10
WHERE `hospital_id` = 'sandy_shores_clinic';

UPDATE `nyx_services_hospitals`
SET `stash_id` = 'stash:paleto_hospital_meds',
    `critical_threshold` = 2,
    `degraded_threshold` = 8
WHERE `hospital_id` = 'paleto_bay_hospital';

-- 3. Register and seed finite hospital containers in nyx_inventories
INSERT INTO `nyx_inventories` (`id`, `type`, `max_weight`, `max_slots`, `coords`)
VALUES
  ('stash:pillbox_meds', 'stash', 250000, 100, '{"x": 340.0, "y": -1396.0, "z": 32.5}'),
  ('stash:sandy_clinic_meds', 'stash', 150000, 60, '{"x": 1839.5, "y": 3672.5, "z": 34.3}'),
  ('stash:paleto_hospital_meds', 'stash', 150000, 60, '{"x": -247.0, "y": 6331.0, "z": 32.4}')
ON DUPLICATE KEY UPDATE `type` = VALUES(`type`), `coords` = VALUES(`coords`);

-- 4. Seed initial finite medical inventory stock into stash:pillbox_meds
INSERT INTO `nyx_inventory_items` (`item_uuid`, `inventory_id`, `item_id`, `slot`, `amount`, `metadata`)
VALUES
  (UUID(), 'stash:pillbox_meds', 'med_plasma', 1, 30, '{"label": "Refrigerated IV Plasma Unit"}'),
  (UUID(), 'stash:pillbox_meds', 'med_firstaid', 2, 25, '{"label": "Trauma First Aid Kit"}'),
  (UUID(), 'stash:pillbox_meds', 'med_surgical_pack', 3, 15, '{"label": "Sterile Surgical Pack"}'),
  (UUID(), 'stash:pillbox_meds', 'bandage_sterile', 4, 50, '{"label": "Sterile Pressure Bandage"}'),
  (UUID(), 'stash:pillbox_meds', 'tourniquet', 5, 20, '{"label": "Combat Application Tourniquet"}')
ON DUPLICATE KEY UPDATE `amount` = VALUES(`amount`);

-- 5. Immutable audit log for hospital supply events and courier emergency haul contracts
CREATE TABLE IF NOT EXISTS `nyx_services_hospital_supply_audit` (
  `audit_id` INT AUTO_INCREMENT PRIMARY KEY,
  `audit_uuid` VARCHAR(64) NOT NULL UNIQUE,
  `hospital_id` VARCHAR(32) NOT NULL,
  `stash_id` VARCHAR(64) NOT NULL,
  `action` ENUM('CONSUMED', 'RESTOCKED', 'SHORTAGE_ALERT', 'CONTRACT_TRIGGERED', 'DELIVERY_FULFILLED') NOT NULL,
  `item_id` VARCHAR(64) NOT NULL,
  `quantity` INT NOT NULL,
  `remaining_count` INT NOT NULL,
  `status` ENUM('optimal', 'degraded', 'critical_shortage') NOT NULL,
  `citizen_id` VARCHAR(64) NULL,
  `contract_id` INT NULL,
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_hospital_audit` (`hospital_id`),
  INDEX `idx_stash_audit` (`stash_id`),
  INDEX `idx_action_audit` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
