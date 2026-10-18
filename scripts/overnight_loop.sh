#!/usr/bin/env bash
# ==============================================================================
#                 NYXFRAMEWORK AUTONOMOUS OVERNIGHT RUNNER (Bash)
# ==============================================================================
# Continuously executes an autonomous agent turn, validates changes with verify.sh,
# commits successful iterations, and rolls back broken syntax/manifests.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

BRANCH_NAME="${BRANCH_NAME:-agent/overnight-experiments}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-5}"
MAX_CYCLES="${MAX_CYCLES:-0}"
LOG_FILE="$ROOT_DIR/agent_loop.log"
STOP_FILE="$ROOT_DIR/STOP_LOOP"

echo "=== Setting Up Dedicated Autonomous Branch: $BRANCH_NAME ==="
git checkout -B "$BRANCH_NAME"

# Locate Agent CLI
AGENT_BIN=""
if [ -n "$CUSTOM_AGENT_COMMAND" ]; then
    echo "Using Custom Agent Command: $CUSTOM_AGENT_COMMAND"
elif command -v agy >/dev/null 2>&1; then
    AGENT_BIN="agy"
    echo "Detected Google Antigravity CLI: $AGENT_BIN"
elif command -v agent-canvas >/dev/null 2>&1; then
    AGENT_BIN="agent-canvas"
elif command -v openhands-cli >/dev/null 2>&1; then
    AGENT_BIN="openhands-cli"
else
    AGENT_BIN="agy"
fi

AGENT_PROMPT="Read AGENT_TASK.md. Pick the highest priority uncompleted task in the Task Backlog (or plan and implement the next feature from Tervek.md if backlog is empty). Implement it completely: write clean Lua 5.4 code, update fxmanifest.lua, add database migration if required, run tests, and update AGENT_TASK.md marking the task completed."

echo "================================================================"
echo "         STARTING AUTONOMOUS OVERNIGHT DEVELOPMENT LOOP          "
echo " Repository : $ROOT_DIR"
echo " Branch     : $BRANCH_NAME"
echo " Log File   : $LOG_FILE"
echo " Stop Signal: Create a file named 'STOP_LOOP' to exit gracefully"
echo "================================================================"

CYCLE_COUNT=0

while true; do
    if [ -f "$STOP_FILE" ]; then
        echo "[STOP] Detected 'STOP_LOOP' signal file. Exiting cleanly."
        rm -f "$STOP_FILE"
        break
    fi

    CYCLE_COUNT=$((CYCLE_COUNT + 1))
    TIMESTAMP="$(date +'%Y-%m-%d %H:%M:%S')"
    echo "[$TIMESTAMP] [Cycle $CYCLE_COUNT] >>> Starting Agent Iteration <<<" | tee -a "$LOG_FILE"

    # 1. Execute Agent Headless
    AGENT_EXIT=0
    if [ -n "$CUSTOM_AGENT_COMMAND" ]; then
        eval "$CUSTOM_AGENT_COMMAND" >> "$LOG_FILE" 2>&1 || AGENT_EXIT=$?
    elif [ "$AGENT_BIN" = "agy" ]; then
        agy --print "$AGENT_PROMPT" --dangerously-skip-permissions --mode auto >> "$LOG_FILE" 2>&1 || AGENT_EXIT=$?
    else
        "$AGENT_BIN" --headless --message "$AGENT_PROMPT" >> "$LOG_FILE" 2>&1 || AGENT_EXIT=$?
    fi

    if [ $AGENT_EXIT -ne 0 ]; then
        echo "[$TIMESTAMP] Agent exited with code $AGENT_EXIT. Stopping loop (token/quota limit or crash)." | tee -a "$LOG_FILE"
        break
    fi

    # 2. Run Verification
    echo "[$TIMESTAMP] Running automated validation checks..."
    if bash "$SCRIPT_DIR/verify.sh" >> "$LOG_FILE" 2>&1; then
        echo "[$TIMESTAMP] Verification PASSED!"
        if [ -n "$(git status --porcelain)" ]; then
            echo "[$TIMESTAMP] Committing verified changes..."
            git add -A
            COMMIT_MSG="autonomous: feature iteration $TIMESTAMP (cycle $CYCLE_COUNT)"
            git commit -m "$COMMIT_MSG" >> "$LOG_FILE" 2>&1
            if git remote | grep -q "^origin$"; then
                echo "[$TIMESTAMP] Pushing to remote branch $BRANCH_NAME..."
                git push origin "$BRANCH_NAME" >> "$LOG_FILE" 2>&1 || true
            fi
            echo "[$TIMESTAMP] Successfully committed: $COMMIT_MSG" >> "$LOG_FILE"
        else
            echo "[$TIMESTAMP] Verification passed, but no working tree modifications detected."
        fi
    else
        echo "[$TIMESTAMP] Verification FAILED! Rolling back broken changes..."
        echo "[$TIMESTAMP] [ROLLBACK] Verification failed. Reverting dirty working tree..." >> "$LOG_FILE"
        git reset --hard HEAD >> "$LOG_FILE" 2>&1
        git clean -fd >> "$LOG_FILE" 2>&1
        echo "[$TIMESTAMP] Working tree reset to clean HEAD."
    fi

    if [ "$MAX_CYCLES" -gt 0 ] && [ "$CYCLE_COUNT" -ge "$MAX_CYCLES" ]; then
        echo "[DONE] Reached maximum requested cycles ($MAX_CYCLES). Stopping."
        break
    fi

    echo "[$TIMESTAMP] Cycle $CYCLE_COUNT finished. Cooldown pause (${COOLDOWN_SECONDS}s)..."
    sleep "$COOLDOWN_SECONDS"
done

echo "=== Autonomous Development Loop Terminated ==="
