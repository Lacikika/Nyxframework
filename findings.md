# Findings: Trade Unionization Framework, Collective Bargaining & Binding Labor Arbitration

## Context & Existing Implementations
1. **Factions (`nyx_factions`)**:
   - `007_factions_organizations.sql` created `nyx_factions_registry` and `nyx_factions_members`.
   - `016_factions_vaults_and_signoff_rules.sql` created corporate multi-sig vaults and tiered sign-off rules.
   - Factions currently handle corporations/enterprises, but workers have no collective organization or wage negotiation power.
2. **Treasury (`nyx_treasury`)**:
   - Closed-loop double-entry accounting with accounts `faction:<faction_id>` and `citizen:<citizen_id>`.
   - Payroll runs disburse funds from employer accounts to employee bank accounts.
   - Dues checkoff can deduct directly during payroll or recurring dues cycles into `union:<union_id>`.
   - Restitution awards can atomically transfer damages from enterprise treasury to union members and union strike funds.
3. **Logistics & Assembly (`nyx_logistics`)**:
   - Facilities produce batches of items (`nyx_logistics/server/facilities.lua`).
   - Facilities can be interlocked during active strikes (`ENTERPRISE_FACILITY_PICKET_LOCKED`).
4. **Judiciary (`nyx_judiciary`)**:
   - Handles case dockets (`nyx_judiciary_dockets`).
   - Labor arbitrations can bind enterprise and union parties under legally enforceable rulings.
