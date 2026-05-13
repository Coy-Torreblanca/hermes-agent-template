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

# Create GBrain config with lowercase keys (matches GBrain's expected format)
cat <<EOF > "$GBRAIN_HOME/config.json"
{
  "openai_api_key": "$GBRAIN_OPENAI_KEY",
  "anthropic_api_key": "$GBRAIN_ANTHROPIC_KEY"
}
EOF

# Check if DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
    echo "[gbrain-start] ERROR: DATABASE_URL environment variable not set"
    echo "[gbrain-start] GBrain requires a Postgres database connection"
    exit 1
fi

# Wait for the database to be reachable (Railway Postgres pods can be asleep on cold start)
if [ -n "$DATABASE_URL" ]; then
    DB_HOST=$(echo "$DATABASE_URL" | sed -n 's|.*@\([^:/]*\).*|\1|p')
    DB_PORT=$(echo "$DATABASE_URL" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
    DB_PORT="${DB_PORT:-5432}"
    echo "[gbrain-start] Waiting for database at $DB_HOST:$DB_PORT..."
    for i in $(seq 1 30); do
        if timeout 3 bash -c "echo > /dev/tcp/$DB_HOST/$DB_PORT" 2>/dev/null; then
            echo "[gbrain-start] Database is reachable (attempt $i)"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "[gbrain-start] ERROR: Database unreachable after 30 attempts — giving up"
            exit 1
        fi
        sleep 2
    done
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
