#!/bin/bash
set -e

echo "[gbrain-weekly] Running weekly maintenance (doctor + embed)..."

# Run doctor check
gbrain doctor --json

# Embed stale documents
gbrain embed --stale

echo "[gbrain-weekly] Weekly maintenance complete"
