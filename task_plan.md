# Task Plan: Anatomical Trauma & Organ-Specific Medical Injury Engine (`nyx_services`)

## Goal
Implement a comprehensive limb-specific anatomical trauma and medical injury engine in `nyx_services`. The system tracks localized trauma across 6 anatomical regions (`head`, `torso`, `left_arm`, `right_arm`, `left_leg`, `right_leg`) with distinct wound types (arterial bleeding, fractures, ballistic trauma, lacerations, burns, blunt impact). It simulates dynamic blood volume depletion (5000 mL normal, multi-tier hypovolemic shock), pain levels, and physical debuffs (limping, aim sway, fainting spells). Field stabilization requires physical medical items (`bandage_sterile`, `first_aid_pack`, `tourniquet`, `splint`), with full database persistence, zero-trust RPC validation, client damage detection and debuff loops, and in-engine integration tests.

## Architecture & Requirements
1. **Database Migration (`041_anatomical_trauma_and_medical_injury_engine.sql` & `index.json`)**:
   - `nyx_medical_trauma`: Persistent player trauma state (`citizen_id` PK, `blood_volume_ml`, `bleeding_rate`, `pain_level`, `wounds_json`, `is_unconscious`, `last_updated_at`).
   - `nyx_medical_treatments_log`: Immutable field treatment audit log (`log_id` PK, `treatment_uuid`, `patient_citizen_id`, `medic_citizen_id`, `item_used`, `target_limb`, `treatment_type`, `blood_volume_before`, `blood_volume_after`, `treated_at`).
   - Register in `FiveM/nyx_core/sql/migrations/index.json` (Step 41) and mirror in `FiveM/nyx_services/sql/migrations/`.

2. **Declarative Items Registration (`nyx_inventory/shared/items.lua`)**:
   - Register physical medical consumable items:
     - `bandage_sterile`: Sterile pressure bandage for lacerations, minor wounds, and bleeding control.
     - `first_aid_pack`: Advanced trauma kit for fractures, ballistic trauma stabilization, and deep wound dressing.
     - `tourniquet`: Extremity arterial bleed clamp (`left_arm`, `right_arm`, `left_leg`, `right_leg`).
     - `splint`: Structural stabilization for fractured limbs.
     - `morphine_ampoule`: Fast-acting analgesic reducing pain level and stabilizing shock symptoms.
   - Maintain backward compatibility with existing items (`med_bandage`, `med_firstaid`, `med_plasma`, `med_surgical_pack`).

3. **Pure Lua 5.4 Shared Engine (`nyx_services/shared/trauma.lua`)**:
   - `Nyx.Trauma.ValidLimbs`: Whitelist of anatomical regions (`head`, `torso`, `left_arm`, `right_arm`, `left_leg`, `right_leg`).
   - `Nyx.Trauma.WoundTypes`: Whitelist of wound classifications (`laceration`, `ballistic`, `arterial_bleed`, `fracture`, `blunt`, `burn`).
   - `Nyx.Trauma.BoneToLimb`: Deterministic mapping from GTA ped bone IDs to anatomical limbs.
   - `Nyx.Trauma.CreateInitialTraumaState()`: Generates initial trauma state table (5000 mL blood, 0 pain, full limb health, no bleeding/fractures).
   - `Nyx.Trauma.CalculateBleedRate(state)`: Calculates blood loss rate in mL/second based on active wounds, arterial bleeds, and applied tourniquets.
   - `Nyx.Trauma.CalculateShockClass(bloodVolume)`: Determines hypovolemic shock class (Class I, II, III, IV) with physiological symptoms.
   - `Nyx.Trauma.SimulateBloodTick(state, deltaSeconds)`: Pure function updating blood volume, applying bleed rate, and evaluating shock/unconsciousness.
   - `Nyx.Trauma.AddWound(state, limb, woundType, severity)`: Applies localized wound, updates limb condition, and recalculates bleeding rate.
   - `Nyx.Trauma.CanTreatLimb(state, limb, item)`: Zero-trust validation for medical item applicability on specific limbs.
   - `Nyx.Trauma.ApplyTreatment(state, limb, item)`: Applies field stabilization effect, fixes fractures, arrests bleeding, reduces pain, and heals limb.
   - `Nyx.Trauma.FormatTraumaDiagnosis(state)`: Generates detailed medical diagnostic summary for EMS and triage examination.
   - Register in `FiveM/nyx_services/fxmanifest.lua`.

4. **Server-Side Subsystem & RPCs (`nyx_services/server/trauma.lua`, `server/exports.lua`)**:
   - In-memory trauma state management for active players with periodic debounced database sync.
   - Character load hydration and disconnect persistence.
   - RPC routes:
     - `services:getTraumaState`: Fetches own trauma telemetry or nearby patient's trauma telemetry.
     - `services:applyMedicalItem`: Validates inventory item possession, verifies distance, applies treatment, deducts item from inventory, and logs to `nyx_medical_treatments_log`.
     - `services:diagnosePatient`: Medical examination of nearby player.
     - `services:syncTraumaDamage`: Ingests client damage reports with server validation.
     - `services:revivePlayer`: Integrated with `ProcessRevival` to reset trauma state.
   - Server exports in `server/exports.lua`:
     - `GetPlayerTraumaState`, `AddLimbDamage`, `ApplyMedicalTreatment`, `SetPlayerBloodVolume`, `DiagnosePlayerTrauma`, `ResetTraumaState`.

5. **Client-Side Damage Listener & Debuff Loop (`nyx_services/client/trauma.lua`, `client/exports.lua`)**:
   - Event listener: captures `CEventNetworkEntityDamage` or bone damage events, determines hit bone via `GetPedLastDamageBone`, maps to anatomical limb, and dispatches to server.
   - Debuff execution loop:
     - Leg injury/fracture: triggers limp animation set (`move_m@injured`).
     - Arm injury/fracture: triggers weapon sway and handling degradation.
     - Arterial bleed / severe blood loss: screen pulsation, vignette flash, and stumbling.
     - Class IV hypovolemic shock (< 3000 mL): blackouts and ragdoll collapse.
   - Commands:
     - `/diagnose [targetId]` to perform a trauma triage check.
     - `/treat [targetId] [limb] [item]` for field stabilization.
   - Client exports:
     - `GetLocalTraumaState`, `GetLimbHealth`, `IsBleeding`, `GetShockClass`.
   - Register in `FiveM/nyx_services/fxmanifest.lua`.

6. **In-Engine Integration Test (`FiveM/nyx_core/server/tests.lua`)**:
   - Test 36: `Nyx.Tests.TestAnatomicalTraumaAndInjuryEngine()`
   - Validates bone-to-limb mapping, initial state generation, wound application, bleed rate calculations, shock classification, item treatment effects, and zero-trust validation rules.
   - Wire into `Nyx.Tests.RunAll()`.

7. **Verification & Completion**:
   - Dedicated Python test suite `tests/test_anatomical_trauma_and_injury_engine.py` (all tests passing).
   - Full pytest regression suite.
   - `python scripts/validator.py` and `powershell -File scripts/verify.ps1`.
   - Update `AGENT_TASK.md` marking task completed.

## Phase Plan
- [x] Phase 1: Test-Driven Design — Create pytest test suite (`tests/test_anatomical_trauma_and_injury_engine.py`)
- [x] Phase 2: Database Migration — Create `041_anatomical_trauma_and_medical_injury_engine.sql`, register in `index.json`, mirror to `nyx_services`
- [x] Phase 3: Declarative Items — Register medical items in `FiveM/nyx_inventory/shared/items.lua`
- [x] Phase 4: Shared Pure Lua 5.4 Trauma Engine — Implement `FiveM/nyx_services/shared/trauma.lua` & update `fxmanifest.lua`
- [x] Phase 5: Server-Side Trauma Subsystem & RPCs — Implement `FiveM/nyx_services/server/trauma.lua`, update `server/main.lua`, `server/exports.lua`
- [x] Phase 6: Client-Side Trauma & Debuff Subsystem — Implement `FiveM/nyx_services/client/trauma.lua`, update `client/exports.lua`, `client/main.lua`
- [x] Phase 7: In-Engine Integration Test — Implement Test 36 in `FiveM/nyx_core/server/tests.lua` & wire into `RunAll()`
- [x] Phase 8: Full Verification & Completion — Run pytest, validator, verify.ps1, update `AGENT_TASK.md`
