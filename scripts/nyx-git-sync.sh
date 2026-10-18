#!/usr/bin/env bash
set -e

WORK_TREE="/opt/nyxframework"
GIT_DIR="/var/repo/nyxframework.git"
RESOURCES_DIR="/opt/fivem/server-data/resources/[nyx]"
SERVER_CFG="/opt/fivem/server-data/server.cfg"
LOG_FILE="/var/log/nyx-git-deploy.log"

# If an upstream remote exists, fetch changes
if git --git-dir="$GIT_DIR" remote | grep -q "^upstream$"; then
    git --git-dir="$GIT_DIR" fetch upstream
    REMOTE_HASH=$(git --git-dir="$GIT_DIR" rev-parse upstream/agent/overnight-experiments 2>/dev/null) || REMOTE_HASH=$(git --git-dir="$GIT_DIR" rev-parse upstream/master 2>/dev/null)
    LOCAL_HASH=$(git --git-dir="$GIT_DIR" rev-parse HEAD 2>/dev/null) || LOCAL_HASH=""
    if [ "$REMOTE_HASH" != "$LOCAL_HASH" ] && [ -n "$REMOTE_HASH" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Auto-sync detected new upstream commit: $REMOTE_HASH" | tee -a "$LOG_FILE"
        git --work-tree="$WORK_TREE" --git-dir="$GIT_DIR" checkout -f "$REMOTE_HASH"
        rsync -av --delete --exclude 'server.cfg' --exclude 'server.cfg.example' --exclude 'scripts' --exclude '__pycache__' "$WORK_TREE/FiveM/" "$RESOURCES_DIR/"
        chmod -R 755 "$RESOURCES_DIR"
        systemctl restart fivem.service
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Upstream auto-sync applied successfully." | tee -a "$LOG_FILE"
    fi
fi
