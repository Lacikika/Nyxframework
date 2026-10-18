# Autonomous Development Contract

## Goal
Build, refine, and optimize resources for the FiveM server project (Nyxframework). Run continuously until manually stopped, token limit reached, or backlog exhausted.

## Boundaries
- **Modifiable scope:** `FiveM/` resource packages (`FiveM/nyx_*` and newly created custom resources under `FiveM/`).
- **Strictly protected:** `FiveM/server.cfg`, `.env`, database root credentials, `scripts/verify.*`, `scripts/overnight_loop.*`.
- **Architecture Rules:**
  - Target Engine: FiveM (Cerulean), Lua 5.4, OneSync Infinity, oxmysql.
  - Manifest Rule: Ensure all client/server files are declared in `fxmanifest.lua`.
  - Code Quality: Write self-contained, clean Lua 5.4 code with defensive error handling (pcall / guard clauses).
  - Database Rule: If adding or modifying database schemas, create incremental migration files in `FiveM/nyx_core/sql/migrations/` and register them in `index.json`.
  - RPC Bus Integrity: Preserve the zero-trust RPC bus contracts (`nyx_core/shared/rpc.lua`).
  - Web UI: If touching `nyx_ui/web`, preserve single-frame CEF SPA integration.

## Pipeline Order
1. Check **Task Backlog** below. Pick the highest uncompleted item (`- [ ]`).
2. If Backlog is empty: analyze existing resources, find code duplication, missing error checks, or pick and plan a new logical feature from `Tervek.md` (e.g., municipal elections, elastic pricing, power grid substations). Add it to the Backlog.
3. Implement the feature completely:
   - Write clean server/client Lua code.
   - Declare all new files in `fxmanifest.lua`.
   - Add database migrations if new tables or columns are required.
4. Run validation (`powershell -File scripts/verify.ps1` or `python scripts/validator.py`). Fix any errors before concluding the iteration.
5. Update `AGENT_TASK.md` marking the task completed (`- [x]`) and log a brief summary of what was implemented under `Completed Tasks Log`.

## Task Backlog
- [ ] Feature: Advanced vehicle mileage & wear tracking system (server-side persistence in `nyx_vehicles`)
- [ ] Feature: Dynamic inventory weight penalties on player movement (`nyx_inventory` -> `nyx_core`)
- [ ] Feature: Elastic item pricing based on localized stock-to-demand ratio (`nyx_logistics` / `nyx_treasury`)
- [ ] Feature: Cryptographic evidence chain-of-custody registry with SHA-256 fingerprints (`nyx_judiciary`)
- [ ] Refactor: Extract shared math/vector helper functions into a standalone utility (`nyx_core/shared/math.lua`)
- [ ] Feature: Multi-signature corporate treasury vaults and sign-off rules (`nyx_factions`)
- [ ] Feature: Municipal power grid substation failure & blackout simulation (`nyx_services`)

## Completed Tasks Log
<!-- Completed iterations will be appended here with timestamp and summary -->
