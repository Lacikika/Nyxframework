# Task Plan: Mechanical Diagnostics & Civic Impound Terminal (`nyx_ui` & `nyx_vehicles`)

## Goal
Implement an interactive Single-Frame CEF SPA terminal and diagnostics system for vehicles in Nyxframework. Players and certified mechanics can inspect vehicle mechanical wear (engine oil, brake pads, transmission, suspension), view active Diagnostic Trouble Codes (OBD-II DTCs), perform certified component repairs/maintenance, reset trip odometers, inspect and renew vehicle registrations, and retrieve/release impounded vehicles from municipal impound lots with double-entry treasury settlements and dynamic fiscal crisis surcharges.

## Architecture & Requirements
1. **Database Migration (`039_vehicles_diagnostics_and_civic_impound_terminal.sql` & `index.json`)**:
   - `nyx_vehicles_diagnostic_scans`: Scan UUID, VIN, plate, mechanic citizen ID, mileage, engine health, oil quality, brake pad wear, transmission wear, suspension wear, overall grade, DTC fault codes JSON, notes, scanned_at.
   - Extend `nyx_vehicles_wear`: `inspection_status` ENUM('passed', 'warning', 'failed', 'uninspected') DEFAULT 'uninspected', `last_inspection_at` INT UNSIGNED NULL, `inspector_citizen_id` VARCHAR(64) NULL.
   - Extend `nyx_vehicles_impound_lots`: `capacity` INT UNSIGNED DEFAULT 50, `is_automated_kiosk` TINYINT DEFAULT 1.
   - Register in `FiveM/nyx_core/sql/migrations/index.json` (Step 39) and mirror to `FiveM/nyx_vehicles/sql/migrations/`.

2. **Pure Lua 5.4 Shared Engine (`nyx_vehicles/shared/diagnostics.lua`)**:
   - `Nyx.VehicleDiagnostics.CalculateOverallGrade(engineHealth, oilQuality, brakePadWear, transmissionWear, suspensionWear)`: Weighted composite score (0-100) and taxonomy ('pristine', 'good', 'fair', 'critical', 'hazardous') plus roadworthiness boolean.
   - `Nyx.VehicleDiagnostics.GenerateDiagnosticCodes(wearData, engineHealth)`: Detects active OBD-II DTC trouble codes (`P0198`, `P0524`, `C0035`, `C0040`, `P0730`, `P0700`, `C1100`, `C1105`, `P0300`, `P0217`) with severity and subsystem tagging.
   - `Nyx.VehicleDiagnostics.CalculateServiceEstimate(wearData, serviceType, isCommercial)`: Computes labor and parts cost, required tools, and recovery delta.
   - `Nyx.VehicleDiagnostics.ValidateServicePayload(payload)`: Zero-trust payload sanitization for mechanic service actions.
   - `Nyx.VehicleDiagnostics.FormatWearBadge(percentage)`: 4-tier visual badge metadata (optimal, warning, urgent, danger).
   - `Nyx.VehicleDiagnostics.CalculateImpoundTotals(baseFee, elapsedDays, dailyRate, fiscalTier)`: Exact fee breakdown with treasury fiscal crisis surcharge rates (`solvent` 0%, `fiscal_stress` 15%, `degraded` 35%, `bankrupt` 60%).
   - `Nyx.VehicleDiagnostics.FilterVehiclesCatalog(vehicles, query, lotFilter, statusFilter)`: Case-insensitive search and filtering.
   - Register in `FiveM/nyx_vehicles/fxmanifest.lua`.

3. **Server Diagnostics & Impound Subsystem (`nyx_vehicles/server/diagnostics.lua`, `server/exports.lua`)**:
   - `GetDiagnosticsOverview`: Aggregates active vehicle wear, DTC codes, roadworthiness grade, registration state, owned vehicles, and impounded assets.
   - `ScanVehicle`: Executes certified OBD-II diagnostic scan, inserts into `nyx_vehicles_diagnostic_scans`, returns scan proof.
   - `PerformCertifiedService`: Validates service payload, deducts costs or repair kit tools, restores component wear to 100%, writes service log, and syncs to clients.
   - `GetCivicImpoundLots`: Returns impound lot registry with status and capacities.
   - Server RPC endpoints: `vehicles:getDiagnosticsOverview`, `vehicles:scanVehicle`, `vehicles:performCertifiedService`, `vehicles:getCivicImpoundLots`.
   - Server exports in `server/exports.lua`.

4. **Client Dispatch & UI Bridge (`nyx_vehicles/client/diagnostics.lua`, `nyx_ui/client/bridge.lua`, `nyx_ui/client/exports.lua`)**:
   - Client commands: `/diagnostics`, `/mechanic`, `/impound`, `/vehiclerotary`.
   - Third-Eye targets on municipal impound terminals and mechanic repair bays.
   - UI Bridge: Whitelist vehicle terminal parameters in `SanitizePayload`; register safe NUI callbacks (`closeVehicleTerminal`, `vehicle:getOverview`, `vehicle:scanOBD`, `vehicle:performService`, `vehicle:resetTrip`, `vehicle:releaseImpound`, `vehicle:renewRegistration`, `vehicle:getImpoundLots`).
   - Exports: `OpenVehicleTerminalUI`, `CloseVehicleTerminalUI`, view aliases in `OpenView`.

5. **Web Single-Frame CEF SPA (`nyx_ui/web/`)**:
   - HTML (`index.html`): Section 8G `#vehicle-terminal-overlay` modal with 3 tabs:
     1. Mechanikai Diagnosztika & Telemetria (wear gauges, DTC trouble codes, certified service action buttons, trip reset).
     2. Városi Autómentő & Lefoglalt Járművek (impound list, cost breakdown calculator, release settlement).
     3. Forgalmi Engedély & Hatósági Műszaki (registration status, expiration countdown, roadworthiness badge, renewal button).
     - Submodals `#vehicle-submodal-service`, `#vehicle-submodal-release`, and dev mode button `#dev-btn-vehicle`.
   - CSS (`css/app.css`): Section 21 CEF styling adhering to strict render budget (high-opacity dark surfaces, circular/linear gauge bars, DTC chips, touch targets $\ge 40$px, WCAG AA+ contrast, zero `backdrop-filter`).
   - JS (`js/app.js`): State management (`NyxState.vehicle`), event listeners (`VEHICLE_TERMINAL_OPEN`/`CLOSE`), tab switching, dynamic gauge rendering, DTC trouble code chips, service modal, impound release, registration renewal, button locking (`lockButtonAction`), hierarchical submodal escape handling, browser dev mode mock telemetry.

6. **In-Engine Integration Test (`FiveM/nyx_core/server/tests.lua`)**:
   - Add Test 34 `Nyx.Tests.TestVehicleDiagnosticsAndCivicImpoundUI()` validating shared math, RPC registration, and impound fee formulas.
   - Wire into `RunAll()`.

7. **Full Verification**:
   - Dedicated Python test suite `tests/test_vehicle_diagnostics_and_impound_ui.py`.
   - Full test suite via `pytest`.
   - Engine syntax and asset validation via `python scripts/validator.py` and `powershell -File scripts/verify.ps1`.
   - Update `AGENT_TASK.md` marking task completed.

## Phase Plan
- [x] Phase 1: Test-Driven Design — Create Python test suite (`tests/test_vehicle_diagnostics_and_impound_ui.py`)
- [x] Phase 2: Database Migration — Create `039_vehicles_diagnostics_and_civic_impound_terminal.sql`, register in `index.json`, mirror to `nyx_vehicles`
- [x] Phase 3: Pure Lua 5.4 Shared Engine — Implement `FiveM/nyx_vehicles/shared/diagnostics.lua` & update `fxmanifest.lua`
- [x] Phase 4: Server Diagnostics & Impound Subsystem — Implement `server/diagnostics.lua`, update `server/exports.lua` and `fxmanifest.lua`
- [x] Phase 5: Client Dispatch & UI Bridge — Implement `client/diagnostics.lua`, update `nyx_ui/client/bridge.lua`, and `nyx_ui/client/exports.lua`
- [x] Phase 6: Web Single-Frame CEF SPA — Update `index.html`, `css/app.css`, and `js/app.js`
- [x] Phase 7: In-Engine Lua Test Suite — Implement Test 34 in `FiveM/nyx_core/server/tests.lua`
- [x] Phase 8: Full Verification & Completion — Run pytest, validator, verify.ps1, update `AGENT_TASK.md`
