#!/usr/bin/env bash
# ==============================================================================
#                 NYXFRAMEWORK AUTOMATED VERIFICATION SCRIPT (Bash)
# ==============================================================================
# Validates manifest declarations, balanced Lua 5.4 block syntax, migration indices,
# and SPA web assets. Returns exit code 0 on success, 1 on failure.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Detect Python
if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
else
    echo "[ERROR] Python 3 was not found in system PATH!"
    exit 1
fi

VALIDATOR_SCRIPT="$SCRIPT_DIR/validator.py"
if [ ! -f "$VALIDATOR_SCRIPT" ]; then
    VALIDATOR_SCRIPT="$ROOT_DIR/FiveM/scripts/bootstrap_validator.py"
fi

# Run core validator
$PYTHON_BIN "$VALIDATOR_SCRIPT"

# Optional Luacheck
if command -v luacheck >/dev/null 2>&1; then
    echo "Running luacheck on FiveM resources..."
    luacheck "$ROOT_DIR/FiveM" --std "lua54" --no-color
fi

echo -e "\n>>> [VERIFICATION PASSED] All tests and assertions clean. Safe to commit. <<<"
exit 0
