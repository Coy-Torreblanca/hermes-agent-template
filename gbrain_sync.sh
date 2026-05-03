#!/bin/bash
set -e

BRAIN_PATH="${SYNCTHING_FOLDER_PATH:-/data/syncthing/Sync}"

echo "[gbrain-sync] Running live sync..."
echo "    Brain Path: $BRAIN_PATH"

# Sync brain: use git-aware sync if the folder is a repo, otherwise plain import
if [ -d "$BRAIN_PATH/.git" ]; then
    echo "[gbrain-sync] Git repo detected — using incremental sync"
    gbrain sync --repo "$BRAIN_PATH"
else
    echo "[gbrain-sync] Plain directory — using import (idempotent, skips unchanged files)"
    gbrain import "$BRAIN_PATH" --no-embed
fi
gbrain embed --stale

echo "[gbrain-sync] Sync complete"
