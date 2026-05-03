#!/bin/bash
set -e

echo "[gbrain-check-update] Checking for GBrain updates (daily)..."

# Check for updates without auto-installing
gbrain check-update --json

echo "[gbrain-check-update] Update check complete"
