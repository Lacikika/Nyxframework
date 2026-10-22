-- ============================================================================
-- Nyxframework: nyx_properties, nyx_treasury, nyx_factions & nyx_parliament
-- Migration: 067_property_zoning_and_building_permits.sql
-- Description: Commercial renovation approvals, municipal inspection fee routing,
--              architectural blueprint validation, statutory zoning rules,
--              and environmental impact surcharges.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Create Property Zoning Rules Table
CREATE TABLE IF NOT EXISTS `nyx_property_zoning_rules` (
  `zoning_type` VARCHAR(32) NOT NULL PRIMARY KEY,
  `label` VARCHAR(128) NOT NULL,
  `max_floor_area_sqm` INT NOT NULL DEFAULT 2000,
  `max_height_meters` DECIMAL(6, 2) NOT NULL DEFAULT 25.00,
  `base_permit_fee` DECIMAL(10, 2) NOT NULL DEFAULT 500.00,
  `inspection_fee_flat` DECIMAL(10, 2) NOT NULL DEFAULT 250.00,
  `environmental_surcharge_rate` DECIMAL(5, 4) NOT NULL DEFAULT 0.0200,
  `requires_certified_blueprint` TINYINT(1) NOT NULL DEFAULT 1,
  `auto_approval_eligible` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_zoning_auto` (`auto_approval_eligible`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Create Architectural Blueprints Table
CREATE TABLE IF NOT EXISTS `nyx_architectural_blueprints` (
  `blueprint_id` VARCHAR(64) NOT NULL PRIMARY KEY,
  `architect_identifier` VARCHAR(64) NOT NULL,
  `title` VARCHAR(128) NOT NULL,
  `target_zoning` VARCHAR(32) NOT NULL,
  `floor_area_sqm` INT NOT NULL DEFAULT 250,
  `structural_tier` INT NOT NULL DEFAULT 1,
  `blueprint_cost` DECIMAL(10, 2) NOT NULL DEFAULT 1000.00,
  `is_certified` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_bp_architect` (`architect_identifier`),
  INDEX `idx_bp_zoning` (`target_zoning`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Create Building Permits Table
CREATE TABLE IF NOT EXISTS `nyx_building_permits` (
  `permit_id` VARCHAR(32) NOT NULL PRIMARY KEY,
  `property_id` VARCHAR(64) NOT NULL,
  `applicant_identifier` VARCHAR(64) NOT NULL,
  `applicant_faction` VARCHAR(64) NULL,
  `zoning_type` VARCHAR(32) NOT NULL,
  `renovation_type` ENUM('interior_remodel', 'facade_modernization', 'structural_expansion', 'safety_upgrade', 'industrial_conversion') NOT NULL DEFAULT 'interior_remodel',
  `blueprint_id` VARCHAR(64) NOT NULL,
  `floor_area_sqm` INT NOT NULL DEFAULT 150,
  `base_permit_fee` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `inspection_fee` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `environmental_surcharge` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `blueprint_cost` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `total_cost` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `status` ENUM('SUBMITTED', 'INSPECTION_PENDING', 'APPROVED', 'REJECTED', 'COMPLETED', 'REVOKED') NOT NULL DEFAULT 'SUBMITTED',
  `inspector_identifier` VARCHAR(64) NULL,
  `rejection_reason` TEXT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `approved_at` TIMESTAMP NULL DEFAULT NULL,
  `completed_at` TIMESTAMP NULL DEFAULT NULL,
  INDEX `idx_permit_prop` (`property_id`),
  INDEX `idx_permit_applicant` (`applicant_identifier`),
  INDEX `idx_permit_status` (`status`),
  INDEX `idx_permit_zoning` (`zoning_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Seed Statutory Property Zoning Rules
INSERT INTO `nyx_property_zoning_rules`
  (`zoning_type`, `label`, `max_floor_area_sqm`, `max_height_meters`, `base_permit_fee`, `inspection_fee_flat`, `environmental_surcharge_rate`, `requires_certified_blueprint`, `auto_approval_eligible`)
VALUES
  ('retail_storefront', 'Retail Commercial District', 1500, 20.00, 450.00, 200.00, 0.0150, 1, 1),
  ('corporate_office', 'Corporate Executive District', 3000, 60.00, 850.00, 350.00, 0.0200, 1, 0),
  ('industrial_warehouse', 'Industrial Logistics Zone', 10000, 35.00, 1200.00, 500.00, 0.0350, 1, 0),
  ('hospitality_venue', 'Commercial Entertainment Sector', 2500, 25.00, 650.00, 300.00, 0.0250, 1, 0),
  ('medical_clinic', 'Public Health & Clinical Complex', 2000, 30.00, 750.00, 400.00, 0.0100, 1, 0)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

-- 5. Seed Standard Architectural Blueprints
INSERT INTO `nyx_architectural_blueprints`
  (`blueprint_id`, `architect_identifier`, `title`, `target_zoning`, `floor_area_sqm`, `structural_tier`, `blueprint_cost`, `is_certified`)
VALUES
  ('bp_retail_mod_v1', 'arch_city_planning', 'Standard Retail Interior Modernization', 'retail_storefront', 250, 1, 750.00, 1),
  ('bp_office_expansion_v1', 'arch_city_planning', 'Executive Office Suite Expansion', 'corporate_office', 600, 2, 1500.00, 1),
  ('bp_warehouse_mezzanine_v1', 'arch_city_planning', 'Heavy Industrial Mezzanine Blueprint', 'industrial_warehouse', 2500, 3, 3000.00, 1),
  ('bp_hospitality_lounge_v1', 'arch_city_planning', 'Commercial Dining & Lounge Layout', 'hospitality_venue', 500, 2, 1250.00, 1)
ON DUPLICATE KEY UPDATE `title` = VALUES(`title`);

SET FOREIGN_KEY_CHECKS = 1;
