# 🌌 Nyxframework Master Repository

Welcome to the **Nyxframework** repository.

This project delivers a complete, modular, zero-trust authoritative roleplay framework for **FiveM**, designed according to the specifications documented in Obsidian specs `01.md` through `10.md` and `Tervek.md`.

## 📁 Repository Structure
- [`FiveM/`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM): Contains all 11 production-ready framework resources and server configs.
  - [`nyx_core`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/nyx_core) — Auth kernel, bitwise SHA-256 migrations, RPC bus, token-bucket limiter, and player registry.
  - [`nyx_inventory`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/nyx_inventory) — Mutex-locked atomic containers, dynamic slots, durability degradation, and ground drops.
  - [`nyx_treasury`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/nyx_treasury) — Closed-loop double-entry accounting, POS/P2P tax interceptor, and fiscal crisis engine.
  - [`nyx_logistics`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/nyx_logistics) — Depleting extraction nodes, player refineries, freight hauling, and price elasticity.
  - [`nyx_parliament`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/nyx_parliament) — Anti-Sybil voter registry, Instant-Runoff Voting (IRV) tabulation, and real-time statutes.
  - [`nyx_judiciary`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/nyx_judiciary) — Cryptographic evidence fingerprints, contamination matrices, and automated jury verdicts.
  - [`nyx_factions`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/nyx_factions) — Staff-free legal charters, RBAC permission nodes, multi-sig vaults, and automated dividends.
  - [`nyx_services`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/nyx_services) — Regional electrical substations, blackout cascade mode, metered utility billing, and medical supplies.
  - [`nyx_vehicles`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/nyx_vehicles) — Full state damage/fuel persistence, dynamic trunk/glovebox bindings, and 5-tier key access.
  - [`nyx_interact`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/nyx_interact) — Dormant spatial raycasting (0.00 ms idle) and declarative target registries.
  - [`nyx_ui`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/nyx_ui) — Master Single Page Application shell hosting HUD, notifications, modals, and inventory.
  - [`server.cfg.example`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/server.cfg.example) — Production server configuration and ensure sequence.
  - [`bootstrap_check.bat`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/bootstrap_check.bat) / [`bootstrap_check.sh`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/bootstrap_check.sh) — Health check scripts.

For detailed deployment instructions and performance targets, see [`FiveM/README.md`](file:///c:/Users/Admin/Desktop/Nyxframework/FiveM/README.md).
