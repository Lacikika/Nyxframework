# Findings: Citizen OS Master Smartphone Framework (`nyx_ui`)

## Context & Architecture
1. **Smartphone Concept in Nyxframework (`nyx_ui`)**:
   - Master SPA shell at `FiveM/nyx_ui/web/index.html`.
   - The Citizen OS Smartphone is a unified single-frame CEF smartphone component rendering directly inside the master SPA without requiring a separate CEF webview or resource.
   - Provides a responsive mobile viewport (360x720px) styled like a modern smartphone with status bar (clock, 5G signal, wifi, battery), home screen app launcher grid, and application windows.
   - Integrates 3 key framework resources:
     - Mobile Banking (`nyx_treasury`): Personal bank balance, recent double-entry ledger transfers, direct P2P wire transfers with progressive transfer tax.
     - Freight & Logistics Board (`nyx_logistics`): Mobile contract marketplace, in-transit contract tracking banner, and remote contract claiming.
     - Citizen Emergency Alerts (`nyx_mdt`): Quick 911 citizen report submission with incident category and GPS position, plus citywide emergency public alert broadcasts.

2. **Integration Invariants**:
   - Zero GPU Shaders / CEF 60 FPS Render Budget:
     - High-opacity dark chassis (`rgba(15, 23, 42, 0.96)`) with subtle borders (`1px solid rgba(148, 163, 184, 0.2)`).
     - Strict prohibition of `backdrop-filter` and `blur()`.
     - Touch targets $\ge 40$px with clear visual feedback.
   - P2P Wire Transfer Conservation:
     - Transfer fee calculated as `math.floor(amount * taxRate * 100) / 100`.
     - Deducted from sender, wire amount credited to receiver, transfer tax credited to municipal master account (`gov:city:master`).
     - Strict validation preventing self-transfers (`recipientCitizenId ~= senderCitizenId`), non-numeric amounts, or amounts outside $[1, 10000000]$.
   - Emergency Alert Zero-Trust Pipeline:
     - Sanitized narrative (5 to 500 characters), whitelisted categories (`police`, `medical`, `fire`, `traffic`, `general`), and priority bounds (`low`, `medium`, `high`, `critical`).
     - Directly logs to `nyx_phone_emergency_alerts` and bridges to `nyx_mdt` emergency dispatch queue (`Nyx.MDT.CreateCall`).

3. **Database Schema Additions (Migration 040)**:
   - `nyx_phone_emergency_alerts` table: immutable log of citizen emergency reports and public broadcasts.
   - `nyx_phone_settings` table: citizen phone preferences (phone number, wallpaper, dark mode, airplane mode).
   - Mirrored to both `nyx_core` and `nyx_ui` migration directories.
