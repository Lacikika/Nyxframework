# Security Policy

## Supported Versions

Only the latest release on the `main` branch receives security fixes.

| Version | Supported |
|---|---|
| `main` (latest) | ✅ |
| Older branches | ❌ |

---

## Reporting a Vulnerability

**Do not open a public GitHub Issue for security vulnerabilities.**

If you discover a vulnerability, please report it via **GitHub's private security advisory system**:

1. Go to the [Security tab](https://github.com/YOUR_USERNAME/Nyxframework/security/advisories/new) of this repository.
2. Click **"New draft security advisory"**.
3. Describe the vulnerability, steps to reproduce, and potential impact.

We will acknowledge your report within **48 hours** and aim to release a patch within **7 days** for critical issues.

---

## Security Architecture

Nyxframework is designed with a **zero-trust, server-authoritative** security model. Key controls include:

### Token-Bucket RPC Rate Limiting

Every player event processed by the RPC bus in `nyx_core` passes through a per-player token-bucket rate limiter. Default limits:

| Category | Limit |
|---|---|
| General events | 20 req / 5 seconds |
| Economy mutations | 5 req / 10 seconds |
| Admin commands | 3 req / 30 seconds |

Exceeding the limit results in the event being silently dropped and a server-side warning log entry. Repeated abuse triggers an automatic temporary ban via `DropPlayer`.

### Zero-Trust Guidelines

- **No client-side state authority**: All game state lives server-side. Clients send intent; servers validate and respond.
- **Source validation**: Every server event handler validates `GetPlayerName(source)` before processing.
- **Nonce-based anti-replay**: Sensitive actions require a `GenerateNonce()` token from `nyx_core` to prevent replay attacks.
- **SQL parameterization**: All database queries use `oxmysql` parameterized queries. String interpolation into SQL is forbidden.
- **Server.cfg is git-ignored**: Connection strings, server keys, and tokens must never be committed.

### Economy Integrity

- The treasury uses a **closed-loop double-entry accounting** model. Money cannot be created or destroyed outside explicit mint/burn events audited in the server log.
- All balance mutations go through `nyx_treasury` exports, never direct SQL writes.

---

## Responsible Disclosure

We appreciate responsible disclosure and will publicly credit researchers in the changelog (unless they prefer anonymity). We do **not** currently offer a bug bounty.
