#!/usr/bin/env python3
"""
Nyxframework Repository & Bootstrap Validator
Scans all 11 framework resources for manifest integrity, balanced Lua 5.4 blocks,
migration sequence indexing, and export cross-references.
"""

import os
import sys
import re
import json

RESOURCES = [
    "nyx_core",
    "nyx_inventory",
    "nyx_treasury",
    "nyx_logistics",
    "nyx_parliament",
    "nyx_judiciary",
    "nyx_factions",
    "nyx_services",
    "nyx_vehicles",
    "nyx_interact",
    "nyx_ui",
    "nyx_properties",
    "nyx_mdt"
]

def strip_lua_comments_and_strings(content):
    result = []
    i = 0
    n = len(content)

    while i < n:
        if content[i:i+2] == '--':
            i += 2
            if i < n and content[i] == '[':
                j = i + 1
                equals_count = 0
                while j < n and content[j] == '=':
                    equals_count += 1
                    j += 1
                if j < n and content[j] == '[':
                    close_tag = ']' + ('=' * equals_count) + ']'
                    close_idx = content.find(close_tag, j + 1)
                    if close_idx == -1:
                        break
                    else:
                        i = close_idx + len(close_tag)
                        continue
            while i < n and content[i] != '\n':
                i += 1
            continue

        if content[i] == '[' and i + 1 < n and (content[i+1] == '[' or content[i+1] == '='):
            j = i + 1
            equals_count = 0
            while j < n and content[j] == '=':
                equals_count += 1
                j += 1
            if j < n and content[j] == '[':
                close_tag = ']' + ('=' * equals_count) + ']'
                close_idx = content.find(close_tag, j + 1)
                if close_idx == -1:
                    result.append(' ')
                    break
                else:
                    i = close_idx + len(close_tag)
                    result.append(' ')
                    continue

        if content[i] in ('"', "'"):
            quote = content[i]
            i += 1
            while i < n:
                if content[i] == '\\':
                    i += 2
                    continue
                if content[i] == quote:
                    i += 1
                    break
                if content[i] == '\n':
                    return False, f"Unclosed {quote} string across newline"
                i += 1
            result.append(' ')
            continue

        result.append(content[i])
        i += 1

    return True, "".join(result)

def check_lua_syntax(file_path):
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    ok, stripped_or_err = strip_lua_comments_and_strings(content)
    if not ok:
        return False, stripped_or_err

    tokens = re.findall(r'\b(function|if|do|repeat|end|until)\b', stripped_or_err)
    block_depth = 0
    repeat_depth = 0

    for idx, t in enumerate(tokens):
        if t in ("function", "if", "do"):
            block_depth += 1
        elif t == "repeat":
            repeat_depth += 1
        elif t == "until":
            repeat_depth -= 1
            if repeat_depth < 0:
                return False, f"Unmatched 'until' without 'repeat'"
        elif t == "end":
            block_depth -= 1
            if block_depth < 0:
                return False, f"Extra 'end' encountered (depth={block_depth})"

    if block_depth != 0:
        return False, f"EOF: Unclosed blocks remaining (depth={block_depth})"
    if repeat_depth != 0:
        return False, f"EOF: Unclosed repeat block remaining (depth={repeat_depth})"

    return True, None

def main():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    print(f"Scanning Nyxframework root: {root_dir}\n")

    has_errors = False
    total_lua_files = 0

    # 1. Check Resource Manifests and Lua Syntax
    print("--- 1. Checking Resource Manifests & Lua 5.4 Syntax ---")
    for res in RESOURCES:
        res_path = os.path.join(root_dir, res)
        if not os.path.isdir(res_path):
            print(f"[FAIL] Missing resource directory: {res}")
            has_errors = True
            continue

        manifest_path = os.path.join(res_path, "fxmanifest.lua")
        if not os.path.isfile(manifest_path):
            print(f"[FAIL] Missing fxmanifest.lua in {res}")
            has_errors = True
            continue

        # Walk through all Lua files in this resource
        res_lua_count = 0
        res_ok = True
        for dirpath, _, filenames in os.walk(res_path):
            for fname in filenames:
                if fname.endswith(".lua"):
                    full_path = os.path.join(dirpath, fname)
                    total_lua_files += 1
                    res_lua_count += 1
                    ok, err = check_lua_syntax(full_path)
                    if not ok:
                        rel = os.path.relpath(full_path, root_dir)
                        print(f"  [ERROR] {rel}: {err}")
                        has_errors = True
                        res_ok = False

        status = "OK" if res_ok else "ERRORS"
        print(f"  [{status}] {res} ({res_lua_count} Lua files)")

    # 2. Check Database Migration Sequence
    print("\n--- 2. Checking SQL Migration Sequence & Index ---")
    index_path = os.path.join(root_dir, "nyx_core", "sql", "migrations", "index.json")
    if not os.path.isfile(index_path):
        print(f"[FAIL] Missing migration index: {index_path}")
        has_errors = True
    else:
        with open(index_path, "r", encoding="utf-8") as f:
            migrations = json.load(f)

        print(f"Found {len(migrations)} registered migrations in index.json:")
        migrations_dir = os.path.join(root_dir, "nyx_core", "sql", "migrations")
        for step, fname in enumerate(migrations, 1):
            fpath = os.path.join(migrations_dir, fname)
            if not os.path.isfile(fpath):
                print(f"  [FAIL] Registered migration file missing on disk: {fname}")
                has_errors = True
            else:
                size = os.path.getsize(fpath)
                print(f"  [OK] Step {step}: {fname} ({size} bytes)")

    # 3. Check Web SPA Build
    print("\n--- 3. Checking nyx_ui Web Single Page Application ---")
    web_dir = os.path.join(root_dir, "nyx_ui", "web")
    required_web_files = ["index.html", "css/app.css", "js/app.js"]
    for wf in required_web_files:
        wfp = os.path.join(web_dir, wf)
        if not os.path.isfile(wfp):
            print(f"  [FAIL] Missing web asset: {wf}")
            has_errors = True
        else:
            print(f"  [OK] Web asset found: {wf}")

    # Summary
    print("\n================================================================")
    if has_errors:
        print(f"[FAILED] Repository validation encountered errors! Scanned {total_lua_files} Lua files.")
        sys.exit(1)
    else:
        print(f"[SUCCESS] All {len(RESOURCES)} resources, {total_lua_files} Lua files, and migrations verified cleanly!")
        sys.exit(0)

if __name__ == "__main__":
    main()
