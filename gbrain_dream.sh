#!/bin/bash
set -e

echo "[gbrain-dream] Running dream cycle..."

# Run the full dream cycle (8 phases)
# See ~/gbrain/docs/guides/cron-schedule.md for details
gbrain dream

echo "[gbrain-dream] Dream cycle complete"
