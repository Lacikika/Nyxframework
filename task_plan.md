# Task Plan: Pre-Trial Judicial Bail Bonds, Surety Escrow & Fugitive Recovery Warrants (`nyx_judiciary`, `nyx_treasury` & `nyx_mdt`)

## Goal
Implement a complete, authoritative judicial bail bonds and pre-trial release engine. Enable the municipal judiciary and magistrate council to configure bail schedules (misdemeanor standard vs felony judicial discretion), accept cash bail and commercial surety bonds into municipal escrow (`gov:escrow:bail`), enforce release conditions, verify defendant court appearance, execute automated 95%/5% exoneration distributions upon trial conclusion, forfeit 100% on failure to appear (FTA / bail jumping), and generate automated felony fugitive arrest warrants with 15% recovery bounties.

## Architecture & Requirements
1. **Database Migration (`065_judicial_bail_bonds_surety_escrow_and_fugitive_recovery.sql` & `index.json`)**:
   - Table `nyx_judiciary_bail_bonds`:
     - `bond_id` BIGINT AUTO_INCREMENT PRIMARY KEY
     - `bond_uuid` VARCHAR(36) NOT NULL UNIQUE
     - `docket_id` VARCHAR(32) NOT NULL
     - `defendant_citizen_id` VARCHAR(16) NOT NULL
     - `poster_citizen_id` VARCHAR(16) NOT NULL
     - `bond_type` ENUM('cash', 'surety', 'recognizance') NOT NULL DEFAULT 'cash'
     - `bail_amount` DECIMAL(15, 2) NOT NULL
     - `collateral_amount` DECIMAL(15, 2) NOT NULL
     - `bondsman_fee` DECIMAL(15, 2) NOT NULL DEFAULT 0.00
     - `clerk_admin_fee` DECIMAL(15, 2) NOT NULL DEFAULT 0.00
     - `status` ENUM('posted', 'exonerated', 'forfeited', 'revoked') NOT NULL DEFAULT 'posted'
     - `escrow_account_id` VARCHAR(64) NOT NULL DEFAULT 'gov:escrow:bail'
     - `treasury_tx_uuid` VARCHAR(36) NULL
     - `conditions` JSON NOT NULL
     - `court_appearance_verified` TINYINT(1) NOT NULL DEFAULT 0
     - `bounty_claimed` TINYINT(1) NOT NULL DEFAULT 0
     - `bounty_hunter_citizen_id` VARCHAR(16) NULL
     - `posted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
     - `resolved_at` TIMESTAMP NULL
     - `notes` VARCHAR(255) NULL
   - Table `nyx_judiciary_bail_audits`:
     - `audit_id` BIGINT AUTO_INCREMENT PRIMARY KEY
     - `audit_uuid` VARCHAR(36) NOT NULL UNIQUE
     - `bond_id` BIGINT NOT NULL
     - `docket_id` VARCHAR(32) NOT NULL
     - `citizen_id` VARCHAR(16) NOT NULL
     - `action` ENUM('BAIL_SCHEDULE_SET', 'BAIL_POSTED', 'CONDITIONS_UPDATED', 'APPEARANCE_CHECKED', 'BAIL_EXONERATED', 'BAIL_FORFEITED_FTA', 'FUGITIVE_WARRANT_ISSUED', 'FUGITIVE_APPREHENDED', 'BOUNTY_DISBURSED') NOT NULL
     - `amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00
     - `treasury_tx_uuid` VARCHAR(36) NULL
     - `notes` VARCHAR(255) NULL
     - `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
   - Seed municipal escrow account in `nyx_treasury_accounts`:
     - `account_id` = 'gov:escrow:bail', `label` = 'Municipal Court Judicial Bail Escrow Pool', `balance` = 0.00, `type` = 'reserve', `signatories_required` = 1.
   - Extend `nyx_judiciary_dockets`:
     - `bail_schedule_amount` DECIMAL(15, 2) NOT NULL DEFAULT 0.00
     - `bail_status` ENUM('not_set', 'eligible', 'posted', 'remand_no_bail', 'exonerated', 'forfeited') NOT NULL DEFAULT 'not_set'
     - `bail_bond_id` BIGINT NULL
   - Register Step 65 in `FiveM/nyx_core/sql/migrations/index.json` and mirror to `FiveM/nyx_judiciary/sql/migrations/`.

2. **Shared Pure Lua 5.4 Domain Engine (`FiveM/nyx_judiciary/shared/bail_bonds.lua`)**:
   - `Nyx.BailBonds.CalculateBailSchedule(caseType, priorFailuresToAppear, offenseGravityMultiplier)`
   - `Nyx.BailBonds.EvaluateBailEligibility(docket, defendantRecord)`
   - `Nyx.BailBonds.CalculateBailPaymentBreakdown(bailAmount, bondType)`
   - `Nyx.BailBonds.EvaluateCourtAppearance(bond, defendantCitizenId, checkinCoords, courtroomCoords, maxDist)`
   - `Nyx.BailBonds.CalculateForfeitureAndBounty(bond)`
   - `Nyx.BailBonds.ValidateReleaseConditions(conditionsList, playerInventoryItems, playerCoords, currentHour)`
   - `Nyx.BailBonds.FormatBailBadge(status, bondType)`

3. **Authoritative Server Subsystems & RPCs (`FiveM/nyx_judiciary/server/bail.lua`)**:
   - In-memory hydration `Nyx.Judiciary.ActiveBailBonds`.
   - `SetBailSchedule(docketId, judgeCitizenId, bailAmount, conditions)`
   - `PostBail(source, docketId, bondType, guarantorCitizenId)` with double-entry treasury transfer
   - `VerifyCourtAppearance(source, docketId)`
   - `ExonerateBail(docketId, reason)` with 95% refund and 5% clerk fee
   - `ForfeitBail(docketId, reason)` with 100% seizure and automatic FTA felony bench warrant
   - `ClaimFugitiveBounty(source, bondId, fugitiveCitizenId)` with 15% bounty disbursement
   - RPC routes & public exports in `server/exports.lua`
   - Verdict execution hook in `server/execution.lua`

4. **Client Subsystems & Spatial Interaction (`FiveM/nyx_judiciary/client/bail.lua`)**:
   - Courtroom & Jail Bail Kiosk interaction targets (`nyx_interact`).
   - Player commands `/bailstatus`, `/checkinbail`, `/postbail`.
   - Client exports in `client/exports.lua`.

5. **In-Engine Integration Test (`FiveM/nyx_core/server/tests.lua`)**:
   - Test 60: `Nyx.Tests.TestJudicialBailBondsSuretyEscrowAndFugitiveRecovery()`
   - Validates bail schedule math, eligibility, cash & surety payment breakdown, court appearance verification, exoneration splits, forfeiture with fugitive warrant bounty, and presentation badge formatting.
   - Wire into `Nyx.Tests.RunAll()`.

6. **Dedicated Pytest Suite (`tests/test_judicial_bail_bonds_surety_escrow_and_fugitive_recovery.py`)**:
   - Unit tests for pure math, migration file syntax and schema definitions, registration, and integration checks.

## Phase Plan
- [ ] Phase 1: Test-Driven Design — Create pytest test suite (`tests/test_judicial_bail_bonds_surety_escrow_and_fugitive_recovery.py`)
- [ ] Phase 2: Database Migration — Create `065_judicial_bail_bonds_surety_escrow_and_fugitive_recovery.sql`, register in `index.json`, mirror to `nyx_judiciary`
- [ ] Phase 3: Shared Pure Lua 5.4 Bail Bonds Engine — Implement `FiveM/nyx_judiciary/shared/bail_bonds.lua`, update `fxmanifest.lua`
- [ ] Phase 4: Authoritative Server Subsystems & RPCs — Implement `FiveM/nyx_judiciary/server/bail.lua`, update `server/exports.lua` and `server/execution.lua`
- [ ] Phase 5: Client Subsystems & Spatial Interaction — Implement `FiveM/nyx_judiciary/client/bail.lua`, update `client/exports.lua`
- [ ] Phase 6: In-Engine Integration Test — Implement Test 60 in `FiveM/nyx_core/server/tests.lua` & wire into `RunAll()`
- [ ] Phase 7: Full Verification & Completion — Run pytest, validator.py, update `AGENT_TASK.md`
