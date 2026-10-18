-- ============================================================================
-- Nyxframework Factions Engine Database Migration
-- File: 034_factions_corporate_ui_and_rbac_audit.sql
-- Description: Immutable RBAC Permission Audit Logs, Corporate UI Metadata,
--              and CBA Contract Builder Annotation Fields.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Immutable RBAC Roster & Permission Node Audit Trail
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_factions_rbac_audit` (
  `audit_id` INT AUTO_INCREMENT PRIMARY KEY,
  `faction_id` VARCHAR(32) NOT NULL,
  `actor_citizen_id` VARCHAR(64) NOT NULL,
  `target_citizen_id` VARCHAR(64) NOT NULL,
  `action_type` VARCHAR(32) NOT NULL, -- 'INVITE', 'UPDATE_PERMISSIONS', 'UPDATE_EQUITY', 'UPDATE_WAGE', 'TERMINATE'
  `old_values` JSON NULL DEFAULT NULL,
  `new_values` JSON NULL DEFAULT NULL,
  `notes` VARCHAR(255) NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_rbac_faction` (`faction_id`),
  INDEX `idx_rbac_target` (`target_citizen_id`),
  INDEX `idx_rbac_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- 2. Extend CBA Table with Contract Builder Notes & Terms Annotation
-- ----------------------------------------------------------------------------
ALTER TABLE `nyx_factions_cba`
  ADD COLUMN IF NOT EXISTS `cba_notes` VARCHAR(255) NULL AFTER `hazard_pay_bonus`;

SET FOREIGN_KEY_CHECKS = 1;
