# Task Plan: Auditable Public Treasury Ledger & Department Allocation Monitor (`nyx_treasury` & `nyx_ui`)

## Goal
Implement a comprehensive, auditable real-time public treasury ledger and department allocation monitor in `nyx_treasury` and `nyx_ui`. The system delivers an open municipal balance sheet, categorized transaction logs with pagination and search, automated percentage splits across statutory pillars (Emergency Services, Infrastructure, Social Dividend), and real-time fiscal crisis threshold telemetry with logarithmic wage scaling and drain velocity analytics.

## Architecture & Requirements
1. **Database Migration (`057_auditable_public_treasury_ledger_and_department_monitor.sql` & `index.json`)**:
   - Extend `nyx_treasury_accounts` with `gov:dept:dividend` (Social Dividend & Civic Grants Reserve).
   - Extend `nyx_treasury_allocations` with `department_label`, `allocation_category` (ENUM: `'emergency_services'`, `'infrastructure'`, `'social_dividend'`, `'general'`), `last_allocated_amount`, and `last_allocated_at`.
   - Seed statutory allocation splits matching `Tervek.md` section 1:
     - Emergency Services: Police (35%), EMS (25%) -> 60%
     - Public Works / Infrastructure: Works (25%)
     - Social Dividend & Small Grants: Dividend (15%)
   - Create `nyx_treasury_revenue_sweeps` immutable audit ledger (`sweep_id` PK, `sweep_uuid` UNIQUE, `tax_pool_balance_before`, `total_swept`, `master_surplus_retained`, `allocations_count`, `allocations_json`, `fiscal_state`, `executed_by`, `created_at`).
   - Register in `FiveM/nyx_core/sql/migrations/index.json` (Step 57) and mirror in `FiveM/nyx_treasury/sql/migrations/`.

2. **Shared Pure Lua 5.4 Domain Engine (`FiveM/nyx_treasury/shared/public_ledger.lua`)**:
   - `Nyx.PublicLedger.AllocationCategories`: Whitelist & metadata for statutory categories (`emergency_services`, `infrastructure`, `social_dividend`, `general`).
   - `Nyx.PublicLedger.TransactionCategories`: Human-readable labels, badges, and flow types (inflow, outflow, internal) for all 11+ treasury categories.
   - `Nyx.PublicLedger.CalculateBalanceSheet(accounts, targetReserve, criticalReserve)`: Pure calculator for municipal balance sheet, total public liquidity, departmental distribution shares, solvency ratings, and double-entry conservation verification.
   - `Nyx.PublicLedger.CalculateSweepSplits(collectedAmount, allocations, accounts)`: Exact zero-cent closed-loop revenue sweep calculator respecting department caps and routing overflow surplus to master reserve.
   - `Nyx.PublicLedger.CalculateFiscalTelemetry(masterReserve, circuitTelemetry, degradationState)`: Computes reserve ratios, fiscal state badge, wage multiplier, burn rate, runway hours, and infrastructure degradation statuses.
   - `Nyx.PublicLedger.SanitizeLedgerQuery(params)`: Zero-trust input sanitization for pagination, category filters, and search terms.
   - `Nyx.PublicLedger.FormatLedgerReport(balanceSheet, telemetry, allocations)`: Text/ASCII formatted public finance audit report for terminal printing.
   - Declare in `FiveM/nyx_treasury/fxmanifest.lua` and `@nyx_treasury/shared/public_ledger.lua` in `FiveM/nyx_ui/fxmanifest.lua`.

3. **Authoritative Server Subsystems & RPCs (`FiveM/nyx_treasury/server/`)**:
   - `server/taxes.lua`: Update `Nyx.Treasury.SweepTaxes` to use the pure split calculator, record immutable sweep records into `nyx_treasury_revenue_sweeps`, update `last_allocated_amount`/`last_allocated_at` in `nyx_treasury_allocations`, and trigger `nyx:treasury:client:sweepExecuted` broadcasts.
   - `server/main.lua`: Register new/enhanced RPC routes:
     - `treasury:getPublicOverview`: Comprehensive overview (balance sheet, accounts, fiscal crisis telemetry, allocations, active tax rates).
     - `treasury:getBalanceSheet`: Structured balance sheet with breakdown of assets, reserves, and conservation proof.
     - `treasury:getLedgerPage`: Paginated, categorized transaction logs with search filter and total entry counts.
     - `treasury:getAllocations`: Department allocation schedules grouped by statutory pillar with progress towards caps.
     - `treasury:getRevenueSweeps`: Immutable history of automated percentage sweeps.
     - `treasury:getFiscalCrisisTelemetry`: Real-time telemetry on wage scaling, drain velocity, runway, and degradation.
   - `server/exports.lua`: Export public server APIs: `GetBalanceSheet`, `GetPublicOverview`, `ExecuteRevenueSweep`, `GetRevenueSweeps`.

4. **Client-Side Subsystems & NUI Bridge (`FiveM/nyx_treasury/client/` & `FiveM/nyx_ui/client/`)**:
   - `nyx_treasury/client/main.lua`: Update `OpenTerminal` and `CloseTerminal` to use standardized `TREASURY_DASHBOARD_OPEN` envelope and pass full overview data. Register commands `/treasury` and `/cityledger`.
   - `nyx_treasury/client/terminals.lua`: Spatial interaction terminals in world.
   - `nyx_treasury/client/exports.lua`: Public client exports: `OpenTreasuryDashboard`, `CloseTreasuryDashboard`.
   - `nyx_ui/client/bridge.lua`: Whitelist treasury parameters, register NUI callbacks (`treasury:getLedgerPage`, `treasury:getAllocations`, `treasury:getRevenueSweeps`, `treasury:getBalanceSheet`, `closeTreasury`).
   - `nyx_ui/client/exports.lua`: Export `OpenTreasuryDashboard` and `CloseTreasuryDashboard`.

5. **Web Master Single-Page Application (`FiveM/nyx_ui/web/`)**:
   - `index.html`: Redesign `treasury-overlay` with modern tabs:
     - Tab 1: **Mérleg & Likviditás (Balance Sheet & Liquidity)** - Municipal asset cards, accounts table, solvency badges, net double-entry conservation verification.
     - Tab 2: **Főkönyvi Napló (Audited Transaction Ledger)** - Live filterable transaction table by category, search bar, pagination (Page X of Y, Prev/Next), and live ticker.
     - Tab 3: **Költségvetési Elosztás (Department Allocation Monitor)** - The 3 statutory pillars (Emergency Services, Infrastructure, Social Dividend) with percentage splits, cap gauges, and sweep history.
     - Tab 4: **Fiskális Krízis Telemetria (Fiscal Crisis Telemetry)** - Reserve status gauge, logarithmic wage scale breakdown, drain velocity / burn rate meter, runway hours, and public infrastructure degradation status.
   - `css/app.css`: Styling for treasury tabs, allocation progress bars, fiscal crisis status banners, and ledger filters.
   - `js/app.js`: Implement `openTreasuryDashboard`, tab switching, filter handlers, pagination handlers, live ticker updates (`TREASURY_TICKER_UPDATE`, `TREASURY_SWEEP_UPDATE`), and browser dev mock data.

6. **In-Engine Integration Test (`FiveM/nyx_core/server/tests.lua`)**:
   - Test 52: `Nyx.Tests.TestAuditablePublicTreasuryLedgerAndDepartmentMonitor()`
   - Validates balance sheet computation, exact cent sweep splits, department cap enforcement, fiscal crisis telemetry, search/pagination sanitization, and double-entry conservation.
   - Wire into `Nyx.Tests.RunAll()`.

7. **Verification & Completion**:
   - Dedicated pytest test suite: `tests/test_auditable_public_treasury_ledger_and_department_monitor.py`.
   - Run full pytest suite (all 477+ tests passing).
   - Run `python scripts/validator.py` and `powershell -File scripts/verify.ps1`.
   - Update `AGENT_TASK.md` marking task completed.

## Phase Plan
- [x] Phase 1: Test-Driven Design — Create pytest test suite (`tests/test_auditable_public_treasury_ledger_and_department_monitor.py`)
- [x] Phase 2: Database Migration — Create `057_auditable_public_treasury_ledger_and_department_monitor.sql`, register in `index.json`, mirror to `nyx_treasury`
- [x] Phase 3: Shared Pure Lua 5.4 Public Ledger Engine — Implement `FiveM/nyx_treasury/shared/public_ledger.lua`, update `fxmanifest.lua` in `nyx_treasury` & `nyx_ui`
- [x] Phase 4: Authoritative Server Subsystems & RPCs — Update `FiveM/nyx_treasury/server/taxes.lua`, `server/main.lua`, `server/exports.lua`
- [x] Phase 5: Client-Side Subsystems & NUI Bridge — Update `FiveM/nyx_treasury/client/main.lua`, `client/exports.lua`, `FiveM/nyx_ui/client/bridge.lua`, `client/exports.lua`
- [x] Phase 6: Web Master SPA UI Integration — Update `FiveM/nyx_ui/web/index.html`, `web/css/app.css`, `web/js/app.js`
- [x] Phase 7: In-Engine Integration Test — Implement Test 52 in `FiveM/nyx_core/server/tests.lua` & wire into `RunAll()`
- [x] Phase 8: Full Verification & Completion — Run pytest, validator.py, verify.ps1, update `AGENT_TASK.md`
