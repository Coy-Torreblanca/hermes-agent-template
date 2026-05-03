#!/bin/bash
set -e

echo "[gbrain-mcp] Starting GBrain MCP server..."

# The MCP server uses stdio transport, so it communicates via stdin/stdout
# Hermes will connect to this server via the MCP protocol
cd /opt/gbrain
bun run src/cli.ts serve

echo "[gbrain-mcp] MCP server stopped"
