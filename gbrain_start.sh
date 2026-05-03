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

# Import brain files from Syncthing folder if they exist
if [ -d "$BRAIN_PATH" ] && [ "$(find "$BRAIN_PATH" -name '*.md' -type f 2>/dev/null | wc -l)" -gt 0 ]; then
    echo "[gbrain-start] Found markdown files in $BRAIN_PATH, importing..."
    gbrain import "$BRAIN_PATH" --no-embed
    echo "[gbrain-start] Generating vector embeddings..."
    gbrain embed --stale
else
    echo "[gbrain-start] No markdown files found in $BRAIN_PATH, skipping import"
fi

echo "[gbrain-start] GBrain initialization complete"
