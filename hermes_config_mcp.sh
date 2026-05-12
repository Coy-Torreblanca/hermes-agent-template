#!/bin/bash
set -e

HERMES_HOME="${HERMES_HOME:-/data/.hermes}"
CONFIG_PATH="$HERMES_HOME/config.yaml"

echo "[hermes-config-mcp] Updating Hermes config with GBrain MCP integration..."

echo "[hermes-config-mcp] Waiting for Hermes to create config at $CONFIG_PATH..."

# Wait up to 30 seconds for the file to appear
MAX_RETRIES=30
COUNT=0
while [ ! -f "$CONFIG_PATH" ]; do
    if [ "$COUNT" -eq "$MAX_RETRIES" ]; then
        echo "[hermes-config-mcp] ERROR: Config not found after ${MAX_RETRIES}s. Exiting."
        exit 1
    fi
    sleep 1
    ((COUNT++))
done

echo "[hermes-config-mcp] Config found! Proceeding with MCP setup..."

# Check if config exists
if [ ! -f "$CONFIG_PATH" ]; then
    echo "[hermes-config-mcp] Config not found at $CONFIG_PATH, skipping MCP setup"
    exit 0
fi

# Validate required env vars
if [ -z "$DATABASE_URL" ]; then
    echo "[hermes-config-mcp] WARNING: DATABASE_URL not set — GBrain MCP may fail to connect to DB"
fi
if [ -z "$GBRAIN_HOME" ]; then
    echo "[hermes-config-mcp] GBRAIN_HOME not set, using default /data/.gbrain"
    GBRAIN_HOME="/data/.gbrain"
fi

# Remove any existing MCP section (so we rewrite cleanly on every boot)
if grep -qE "^mcp(_servers)?:" "$CONFIG_PATH"; then
    echo "[hermes-config-mcp] Removing previous MCP section..."
    awk 'BEGIN{skip=0}
         /^mcp(_servers)?:/{skip=1; next}
         skip && /^[a-z]/ {skip=0}
         !skip' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp"
    mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
fi

# Append MCP configuration with EXPANDED env vars (unquoted heredoc = expansion)
cat >> "$CONFIG_PATH" << MCPEOF

# GBrain MCP Server Integration (stdio transport — Hermes spawns on demand)
mcp_servers:
  gbrain:
    command: "bun"
    args:
      - "--cwd=/opt/gbrain"
      - "run"
      - "src/cli.ts"
      - "serve"
    env:
      DATABASE_URL: "${DATABASE_URL}"
      GBRAIN_HOME: "${GBRAIN_HOME}"
      BRAIN_PATH: "${SYNCTHING_FOLDER_PATH:-/data/syncthing/Sync}"
    timeout: 60
    connect_timeout: 30
MCPEOF

echo "[hermes-config-mcp] GBrain MCP server configured in Hermes config"
echo "[hermes-config-mcp]   DATABASE_URL:  ${DATABASE_URL:+set (${#DATABASE_URL} chars)}"
echo "[hermes-config-mcp]   GBRAIN_HOME:   ${GBRAIN_HOME}"
