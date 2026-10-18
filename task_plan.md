# Task Plan: Citizen OS Master Smartphone Framework (`nyx_ui`)

## Goal
Implement a unified single-frame CEF smartphone OS ("Citizen OS") for `nyx_ui` that integrates mobile banking (`nyx_treasury`), a mobile freight dispatch board (`nyx_logistics`), and emergency citizen alerts & 911 dispatch (`nyx_mdt`). The phone is fully CEF-compliant, delta-throttled, accessible via `/phone` or F1 keybinding, and supports seamless app switching between CivicPay, HaulExpress, CivicAlert, CivicID, and Settings.

## Architecture & Requirements
1. **Database Migration (`040_citizen_os_smartphone_framework.sql` & `index.json`)**:
   - `nyx_phone_emergency_alerts`: Immutable log of citizen emergency alerts (`alert_id`, `alert_uuid`, `citizen_id`, `caller_name`, `category`, `message`, `location_label`, `coords_json`, `priority`, `status`, `created_at`).
   - `nyx_phone_settings`: Per-citizen phone preferences and registry (`citizen_id`, `phone_number`, `wallpaper`, `dark_mode`, `airplane_mode`, `notifications_enabled`, `updated_at`).
   - Register in `FiveM/nyx_core/sql/migrations/index.json` (Step 40) and mirror to `FiveM/nyx_ui/sql/migrations/`.

2. **Pure Lua 5.4 Shared Engine (`nyx_ui/shared/phone.lua`)**:
   - `Nyx.Phone.FormatPhoneNumber(number)`: Standardized phone formatting.
   - `Nyx.Phone.GeneratePhoneNumber(citizenId)`: Deterministic phone number derivation.
   - `Nyx.Phone.FormatCurrency(amount)`: Standard currency formatting.
   - `Nyx.Phone.CalculateTransferTax(amount, taxRate)`: Pure math P2P transfer tax calculation with 2-decimal cent rounding.
   - `Nyx.Phone.ValidateTransferPayload(payload, senderCitizenId)`: Zero-trust validation (self-transfer prevention, amount bounds $1-$10,000,000, memo sanitization).
   - `Nyx.Phone.ValidateEmergencyAlertPayload(payload)`: Category whitelist ('police', 'medical', 'fire', 'traffic', 'general'), narrative minimums (5-500 chars), priority whitelist.
   - `Nyx.Phone.FormatAlertBadge(priority, category)`: UI badge metadata and styling tokens.
   - `Nyx.Phone.FormatContractCard(contract)`: Formats freight hauling contract for mobile display.
   - `Nyx.Phone.FilterFreightContracts(contracts, filterType, search)`: Case-insensitive search and category filtering.
   - Register in `FiveM/nyx_ui/fxmanifest.lua`.

3. **Server-Side Subsystem & RPCs (`nyx_ui/server/phone.lua`, `server/exports.lua`)**:
   - `GetPhoneOverview`: Aggregates citizen identity, bank balance, recent ledger transactions, active freight contract, available contract count, emergency alerts feed, and phone settings.
   - `TransferMoney`: Double-entry atomic transfer via `nyx_treasury` with automatic transfer tax deduction to municipal treasury.
   - `SendEmergencyAlert`: Validates payload, stores immutable alert, forwards call to `nyx_mdt` dispatch engine, and broadcasts client alert event.
   - `GetEmergencyAlerts`: Queries active emergency broadcasts feed.
   - `GetFreightBoard`: Queries available logistics contracts from `nyx_logistics`.
   - `ClaimFreightContract`: Claims contract directly from phone via `nyx_logistics`.
   - `UpdateSettings`: Updates wallpaper, dark mode, airplane mode.
   - RPC endpoints: `phone:getOverview`, `phone:transferMoney`, `phone:getFreightBoard`, `phone:claimContract`, `phone:sendEmergencyAlert`, `phone:getEmergencyAlerts`, `phone:updateSettings`.
   - Server exports in `server/exports.lua`.

4. **Client-Side Dispatch & UI Bridge (`nyx_ui/client/phone.lua`, `client/bridge.lua`, `client/exports.lua`)**:
   - Client commands: `/phone`, `/smartphone`, `/citizenphone`.
   - Key mapping: F1 for opening/closing phone.
   - Bridge updates: parameter sanitization for phone parameters; safe NUI callbacks for `closePhone`, `phone:getOverview`, `phone:transferMoney`, `phone:getFreightBoard`, `phone:claimContract`, `phone:loadFreightPallet`, `phone:deliverContract`, `phone:abandonContract`, `phone:sendEmergencyAlert`, `phone:getEmergencyAlerts`, `phone:updateSettings`.
   - Client exports: `OpenPhone`, `ClosePhone`, `TogglePhone`, and mapping in `OpenView`.

5. **Web Single-Frame CEF SPA (`nyx_ui/web/`)**:
   - HTML (`index.html`): Section 8H `#phone-overlay` featuring a sleek smartphone chassis (bezel, dynamic island / speaker notch, status bar with live time, WiFi, 5G, and battery), home screen app launcher grid (CivicPay, HaulExpress, CivicAlert, CivicID, Settings), and dedicated app screens for Banking, Freight Logistics, Emergency Alerts, Profile, and Settings. Also `#dev-btn-phone` in dev mode toolbar.
   - CSS (`css/app.css`): Section 22 CEF-compliant styling strictly adhering to render budget (high-opacity dark surfaces `rgba(15, 23, 42, 0.96)`, zero GPU shaders, zero `backdrop-filter`, zero `blur()`, touch targets $\ge 40$px, WCAG AA+ contrast).
   - JavaScript (`js/app.js`): Added `NyxState.phone` reactive state, message listeners (`PHONE_OPEN`/`PHONE_CLOSE`), app switcher state machine (`switchPhoneApp`), live balance updates, P2P transfer submission with tax calculation preview, freight contract claiming and tracking, emergency alert dispatching, escape key handling (back to home screen or close), button locking (`lockButtonAction`), and browser dev mode mock telemetry.

6. **In-Engine Integration Test (`FiveM/nyx_core/server/tests.lua`)**:
   - Add Test 35 `Nyx.Tests.TestCitizenOSSmartphoneFramework()` covering transfer tax math, payload validation, phone formatting, priority badges, and mobile contract filtering.
   - Wire into `RunAll()`.

7. **Full Verification**:
   - Dedicated Python test suite `tests/test_citizen_os_smartphone_framework.py`.
   - Full test suite via `pytest`.
   - Engine syntax and asset validation via `python scripts/validator.py` and `powershell -File scripts/verify.ps1`.
   - Update `AGENT_TASK.md` marking task completed.

## Phase Plan
- [x] Phase 1: Test-Driven Design — Create Python test suite (`tests/test_citizen_os_smartphone_framework.py`)
- [x] Phase 2: Database Migration — Create `040_citizen_os_smartphone_framework.sql`, register in `index.json`, mirror to `nyx_ui`
- [x] Phase 3: Pure Lua 5.4 Shared Engine — Implement `FiveM/nyx_ui/shared/phone.lua` & update `fxmanifest.lua`
- [x] Phase 4: Server Subsystem & RPCs — Implement `server/phone.lua`, `server/exports.lua`, update `fxmanifest.lua`
- [x] Phase 5: Client Dispatch & UI Bridge — Implement `client/phone.lua`, update `client/bridge.lua`, and `client/exports.lua`
- [x] Phase 6: Web Single-Frame CEF SPA — Update `index.html`, `css/app.css`, and `js/app.js`
- [x] Phase 7: In-Engine Lua Test Suite — Implement Test 35 in `FiveM/nyx_core/server/tests.lua`
- [x] Phase 8: Full Verification & Completion — Run pytest, validator, verify.ps1, update `AGENT_TASK.md`
