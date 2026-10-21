# 🚀 Repo Owner Success & Launch Playbook

> **Your step-by-step guide to launching Nyxframework publicly on GitHub and growing the community.**

---

## ⚡ Quick Launch (Automated — Recommended)

If you have a GitHub Personal Access Token, one command does everything:

```bash
py scripts/github_launch.py --token ghp_XXXXXXXXXXXXXXXXXXXX
```

This will:
1. Detect your GitHub username from the token
2. Create the public `Nyxframework` repository via the GitHub API
3. Add the `origin` remote and push `main`
4. Set all recommended repository topics
5. Enable branch protection rules on `main`

**Options:**

| Flag | Description |
|---|---|
| `--token <PAT>` | *(required)* GitHub Personal Access Token |
| `--username <name>` | Override GitHub username (auto-detected if omitted) |
| `--repo <name>` | Override repository name (default: `Nyxframework`) |
| `--private` | Create as a private repo instead of public |
| `--desc "..."` | Override the repository description |
| `--dry-run` | Print what would happen without making any changes |

**Generating a token:**  
Go to [github.com/settings/tokens/new](https://github.com/settings/tokens/new) → select scopes: **`repo`** (required) + **`delete_repo`** (optional). Copy the `ghp_...` token and pass it as `--token`.

> [!CAUTION]
> Never commit your token. Pass it only on the command line or via an environment variable — it is not stored anywhere by this script.

After the script completes, update the CI badge URL in `README.md` (replace `YOUR_USERNAME` with your real GitHub username) and commit:

```bash
# Edit README.md, then:
git add README.md
git commit -m "docs: update CI badge URL with real GitHub username"
git push
```

---

## Manual Steps (Fallback)

The sections below describe the same process manually, in case you prefer full control.

---

## Table of Contents

1. [Create the GitHub Repository & Push `main`](#1-create-the-github-repository--push-main)
2. [Recommended Repository Settings](#2-recommended-repository-settings)
3. [Cfx.re (FiveM Forum) Release Announcement](#3-cfxre-fivem-forum-release-announcement)
4. [Discord Community Guidelines & Support Channels](#4-discord-community-guidelines--support-channels)
5. [Managing Releases, Packages & PRs](#5-managing-releases-packages--prs)

---

## 1. Create the GitHub Repository & Push `main`

### Step 1.1 — Create the remote repository

Go to [github.com/new](https://github.com/new) and create a new **public** repository named `Nyxframework`.

- ❌ Do **not** initialize it with a README, `.gitignore`, or license (we already have those).

### Step 1.2 — Add the remote and rename the branch

```bash
# From your local Nyxframework directory:
git remote add origin https://github.com/YOUR_USERNAME/Nyxframework.git

# Rename local branch to main (if not already)
git checkout -B main
```

### Step 1.3 — Push `main`

```bash
git push -u origin main
```

### Step 1.4 — Verify CI passes

After pushing, visit:

```
https://github.com/YOUR_USERNAME/Nyxframework/actions
```

You should see the **Nyxframework CI** workflow run automatically. Both the validator and the 560-test pytest suite must show green.

### Step 1.5 — Update the README badge URL

Open `README.md` and replace `YOUR_USERNAME` in the CI badge URL:

```markdown
[![CI](https://github.com/YOUR_USERNAME/Nyxframework/actions/workflows/ci.yml/badge.svg)](...)
```

Commit and push:

```bash
git add README.md
git commit -m "docs: update CI badge URL with real GitHub username"
git push
```

---

## 2. Recommended Repository Settings

Navigate to **Settings** on your GitHub repository and apply the following:

### About (top-right on the repo home page)

| Field | Value |
|---|---|
| **Description** | Complete zero-trust authoritative FiveM roleplay framework — closed-loop economy, IRV governance, 560 tests, GPL-3.0 |
| **Website** | *(your Cfx.re release thread URL once posted)* |
| **Topics** | `fivem`, `lua`, `roleplay`, `fivem-framework`, `cerulean`, `onesync`, `gpl3`, `gameserver`, `fivem-server` |

### General Settings

- ✅ **Discussions** — Enable this. Use it as your primary support channel.
- ✅ **Issues** — Keep enabled (templates are already configured).
- ✅ **Projects** — Optional, useful for roadmap tracking.
- ✅ **Preserve this repository** — Check if you want GitHub Archive Program inclusion.
- ❌ **Allow merge commits** — Disable. Use squash or rebase only for a clean `git log`.
- ✅ **Allow squash merging** — Enable with message "Pull request title and commit details".
- ✅ **Automatically delete head branches** — Enable.

### Branch Protection Rules (for `main`)

Go to **Settings → Branches → Add rule** for branch `main`:

| Rule | Setting |
|---|---|
| Require a pull request before merging | ✅ |
| Require status checks to pass before merging | ✅ — Select the `validate-and-test` CI job |
| Require branches to be up to date before merging | ✅ |
| Do not allow bypassing the above settings | ✅ (even for admins) |
| Allow force pushes | ❌ |
| Allow deletions | ❌ |

---

## 3. Cfx.re (FiveM Forum) Release Announcement

Post this in the **[Releases](https://forum.cfx.re/c/development/releases)** category on [forum.cfx.re](https://forum.cfx.re).

---

### 📋 Post Template

**Title:** `[Release] Nyxframework — Zero-Trust FiveM Roleplay Framework (GPL-3.0, 560 Tests)`

**Body:**

```
## 🌌 Nyxframework — Open Source FiveM Roleplay Framework

Hello FiveM community!

I'm excited to release **Nyxframework** as a fully open-source project under the GPL-3.0 license.

Nyxframework is a complete, modular, zero-trust authoritative roleplay framework built from first principles. It is designed for production FiveM servers running Cerulean (Artifact 3095+) with OneSync Infinity.

---

### ✨ Highlights

- **14 resource modules** — core, inventory, treasury, logistics, parliament, judiciary, factions, services, vehicles, interact, MDT, press, properties, UI
- **Zero-trust server authority** — clients send intent; servers validate and respond. No client-side state.
- **Closed-loop double-entry economy** — money cannot appear from nowhere. Every transaction is audited.
- **IRV governance system** — anti-Sybil voter registry and Instant-Runoff Voting tabulation
- **Cryptographic justice** — evidence fingerprints, contamination matrices, automated jury verdicts
- **0.00 ms idle UI** — single-frame CEF SPA with dormant spatial raycasting
- **560 automated pytest tests** with GitHub Actions CI
- **GPL-3.0 licensed** — free to use, modify, and redistribute (with source disclosure)

---

### 🚀 Requirements

- FiveM Server Artifact ≥ 3095 (Cerulean)
- OneSync Infinity
- oxmysql (latest)
- MySQL / MariaDB 8.0+

---

### 📦 GitHub

👉 https://github.com/YOUR_USERNAME/Nyxframework

Full installation guide and architecture docs are in the README.

---

### 🤝 Contributing

PRs welcome! See CONTRIBUTING.md for coding standards and zero-trust validation rules.
All 560 tests must pass. CI is required to merge.

---

*Questions? Post below or open a GitHub Discussion.*
```

---

## 4. Discord Community Guidelines & Support Channels

### Recommended Channel Structure

| Channel | Purpose |
|---|---|
| `#announcements` | Release notes, security advisories (admin only) |
| `#general` | General discussion |
| `#support` | Installation and configuration help |
| `#dev-chat` | Contributor discussion, PR reviews |
| `#showcase` | Community servers using Nyxframework |
| `#bug-reports` | Triage (link to GitHub Issues) |

### Support Channel Guidelines (pin in `#support`)

```
📌 SUPPORT RULES

1. Before asking, search the GitHub README and docs (01.md – 10.md).
2. Run `python scripts/validator.py` and paste the output with your question.
3. Include your FiveM artifact version, oxmysql version, and OneSync mode.
4. For bugs: open a GitHub Issue using the Bug Report template.
5. For security issues: do NOT post here. Use GitHub's private security advisory.
6. Be patient and respectful (see Code of Conduct).
```

### Role Structure

| Role | Who gets it |
|---|---|
| `@Maintainer` | Repository owners and core contributors |
| `@Contributor` | Anyone who has merged a PR |
| `@Community` | All verified members |

---

## 5. Managing Releases, Packages & PRs

### Creating a Release

1. Decide on a version number following [Semantic Versioning](https://semver.org/): `vMAJOR.MINOR.PATCH`
2. Run the full test suite one final time: `pytest -v tests/`
3. Create and push a git tag:

```bash
git tag -a v1.0.0 -m "Release v1.0.0 — Initial open-source launch"
git push origin v1.0.0
```

4. Go to **GitHub → Releases → Draft a new release**.
5. Select the tag, write release notes (summarize changes since last tag), and attach a zip:

```bash
# Create a clean zip for server owners (excludes git history, tests, and dev scripts)
git archive --format=zip --prefix=Nyxframework/ HEAD -- FiveM/ README.md LICENSE > Nyxframework-v1.0.0.zip
```

6. Upload `Nyxframework-v1.0.0.zip` as a release asset. Server owners download this instead of cloning.

### PR Triage Process

1. **Check CI status first** — never review a PR with failing CI. Return it with a comment.
2. **Check the checklist** — ensure the PR template is filled out fully.
3. **Run locally** for non-trivial changes:
   ```bash
   git fetch origin pull/<PR_NUMBER>/head:pr-<PR_NUMBER>
   git checkout pr-<PR_NUMBER>
   python scripts/validator.py && pytest -v tests/
   ```
4. **Squash-merge** to keep `git log` clean. The commit message should follow the Conventional Commits format.
5. After merge, **delete the head branch** (GitHub does this automatically if you enabled it in settings).

### Staying on Top of Issues

- **Label everything**: Use `bug`, `enhancement`, `documentation`, `good first issue`, `help wanted`, `wontfix`.
- **Mark `good first issue`** on well-defined, self-contained issues to attract new contributors.
- **Close stale issues** after 30 days of no activity with a polite comment linking to Discussions.

---

*Good luck with the launch! 🚀*
