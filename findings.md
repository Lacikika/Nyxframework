# Findings: Auditable Public Treasury Ledger & Department Allocation Monitor (`nyx_treasury` & `nyx_ui`)

## Context & Architecture
1. **Decentralized Public Finance & Open Municipal Balance Sheets**:
   - Accounts Architecture:
     - `gov:city:master` (`public_master`): Central municipal reserve backing the currency, municipal infrastructure, and subventions. Target: $5,000,000.00; Critical: $500,000.00.
     - `gov:city:tax` (`tax_pool`): Inflow pool for Point-of-Sale (POS) taxes and P2P wire transfer duties. Emptied during periodic revenue sweeps.
     - `gov:dept:police` (`department`): San Andreas State Police operating budget for payroll, tactical fleet, and stations.
     - `gov:dept:ems` (`department`): Emergency Medical Services operating budget for hospital supplies, paramedic wages, and ambulances.
     - `gov:dept:works` (`department`): Public Works infrastructure budget for power grid substations, water treatment, and road maintenance.
     - `gov:dept:dividend` (`grant_pool`): Social Dividend & Small Grants fund redistributing public surpluses back to citizens.
   - Balance Sheet Invariants:
     - Total Municipal Liquidity: Sum of all public and departmental account balances.
     - Double-Entry Conservation: All transactions record symmetric debit and credit entries with exact cent precision ($\sum \text{Debits} \equiv \sum \text{Credits}$).
     - Solvency ratings:
       - Account balance $\ge 50\%$ of target/cap: `SOLVENT`
       - Account balance between $20\%$ and $49\%$: `LOW_RESERVE`
       - Account balance $< 20\%$: `DEFICIT_WARNING`
       - Account balance $\le \$0.00$: `DEPLETED`

2. **Automated Percentage Splits & Statutory Pillars (Tervek.md 1.1 - 1.2)**:
   - Three Core Statutory Allocation Pillars:
     1. Emergency Services (Payroll & Fleet): Police (35.00%) + EMS (25.00%) = 60.00% total.
     2. Public Works / Infrastructure: Works (25.00%).
     3. Social Dividend & Small Grants: Dividend (15.00%).
     (Total allocation percentage $\equiv 100.00\%$).
   - Revenue Sweep Rules:
     - Minimum tax pool threshold for sweep: $10.00.
     - Department Cap Limits: Each department has a statutory maximum balance (e.g. Police $1.5M, EMS $1.0M, Works $800k, Dividend $500k).
     - Cap overflow behavior: If a department's current balance + allocation share exceeds its statutory cap, the excess overflow is automatically redirected to the Municipal Master Reserve (`gov:city:master`) as public surplus.
     - Exact Cent Conservation: Floored cents arithmetic ensures $\sum \text{Allocations} + \text{MasterSurplus} \equiv \text{CollectedAmount}$.
     - Immutable audit record written to `nyx_treasury_revenue_sweeps`.

3. **Fiscal Crisis Telemetry & Logarithmic Wage Scaling**:
   - Fiscal Crisis State Machine:
     - `SOLVENT`: Reserve $\ge \$5,000,000.00$. Full 100% wage payouts.
     - `THROTTLED`: $\$2,500,000.00 \le \text{Reserve} < \$5,000,000.00$. Mild wage tapering (approx 85-99%).
     - `AUSTERITY`: $\$500,000.00 \le \text{Reserve} < \$2,500,000.00$. Public sector austerity measures (10-84% wages).
     - `CRITICAL_DEFICIT`: $\text{Reserve} \le \$500,000.00$. Public payroll frozen (0%), infrastructure degraded.
     - `CIRCUIT_TRIPPED`: Active circuit breaker from rapid drain or anomalous debit.
   - Public Wage Multiplier Formula:
     $$\text{Multiplier} = \text{Floor} + (1.0 - \text{Floor}) \times \frac{\ln(\text{Current} / \text{Critical})}{\ln(\text{Target} / \text{Critical})}$$
   - Outflow Velocity & Runway:
     - 10-minute rolling outflow velocity window ($/sec, $/hr).
     - Projected Runway Hours: $(\text{CurrentReserve} - \text{CriticalReserve}) / \text{VelocityPerHour}$.
   - Infrastructure Degradation Modes:
     - Auto-Repair Stations: Offline if Reserve $\le \$100,000$ or state is `CRITICAL_DEFICIT` / `CIRCUIT_TRIPPED`.
     - Civic Impound Lots: +50% surcharge during austerity or crisis states.
     - AI Dispatchers: Reduced responsiveness / delayed dispatch when degraded.

4. **Web UI Master Single-Page Application (`nyx_ui`)**:
   - Single-frame CEF SPA integration.
   - Tab 1: Balance Sheet & Accounts Overview.
   - Tab 2: Filterable Transaction Ledger with live pagination and search.
   - Tab 3: Department Budget Allocation Monitor with statutory progress gauges.
   - Tab 4: Fiscal Crisis & Circuit Breaker Telemetry with interactive charts/gauges.
