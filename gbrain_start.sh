#!/bin/bash
set -e

GBRAIN_HOME="${GBRAIN_HOME:-/data/.gbrain}"
BRAIN_PATH="${SYNCTHING_FOLDER_PATH:-/data/syncthing/Sync}"

# Create necessary directories
mkdir -p "$GBRAIN_HOME"
mkdir -p "$BRAIN_PATH"

echo "[gbrain-start] Initializing GBrain..."
echo "    Home: $GBRAIN_HOME"
echo "    Brain Path: $BRAIN_PATH"

# Check if DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
    echo "[gbrain-start] ERROR: DATABASE_URL environment variable not set"
    echo "[gbrain-start] GBrain requires a Postgres database connection"
    exit 1
fi

# Initialize GBrain with Postgres database if not already initialized
if [ ! -f "$GBRAIN_HOME/config.json" ]; then
    echo "[gbrain-start] Running gbrain init with Postgres..."
    gbrain init --url "$DATABASE_URL" --json
else
    echo "[gbrain-start] GBrain config already exists at $GBRAIN_HOME/config.json"
fi

# Run doctor check
echo "[gbrain-start] Running gbrain doctor..."
gbrain doctor --json

echo "[gbrain-start] GBrain initialization complete"
