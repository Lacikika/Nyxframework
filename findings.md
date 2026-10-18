# Findings: Mechanical Diagnostics & Civic Impound Terminal (`nyx_ui` & `nyx_vehicles`)

## Context & Architecture
1. **Vehicle Persistence & Wear (`nyx_vehicles`)**:
   - `009_vehicles_persistence.sql` creates `nyx_vehicles_owned`.
   - `013_vehicles_wear_mileage.sql` creates `nyx_vehicles_wear` (oil_quality, brake_pad_wear, transmission_wear, suspension_wear, mileage, trip_odometer) and `nyx_vehicles_service_logs`.
   - `030_treasury_infrastructure_degradation_and_vehicle_impounds.sql` creates `nyx_vehicles_impound_lots` and `nyx_vehicles_impound_logs`, plus extends `nyx_vehicles_owned` with `registration_status`, `registration_expires_at`, `impound_lot_id`, `impound_fee`, `impounded_at`.
   - In `server/wear.lua`: `LoadWear`, `GetWear`, `UpdateWear`, `ResetTrip`, `ServiceVehicle`, `FlushWearBatch`.
   - In `server/impound.lua`: `LoadImpoundLots`, `ImpoundVehicle`, `GetImpoundedVehicles`, `ReleaseImpoundedVehicle` (with double-entry treasury transfer to `gov:city:master`).
   - In `server/registration.lua`: `GetVehicleRegistration`, `RenewVehicleRegistration` (with double-entry treasury transfer).
   - In `client/wear.lua`: Real-time sampling loop, degradation loops, `/odometer`, `/vehstatus`, `/resettrip`.
   - In `client/impound.lua`: `/myimpounds`, `/releasevehicle`, `/vehiclereg`, `/renewreg`.

2. **Master SPA UI (`nyx_ui`)**:
   - CEF single-page application at `nyx_ui/web/index.html`.
   - Transport envelope `Nyx.UI.Send(app, action, payload)`.
   - Client bridge in `nyx_ui/client/bridge.lua` with strict parameter sanitization and safe NUI callback wrappers.
   - Design standards: CEF render budget strictly enforced (no heavy drop shadows, zero `backdrop-filter`, zero `blur()`, high-opacity dark surfaces `rgba(12, 16, 24, 0.96)`, WCAG AA+ contrast, touch targets >= 40px).

3. **Treasury Integration (`nyx_treasury`)**:
   - Closed-loop double-entry accounting: Player bank `char:<citizenId>:bank` -> City Master `gov:city:master`.
   - Surcharge rules: `solvent` (+0%), `fiscal_stress` (+15%), `degraded` (+35%), `bankrupt` (+60%).

## Implementation Discoveries & Key Invariants
- **Composite Mechanical Roadworthiness**:
  - Overall vehicle health calculated via $(0.25 \times \text{oil}) + (0.25 \times \text{pads}) + (0.20 \times \text{trans}) + (0.15 \times \text{susp}) + (0.15 \times \text{eng})$.
  - Vehicle is declared unroadworthy (`isRoadworthy = false`) if composite score $< 25.0$ or if critical component wear (oil or brake pads) $\le 10.0\%$.
- **OBD-II DTC Mapping**:
  - DTCs `P0524`, `P0198` map to oil quality/pressure failure.
  - DTCs `C0035`, `C0040` map to brake pad sensor wear.
  - DTCs `P0730`, `P0700` map to transmission wear.
  - DTCs `C1100`, `C1105` map to suspension damage.
  - DTCs `P0300`, `P0217` map to engine misfire / thermal degradation.
- **CEF 60 FPS Single-Frame Render Budget**:
  - Avoided all GPU shaders, `backdrop-filter`, and `blur()` in `#vehicle-terminal-overlay`.
  - Used high-opacity dark surfaces (`rgba(12, 16, 24, 0.96)`) with `1px solid rgba(245, 158, 11, 0.25)` borders and amber accent tokens (`#F59E0B`).
  - Strict button intent locking with `isPending` state flags prevents double-submit exploits during asynchronous NUI callback flight.
- **In-Engine Test Harness Invariant (Test 34)**:
  - Added Test 34 `Nyx.Tests.TestVehicleDiagnosticsAndCivicImpoundUI()` in `FiveM/nyx_core/server/tests.lua` validating grade taxonomy, DTC generation, estimate calculations, payload validation, fiscal crisis surcharge math, and wear badge taxonomy. Total repository tests pass at 300/300.
