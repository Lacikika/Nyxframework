# Task Plan: Automated Jury Pool Dispatcher with Fisher-Yates Shuffle & Courtroom Bucket Routing (`nyx_judiciary`)

## Goal
Implement a fully autonomous, unbiased civic jury pool selection engine using the Fisher-Yates shuffle algorithm, automated summons dispatch with no-show replacement, and OneSync Virtual Routing Bucket isolation for active trials and deliberation chambers in `nyx_judiciary`.

## Architecture & Requirements
1. **Pure Lua 5.4 Shared Engine (`nyx_judiciary/shared/jury.lua`)**:
   - `Nyx.Jury.FisherYatesShuffle(list, rng)`: Mathematically unbiased $O(N)$ permutation generator.
   - `Nyx.Jury.FilterCandidates(candidates, criteria)`: Disqualifies exempt jobs, active warrants, case participants, incarcerated citizens, and recent jury service fatigue cooldowns.
   - `Nyx.Jury.CalculateDispatchPlan(eligiblePool, requiredCount, minQuorum, existingSeatedCount)`: Quorum checking, vacancy calculation, and selection.
   - `Nyx.Jury.AssignSeats(seatedJurors, totalSeats)`: Dynamic seat allocation for jury box seats 1..6 without collisions.
   - `Nyx.Jury.TabulateVotes(ballots, ruleType, minVotes)`: Deterministic vote tabulation (majority, unanimous, supermajority, hung jury).
2. **Database Migration (`023_judiciary_jury_dispatcher_and_courtroom_routing.sql` & `index.json`)**:
   - Enhance `nyx_judiciary_dockets` with `routing_bucket`, `deliberation_bucket`, `deliberation_started_at`, and new status values (`in_trial`, `mistrial`).
   - Enhance `nyx_judiciary_juries` with `seat_index`, `summons_expires_at`, `stipend_paid`, `deliberation_entered_at`, and status values (`deliberating`, `dismissed`).
   - Create `nyx_judiciary_jury_service_logs` for historical service tracking and cooldown enforcement.
   - Mirror migration in `FiveM/nyx_core/sql/migrations/` and `FiveM/nyx_judiciary/sql/migrations/`, register in `index.json`.
3. **Server Jury Dispatcher & Courtroom Routing Bucket Engine (`nyx_judiciary/server/jury.lua`, `courtroom.lua`, `dockets.lua`, `execution.lua`, `main.lua`, `exports.lua`)**:
   - Automated jury dispatcher: `SummonJury`, `SeatJuror`, `ExcuseJuror`, `AutoReplaceNoShows`.
   - Routing bucket manager: `AllocateCourtroomBucket`, `StartTrial` (routes participants to courtroom bucket), `StartDeliberation` (isolates jurors in deliberation chamber bucket), `DeliverVerdict`, and `ConcludeTrial` (restores bucket 0 and pays stipend via `nyx_treasury`).
   - RPC routes and server exports.
4. **Client Third-Eye Courtroom & Deliberation Integration (`nyx_judiciary/client/courtroom.lua`, `main.lua`)**:
   - Third-Eye (`LALT`) check-in on jury seats.
   - Deliberation ballot dialog / commands / controls in isolated chamber.
   - GPS waypoint routing and notifications.
5. **Testing & Verification**:
   - Python unit test suite `tests/test_jury_dispatcher_and_courtroom_routing.py` testing shuffle uniformity, candidate filtering, quorum checks, seat assignment, vote tabulation, bucket transitions, and stipend payouts.
   - Lua in-engine test suite `Nyx.Tests.TestJuryDispatcherAndCourtroomRouting()` in `FiveM/nyx_core/server/tests.lua` added to `RunAll()`.
   - Complete verification run with `python scripts/validator.py`, `powershell -File scripts/verify.ps1`, and `pytest`.
   - Update `AGENT_TASK.md` marking task completed.

## Phase Plan
- [x] Phase 1: Test-Driven Design — Create failing Python test suite (`tests/test_jury_dispatcher_and_courtroom_routing.py`)
- [x] Phase 2: Database Migration — Create `023_judiciary_jury_dispatcher_and_courtroom_routing.sql` & update `index.json`
- [x] Phase 3: Pure Lua 5.4 Shared Engine — Implement `FiveM/nyx_judiciary/shared/jury.lua` & update `fxmanifest.lua`
- [x] Phase 4: Server Dispatcher & Courtroom Routing — Implement server jury dispatching, bucket routing, trial lifecycle, and RPCs
- [x] Phase 5: Client Courtroom & Deliberation UI — Enhance seating, third-eye targets, and deliberation voting
- [x] Phase 6: In-Engine Lua Test Suite — Implement `Nyx.Tests.TestJuryDispatcherAndCourtroomRouting` in `tests.lua`
- [x] Phase 7: Full Verification & Agent Task Completion — Run validator, verify.ps1, pytest, and update `AGENT_TASK.md`
