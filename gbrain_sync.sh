#!/bin/bash
set -e

BRAIN_PATH="${SYNCTHING_FOLDER_PATH:-/data/syncthing/Sync}"

echo "[gbrain-sync] Running live sync..."
echo "    Brain Path: $BRAIN_PATH"

# Sync brain repo and embed stale documents
gbrain sync --repo "$BRAIN_PATH"
gbrain embed --stale

echo "[gbrain-sync] Sync complete"
