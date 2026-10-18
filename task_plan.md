# Task Plan: Trade Unionization Framework, Collective Bargaining Agreements & Binding Labor Arbitration (`nyx_factions` / `nyx_treasury` / `nyx_judiciary`)

## Goal
Implement a comprehensive, autonomous Trade Unionization Framework and Collective Bargaining system for Nyxframework. Workers can organize trade unions across industry sectors, collect automated dues check-offs, ratify Collective Bargaining Agreements (CBAs) with enterprise wage floors, authorize strikes with facility picket lockouts and strike fund relief payouts, and resolve labor disputes through binding judicial arbitrations with double-entry restitution transfers.

## Architecture & Requirements
1. **Database Migration (`028_factions_trade_unions_and_collective_bargaining.sql` & `index.json`)**:
   - `nyx_factions_unions`: Union ID, legal name, industry sector, treasury account ID, founder, dues amount/rate/mode, strike fund balance, strike pay rate, status.
   - `nyx_factions_union_members`: Member ID, union ID, citizen ID, employer enterprise faction ID, role (steward/delegate/member), standing, unpaid dues, last dues paid, last strike pay claimed.
   - `nyx_factions_cba`: CBA UUID, union ID, enterprise faction ID, title, wage floor, overtime multiplier, hazard bonus, strike grace period, status (draft/proposed/ratified/breached/expired/arbitration).
   - `nyx_factions_strikes`: Strike UUID, union ID, enterprise faction ID, CBA ID, reason, vote ratio, status (voting/active/settled/broken/arbitration).
   - `nyx_factions_strike_votes`: Ballots per member with yes/no/abstain votes.
   - `nyx_factions_arbitration_awards`: Award UUID, strike ID, CBA ID, docket ID, arbitrator citizen ID, restitution damages, statutory penalty, revised wage floor, settlement status, tx UUID.
   - Mirror in `FiveM/nyx_core/sql/migrations/` and `FiveM/nyx_factions/sql/migrations/`, register in `index.json`.

2. **Pure Lua 5.4 Shared Engine (`nyx_factions/shared/unions.lua`)**:
   - `Nyx.Unions.CalculateDuesCheckoff(grossWage, duesMode, duesAmount, duesRate)`: Integer-cent dues calculation and wage deduction.
   - `Nyx.Unions.CalculateStrikeFundRunway(strikeFundBalance, memberCount, strikePayRate)`: Daily burn velocity, days of runway, and solvency state.
   - `Nyx.Unions.EvaluateWageCompliance(actualWage, wageFloor)`: CBA wage compliance, deficit calculation.
   - `Nyx.Unions.EvaluateStrikeVote(votes, quorumThreshold, majorityThreshold)`: Participation quorum and majority threshold validation.
   - `Nyx.Unions.CalculateArbitrationAward(underpaidHours, hourlyDeficit, penaltyRate, affectedMemberCount)`: Restitution damages, statutory penalty, and total award breakdown.
   - `Nyx.Unions.CanClaimStrikePay(lastClaimTimestamp, currentTimestamp, cooldownSeconds)`: Cooldown validator for strike relief disbursements.

3. **Server Union, CBA & Arbitration Engine (`nyx_factions/server/unions.lua`, `cba.lua`, `main.lua`, `exports.lua`)**:
   - Union registry: `RegisterUnion`, `JoinUnion`, `LeaveUnion`, `GetUnion`, `GetMemberStanding`.
   - CBA lifecycle: `ProposeCBA`, `RatifyCBA`, `EvaluateEnterpriseCompliance`.
   - Strike state machine: `CallStrikeVote`, `CastStrikeVote`, `DeclareStrike`, `ClaimStrikeRelief`, `EndStrike`.
   - Binding arbitration: `PetitionLaborArbitration`, `ExecuteArbitrationAward` with atomic double-entry treasury restitution transfers.
   - OneSync state bag sync: `GlobalState.activeStrikes`.
   - Interlocks: Facility manufacturing picket locks (`nyx_logistics`) and commercial fleet locks (`nyx_factions`).

4. **Client & Third-Eye (`LALT`) Integration (`nyx_factions/client/unions.lua`, `fxmanifest.lua`)**:
   - Third-Eye targets on civic union terminals and enterprise facility picket lines.
   - `/unionstatus` command showing union membership, standing, strike runway, and CBA status.
   - Sync manifest declarations across client, server, and shared scopes.

5. **Testing & Verification**:
   - Python unit test suite `tests/test_trade_unions_and_collective_bargaining.py`.
   - Lua in-engine test suite `Nyx.Tests.TestTradeUnionsAndCollectiveBargaining()` in `FiveM/nyx_core/server/tests.lua` (Test 22 in `RunAll()`).
   - Run `python scripts/validator.py`, `powershell -File scripts/verify.ps1`, and `pytest`.
   - Update `AGENT_TASK.md` marking task completed.

## Phase Plan
- [x] Phase 1: Test-Driven Design — Create failing Python test suite (`tests/test_trade_unions_and_collective_bargaining.py`)
- [x] Phase 2: Database Migration — Create `028_factions_trade_unions_and_collective_bargaining.sql` & update `index.json`
- [x] Phase 3: Pure Lua 5.4 Shared Engine — Implement `FiveM/nyx_factions/shared/unions.lua` & update `fxmanifest.lua`
- [x] Phase 4: Server Union, CBA & Arbitration Subsystem — Implement `server/unions.lua`, `server/cba.lua`, exports, and interlocks
- [x] Phase 5: Client Third-Eye & Status UI — Implement `client/unions.lua` and command hooks
- [x] Phase 6: In-Engine Lua Test Suite — Implement `Nyx.Tests.TestTradeUnionsAndCollectiveBargaining` in `tests.lua`
- [x] Phase 7: Full Verification & Agent Task Completion — Run validator, verify.ps1, pytest, and update `AGENT_TASK.md`
