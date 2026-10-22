# 🤖 Instructions for AI Pipeline Agents

Welcome to `Lacikika/Nyxframework`. When developing features or fixing bugs in this codebase, adhere strictly to the following instructions.

---

## 📋 Merge Conflict & Schema Collision Check Protocol

Before submitting a Pull Request, every AI agent **MUST** execute the following checks:

1. **Database Migration Sequence & State Detection:**
   - Inspect `FiveM/nyx_core/sql/migrations/index.json` and directory listings in `FiveM/nyx_core/sql/migrations/`.
   - Ensure the new migration N+1 is strictly sequential with 3-digit zero-padding (`067_<name>.sql`).
   - Register the new SQL migration file in BOTH `FiveM/nyx_core/sql/migrations/index.json` AND `FiveM/nyx_core/server/migrations.lua` (if fallback manifest exists).
   - Mirror the SQL migration across any module migration folders (e.g. `FiveM/nyx_<module>/sql/migrations/`).

2. **Branch & Git Collision Prevention:**
   - Verify active git branches and origin tracking to prevent branch naming collisions or conflicting migration sequence numbers.

3. **Validation & Test Execution:**
   - Execute all verification tools before submission:
     ```bash
     python3 scripts/validator.py
     python3 FiveM/scripts/bootstrap_validator.py
     pytest
     ```
   - Ensure all 14 resource manifests, Lua scripts, SQL migrations, and test suites pass cleanly with zero errors.
