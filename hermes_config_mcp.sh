#!/bin/bash
set -e

HERMES_HOME="${HERMES_HOME:-/data/.hermes}"
CONFIG_PATH="$HERMES_HOME/config.yaml"

echo "[hermes-config-mcp] Updating Hermes config with GBrain MCP integration..."

# Check if config exists
if [ ! -f "$CONFIG_PATH" ]; then
    echo "[hermes-config-mcp] Config not found at $CONFIG_PATH, skipping MCP setup"
    exit 0
fi

# Check if MCP section already exists
if grep -q "mcp:" "$CONFIG_PATH"; then
    echo "[hermes-config-mcp] MCP section already configured"
    exit 0
fi

# Append MCP configuration to config.yaml
cat >> "$CONFIG_PATH" << 'MCPEOF'

# GBrain MCP Server Integration
mcp:
  servers:
    gbrain:
      command: /app/gbrain_mcp.sh
      env:
        DATABASE_URL: ${DATABASE_URL}
        GBRAIN_HOME: ${GBRAIN_HOME}
MCPEOF

echo "[hermes-config-mcp] GBrain MCP server configured in Hermes config"
