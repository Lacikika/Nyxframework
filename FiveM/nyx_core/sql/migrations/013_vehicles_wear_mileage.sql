-- ============================================================================
-- Nyxframework: nyx_vehicles
-- Migration: 013_vehicles_wear_mileage.sql
-- Description: Authoritative vehicle mileage tracking (odometer), component
--              wear and tear (oil, brakes, transmission, suspension), and
--              certified mechanic maintenance service logs.
-- Engine: InnoDB | Charset: utf8mb4 | Collation: utf8mb4_unicode_ci
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. Jármű Futásteljesítmény és Alkatrész Kopás Nyilvántartás (Wear & Mileage)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_vehicles_wear` (
  `vin` VARCHAR(32) PRIMARY KEY,
  `plate` VARCHAR(12) NOT NULL,
  `mileage` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  `trip_odometer` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `oil_quality` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
  `brake_pad_wear` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
  `transmission_wear` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
  `suspension_wear` DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
  `last_service_mileage` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  `service_notes` VARCHAR(255) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  
  CONSTRAINT `fk_veh_wear_vin` FOREIGN KEY (`vin`) REFERENCES `nyx_vehicles_owned` (`vin`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 2. Szerviz és Karbantartási Napló (Maintenance & Diagnostic History)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nyx_vehicles_service_logs` (
  `log_id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `vin` VARCHAR(32) NOT NULL,
  `plate` VARCHAR(12) NOT NULL,
  `mechanic_citizen_id` VARCHAR(16) NOT NULL,
  `service_type` ENUM('oil_change', 'brake_replacement', 'transmission_overhaul', 'suspension_tune', 'full_inspection', 'odometer_reset') NOT NULL,
  `mileage_at_service` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  `cost` DECIMAL(15, 2) NOT NULL DEFAULT 0.00 CHECK (`cost` >= 0.00),
  `notes` VARCHAR(255) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT `fk_veh_service_vin` FOREIGN KEY (`vin`) REFERENCES `nyx_vehicles_owned` (`vin`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- 3. B-Fa Indexek a Valós Idejű Telemetriai Lekérdezésekhez
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS `idx_veh_wear_plate` ON `nyx_vehicles_wear` (`plate`);
CREATE INDEX IF NOT EXISTS `idx_veh_wear_mileage` ON `nyx_vehicles_wear` (`mileage`);
CREATE INDEX IF NOT EXISTS `idx_veh_service_vin` ON `nyx_vehicles_service_logs` (`vin`, `created_at` DESC);
CREATE INDEX IF NOT EXISTS `idx_veh_service_mechanic` ON `nyx_vehicles_service_logs` (`mechanic_citizen_id`);
