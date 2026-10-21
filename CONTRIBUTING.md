# Contributing to Nyxframework

Thank you for considering contributing to Nyxframework! This document explains the standards
and workflow we require for all contributions.

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Coding Standards](#coding-standards)
3. [Zero-Trust Validation Rules](#zero-trust-validation-rules)
4. [Lua 5.4 Conventions](#lua-54-conventions)
5. [Running Tests Before Submitting](#running-tests-before-submitting)
6. [Pull Request Process](#pull-request-process)
7. [Commit Message Format](#commit-message-format)

---

## Getting Started

1. **Fork** the repository and create your branch from `main`.
2. Ensure your development environment has Python 3.12+ and pytest installed.
3. Run the full validator and test suite before writing a single line of code to confirm your baseline.

```bash
python scripts/validator.py    # 14 resources must pass
pytest -v tests/               # 560 tests must pass
```

---

## Coding Standards

### General

- **No secrets in source**: Never commit `server.cfg`, API keys, private IPs (`192.168.*`), or credentials. Use `.env` files or `server.cfg` (which is git-ignored by design).
- **No personal paths**: Keep all file paths relative to the resource root.
- **Consistent formatting**: Lua files use 4-space indentation. No tabs.
- **Meaningful names**: Variables and functions use `camelCase` for locals, `PascalCase` for exported symbols, and `SCREAMING_SNAKE_CASE` for module-level constants.

### Lua Specifics

- All Lua must be **syntactically valid under Lua 5.4**. The CI validator will catch parse errors.
- Prefer `local` for all variables not intentionally exported. Never pollute the global scope.
- Use `pcall`/`xpcall` around any untrusted external data (player input, DB results, NUI callbacks).

### Python / Test Code

- Tests live in `tests/`. Follow the existing file/class naming conventions.
- All test functions must be deterministic — no random seeds, no network calls in unit tests.
- Use type hints in new Python utility code.

---

## Zero-Trust Validation Rules

Nyxframework enforces **server-authority on all state mutations**. When adding a new feature:

1. **No client-side state authority**: Clients send intent events (e.g., `nyx:intent:useItem`). Servers validate, mutate state, then broadcast the result.
2. **All RPC calls go through `nyx_core`'s token-bucket rate limiter**. Do not bypass it with raw `TriggerEvent` for game-logic actions.
3. **Economy mutations must use the double-entry ledger** in `nyx_treasury`. Never directly `UPDATE balance` in SQL from outside `nyx_treasury`.
4. **Validate all player source IDs** server-side with `GetPlayerName(source) ~= nil` before processing any event.
5. **Cryptographic nonces**: Use `exports.nyx_core:GenerateNonce()` for any security-sensitive token generation.

---

## Lua 5.4 Conventions

| Pattern | Correct | Avoid |
|---|---|---|
| Integer division | `a // b` | `math.floor(a / b)` |
| Integer type hint | `local x <const> = 42` | bare `local x = 42` where const is appropriate |
| Table access | `table[key]` with nil-check | Unchecked access on untrusted input |
| String formatting | `string.format(...)` | Concatenation in hot paths |
| Error handling | `pcall(fn, ...)` | Naked calls on untrusted paths |
| Generalized for | `for k, v in next, t do` | `pairs`/`ipairs` in extreme hot loops |

---

## Running Tests Before Submitting

**All 560 tests must pass. Zero failures are acceptable.**

```bash
# Validate manifests, Lua syntax, migrations, and SPA assets
python scripts/validator.py

# Run the full test suite
pytest -v tests/

# Expected output:
# [SUCCESS] Clean! Verified 14 resources, 292 Lua files, and all SQL/SPA assets.
# 560 passed in ~1.5s
```

If you are adding a new feature, add corresponding tests in `tests/`. Aim for ≥ 90% branch coverage on new code paths.

---

## Pull Request Process

1. Ensure all tests pass locally (see above).
2. Update documentation if the change affects public exports or the architecture.
3. Fill out the PR template completely — partial PRs will be returned for revision.
4. PRs with failing CI checks will **not** be merged.
5. At least one maintainer review is required before merge.

---

## Commit Message Format

We follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification:

```
<type>(scope): <short description>

[optional body]

[optional footer]
```

| Type | When to use |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `chore` | Maintenance, build, CI |
| `perf` | Performance improvement |
| `refactor` | Code restructure without behavior change |
| `test` | Adding or correcting tests |
| `ci` | CI/CD pipeline changes |

Example: `fix(nyx_treasury): prevent negative balance race condition in P2P transfers`

---

## Code of Conduct

By participating in this project, you agree to uphold our [Code of Conduct](CODE_OF_CONDUCT.md).

---

*Questions? Open a [Discussion](https://github.com/YOUR_USERNAME/Nyxframework/discussions) rather than an Issue.*
