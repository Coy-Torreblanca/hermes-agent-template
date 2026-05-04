#!/bin/bash
set -e

echo "[gbrain-mcp] Starting GBrain MCP server (stdio transport)..."

# Hermes spawns this script as a child process and communicates via stdin/stdout.
# The gbrain CLI resolves its own package root, so no cd /opt/gbrain needed.
exec gbrain serve

echo "[gbrain-mcp] MCP server stopped"
