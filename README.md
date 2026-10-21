# 🌌 Nyxframework

> **A complete, modular, zero-trust authoritative roleplay framework for FiveM — built from first principles.**

[![CI](https://github.com/YOUR_USERNAME/Nyxframework/actions/workflows/ci.yml/badge.svg)](https://github.com/YOUR_USERNAME/Nyxframework/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![FiveM: Cerulean](https://img.shields.io/badge/FiveM-Cerulean-orange)](https://docs.fivem.net/)
[![Lua 5.4](https://img.shields.io/badge/Lua-5.4-blueviolet)](https://www.lua.org/)
[![OneSync: Infinity](https://img.shields.io/badge/OneSync-Infinity-green)](https://docs.fivem.net/docs/scripting-reference/onesync/)
[![Tests: 560 passed](https://img.shields.io/badge/tests-560%20passed-brightgreen)](tests/)
[![oxmysql](https://img.shields.io/badge/DB-oxmysql-blue)](https://github.com/overextended/oxmysql)

---

## 📖 Overview

Nyxframework is a production-grade FiveM roleplay framework designed with a **zero-trust, server-authoritative architecture**. Every client action is validated server-side. The economy is a **closed-loop double-entry accounting system** with no money creation outside explicit mint events. The UI is a **single-frame CEF SPA** with sub-millisecond idle cost.

The framework is fully specified across 10 architecture documents and a master plan (`Tervek.md`), and ships with **560 automated pytest unit and integration tests** plus a dedicated manifest validator.

---

## 🏛️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   NYXFRAMEWORK — SERVER                          │
│                                                                  │
│  ┌─────────────┐   RPC Bus    ┌──────────────────────────────┐  │
│  │  nyx_core   │◄────────────►│  All Resource Modules (×13)  │  │
│  │ Auth Kernel │  Token-Bucket│  (validated, rate-limited)   │  │
│  │ SHA-256 Mig │  Limiter     └──────────────────────────────┘  │
│  │ Player Reg  │                                                 │
│  └─────────────┘                                                 │
│         │                                                        │
│         ▼                                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │            CLOSED-LOOP DOUBLE-ENTRY ECONOMY              │   │
│  │  nyx_treasury: POS/P2P tax interceptor, fiscal engine    │   │
│  │  nyx_logistics: extraction nodes, price elasticity       │   │
│  │  nyx_factions: multi-sig vaults, automated dividends     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │            GOVERNANCE & JUSTICE LAYER                    │   │
│  │  nyx_parliament: IRV tabulation, live statutes           │   │
│  │  nyx_judiciary: cryptographic evidence, jury verdicts    │   │
│  │  nyx_mdt: mobile data terminal, incident management      │   │
│  │  nyx_press: player-authored news, editor permissions     │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                             ▲
               NUI / SendNUIMessage
                             │
┌─────────────────────────────────────────────────────────────────┐
│                   CLIENT — CEF SPA (nyx_ui)                      │
│      HUD · Notifications · Inventory · Modals · Properties       │
│           0.00 ms idle  ·  single-frame render                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📦 14 Resource Modules

| Resource | Description | Key Exports / Events |
|---|---|---|
| `nyx_core` | Authoritative auth kernel, bitwise SHA-256 DB migrations, RPC bus, token-bucket rate limiter, player registry, `GenerateNonce` | `GetPlayer`, `GetPlayers`, `GenerateNonce`, `nyx:playerLoaded` |
| `nyx_inventory` | Mutex-locked atomic containers, dynamic slots, durability degradation, ground drops | `GetItem`, `AddItem`, `RemoveItem`, `OpenContainer` |
| `nyx_treasury` | Closed-loop double-entry accounting, POS/P2P tax interceptor, fiscal crisis engine, bank ledger | `GetBalance`, `Transfer`, `nyx:treasury:taxEvent` |
| `nyx_logistics` | Depleting extraction nodes, player refineries, freight hauling, price elasticity engine | `GetNodeLevel`, `HarvestNode`, `nyx:logistics:priceUpdate` |
| `nyx_parliament` | Anti-Sybil voter registry, Instant-Runoff Voting (IRV) tabulation, real-time statute store | `GetStatutes`, `CastVote`, `nyx:parliament:statuteChanged` |
| `nyx_judiciary` | Cryptographic evidence fingerprints, contamination matrices, automated jury verdict engine | `SubmitEvidence`, `GetCaseFile`, `nyx:judiciary:verdict` |
| `nyx_factions` | Staff-free legal charters, RBAC permission nodes, multi-sig vaults, automated dividends | `GetFaction`, `InviteMember`, `WithdrawVault` |
| `nyx_services` | Regional electrical substations, blackout cascade mode, metered utility billing, medical supplies | `GetPowerStatus`, `TriggerBlackout`, `PurchaseSupplies` |
| `nyx_vehicles` | Full state damage/fuel persistence, dynamic trunk/glovebox bindings, 5-tier key access control | `SpawnVehicle`, `GetVehicleState`, `GiveKey` |
| `nyx_interact` | Dormant spatial raycasting (0.00 ms idle), declarative target registries, zone management | `AddTarget`, `RemoveTarget`, `AddZone` |
| `nyx_mdt` | Mobile data terminal, incident management, BOLO system, officer dispatch | `CreateIncident`, `SearchPlate`, `nyx:mdt:dispatch` |
| `nyx_press` | Player-authored newspaper publishing, editor permissions, article archive | `PublishArticle`, `GetArticles`, `SetEditorRole` |
| `nyx_properties` | Persistent property ownership, interior instancing, rent/mortgage engine | `GetProperty`, `PurchaseProperty`, `nyx:properties:evict` |
| `nyx_ui` | Master CEF Single Page Application: HUD, notifications, modals, inventory overlay | `ShowNotification`, `OpenInventory`, `SetHUDData` |

---

## 🛠️ Server Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| FiveM Server Artifact | `≥ 3095` (Cerulean) | [builds.fivem.net](https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/) |
| OneSync | `Infinity` | Required for >32 players and entity ownership |
| oxmysql | latest | [github.com/overextended/oxmysql](https://github.com/overextended/oxmysql) |
| MySQL / MariaDB | `≥ 8.0` | |
| Node.js | `≥ 18` (optional, for UI dev) | Only needed to rebuild `nyx_ui` SPA |

---

## 🚀 Installation

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/Nyxframework.git
```

### 2. Copy framework resources into your FiveM server

```bash
cp -r Nyxframework/FiveM/nyx_* /your/fivem/server/resources/
cp -r Nyxframework/FiveM/scripts /your/fivem/server/resources/scripts
```

### 3. Configure `server.cfg`

Use the provided example as a template:

```bash
cp Nyxframework/FiveM/server.cfg.example /your/fivem/server/server.cfg
# Edit server.cfg and fill in your MySQL connection string, server key, etc.
```

### 4. Ensure order in `server.cfg`

Resources **must** be started in dependency order. The example config already reflects this:

```cfg
set mysql_connection_string "mysql://user:pass@localhost/nyx?charset=utf8mb4"

# Core first — provides auth kernel and RPC bus
ensure nyx_core

# Economy
ensure nyx_treasury
ensure nyx_logistics

# Physical world
ensure nyx_inventory
ensure nyx_vehicles
ensure nyx_properties

# Social / governance
ensure nyx_factions
ensure nyx_parliament
ensure nyx_judiciary

# Services and content
ensure nyx_services
ensure nyx_mdt
ensure nyx_press
ensure nyx_interact

# UI last (depends on all others for data)
ensure nyx_ui
```

### 5. Run the bootstrap health check

```bash
# Linux
bash Nyxframework/FiveM/bootstrap_check.sh

# Windows
Nyxframework\FiveM\bootstrap_check.bat
```

Expected output: `[OK] All 14 resources verified.`

---

## 🧪 Developer Verification

### Manifest & Syntax Validator

Validates all 14 `fxmanifest.lua` files, 292 Lua syntax files, SQL migrations, and SPA assets:

```bash
python scripts/validator.py
# Expected: [SUCCESS] Clean! Verified 14 resources, 292 Lua files, and all SQL/SPA assets.
```

### Full Test Suite (560 tests)

```bash
pip install pytest
pytest -v tests/
# Expected: 560 passed in ~1.5s
```

Tests cover: RPC bus dispatch, token-bucket rate limiting, double-entry ledger invariants, IRV tabulation, migration sequencing, SHA-256 nonce generation, container mutex semantics, and more.

---

## 📚 Architecture Specifications

| Document | Topic |
|---|---|
| [`01.md`](01.md) | Project Charter & Zero-Trust Principles |
| [`02.md`](02.md) | Core Auth Kernel & RPC Bus |
| [`03.md`](03.md) | Database Migrations & Schema |
| [`04.md`](04.md) | Inventory & Container System |
| [`05.md`](05.md) | Double-Entry Economy (Treasury) |
| [`06.md`](06.md) | Governance — Parliament & Judiciary |
| [`07.md`](07.md) | Factions, RBAC & Multi-Sig Vaults |
| [`08.md`](08.md) | Logistics, Extraction & Price Elasticity |
| [`09.md`](09.md) | Vehicle State, Properties & Services |
| [`10.md`](10.md) | UI SPA Architecture & NUI Protocol |
| [`Tervek.md`](Tervek.md) | Master Plan & Design Decisions |

---

## 🤝 Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for coding standards, Lua 5.4 conventions, zero-trust validation rules, and how to run the test suite before submitting a PR.

---

## 🔒 Security

To report a vulnerability, see [`SECURITY.md`](SECURITY.md). Do **not** open a public issue for security-related bugs.

---

## 📜 License

Nyxframework is licensed under the **GNU General Public License v3.0**.  
See [`LICENSE`](LICENSE) for the full text.

> You are free to use, modify, and distribute this software under the terms of the GPL-3.0. Any derivative work distributed publicly must also be released under GPL-3.0.
