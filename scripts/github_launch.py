#!/usr/bin/env python3
"""
Nyxframework GitHub Launch Script
==================================
Creates the GitHub repository (via API) and pushes the main branch.

Usage:
    py scripts/github_launch.py --token <your_github_token>
    py scripts/github_launch.py --token <your_github_token> --username <gh_username>
    py scripts/github_launch.py --token <your_github_token> --private

Options:
    --token     GitHub Personal Access Token (needs repo scope)
    --username  GitHub username (auto-detected from token if omitted)
    --repo      Repository name (default: Nyxframework)
    --private   Create as a private repository (default: public)
    --desc      Repository description (default: built-in)
    --dry-run   Print what would happen without doing it
"""

import argparse
import json
import subprocess
import sys
import urllib.request
import urllib.error


REPO_NAME_DEFAULT = "Nyxframework"
DESCRIPTION_DEFAULT = (
    "Complete zero-trust authoritative FiveM roleplay framework — "
    "closed-loop economy, IRV governance, 560 tests, GPL-3.0"
)
TOPICS_DEFAULT = [
    "fivem", "lua", "roleplay", "fivem-framework", "cerulean",
    "onesync", "gpl3", "gameserver", "fivem-server",
]


# ---------------------------------------------------------------------------
# GitHub API helpers
# ---------------------------------------------------------------------------

def gh_request(method: str, path: str, token: str, body: dict = None) -> dict:
    url = f"https://api.github.com{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body_text = e.read().decode()
        print(f"[ERROR] GitHub API {method} {path} -> HTTP {e.code}")
        print(f"        {body_text}")
        sys.exit(1)


def get_authenticated_user(token: str) -> str:
    data = gh_request("GET", "/user", token)
    return data["login"]


def repo_exists(token: str, username: str, repo: str) -> bool:
    try:
        gh_request("GET", f"/repos/{username}/{repo}", token)
        return True
    except SystemExit:
        return False


def create_repo(token: str, repo: str, description: str, private: bool) -> dict:
    return gh_request("POST", "/user/repos", token, {
        "name": repo,
        "description": description,
        "private": private,
        "has_issues": True,
        "has_projects": True,
        "has_wiki": False,
        "has_discussions": True,
        "auto_init": False,
        "allow_squash_merge": True,
        "allow_merge_commit": False,
        "allow_rebase_merge": True,
        "delete_branch_on_merge": True,
    })


def set_topics(token: str, username: str, repo: str, topics: list[str]) -> None:
    gh_request("PUT", f"/repos/{username}/{repo}/topics", token, {"names": topics})


def set_branch_protection(token: str, username: str, repo: str, branch: str = "main") -> None:
    gh_request("PUT", f"/repos/{username}/{repo}/branches/{branch}/protection", token, {
        "required_status_checks": {
            "strict": True,
            "contexts": ["validate-and-test"],
        },
        "enforce_admins": True,
        "required_pull_request_reviews": {
            "required_approving_review_count": 1,
            "dismiss_stale_reviews": True,
        },
        "restrictions": None,
        "allow_force_pushes": False,
        "allow_deletions": False,
    })


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

def run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    print(f"  $ {' '.join(cmd)}")
    return subprocess.run(cmd, check=check, capture_output=False)


def git_remote_exists(name: str) -> bool:
    result = subprocess.run(
        ["git", "remote"], capture_output=True, text=True
    )
    return name in result.stdout.split()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Create the Nyxframework GitHub repo and push main."
    )
    parser.add_argument("--token", required=True, help="GitHub Personal Access Token")
    parser.add_argument("--username", default=None, help="GitHub username (auto-detected)")
    parser.add_argument("--repo", default=REPO_NAME_DEFAULT, help="Repository name")
    parser.add_argument("--desc", default=DESCRIPTION_DEFAULT, help="Repository description")
    parser.add_argument("--private", action="store_true", help="Create as private")
    parser.add_argument("--dry-run", action="store_true", help="Print plan only")
    args = parser.parse_args()

    token = args.token

    print("\n🌌 Nyxframework GitHub Launch Script")
    print("=" * 50)

    # 1. Resolve username
    print("\n[1/6] Authenticating with GitHub...")
    username = args.username or get_authenticated_user(token)
    print(f"      Authenticated as: {username}")

    repo_url = f"https://github.com/{username}/{args.repo}"
    clone_url = f"https://{username}:{token}@github.com/{username}/{args.repo}.git"

    if args.dry_run:
        print(f"\n[DRY RUN] Would create {'private' if args.private else 'public'} repo: {repo_url}")
        print(f"[DRY RUN] Would push branch: main")
        print(f"[DRY RUN] Would set topics: {TOPICS_DEFAULT}")
        print(f"[DRY RUN] Would enable branch protection on: main")
        print("\nDry run complete. No changes made.")
        return

    # 2. Create repo
    print(f"\n[2/6] Creating {'private' if args.private else 'public'} repository: {args.repo}...")
    if repo_exists(token, username, args.repo):
        print(f"      Repository already exists: {repo_url}")
    else:
        data = create_repo(token, args.repo, args.desc, args.private)
        print(f"      Created: {data['html_url']}")

    # 3. Set git remote
    print(f"\n[3/6] Configuring git remote 'origin'...")
    if git_remote_exists("origin"):
        run(["git", "remote", "set-url", "origin", clone_url])
        print("      Updated existing 'origin' remote.")
    else:
        run(["git", "remote", "add", "origin", clone_url])
        print("      Added 'origin' remote.")

    # 4. Ensure on main branch
    print(f"\n[4/6] Ensuring local branch is 'main'...")
    run(["git", "checkout", "-B", "main"])

    # 5. Push
    print(f"\n[5/6] Pushing 'main' to GitHub...")
    run(["git", "push", "-u", "origin", "main"])
    print(f"      Pushed! View at: {repo_url}")

    # 6. Set topics
    print(f"\n[6/6] Applying repository topics...")
    set_topics(token, username, args.repo, TOPICS_DEFAULT)
    print(f"      Topics set: {', '.join(TOPICS_DEFAULT)}")

    # Optional: branch protection (requires token with admin:repo scope)
    print(f"\n[Optional] Setting branch protection on 'main'...")
    try:
        set_branch_protection(token, username, args.repo, "main")
        print("      Branch protection enabled.")
    except SystemExit:
        print("      Skipped — token may lack admin:repo scope (add it to enable).")

    # Done
    print("\n" + "=" * 50)
    print("✅ Launch complete!")
    print(f"   Repository: {repo_url}")
    print(f"   CI:         {repo_url}/actions")
    print(f"   Releases:   {repo_url}/releases")
    print("\nNext steps:")
    print("  1. Update the CI badge URL in README.md with your real username.")
    print("  2. Post your Cfx.re release announcement (see docs/REPO_OWNER_GUIDE.md).")
    print("  3. Set up your Discord support server and link it in the repo About section.")
    print()


if __name__ == "__main__":
    main()
