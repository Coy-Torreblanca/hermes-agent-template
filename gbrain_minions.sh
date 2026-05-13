#!/bin/bash
set -e

echo "[gbrain-minions] Starting GBrain Minions worker..."

# The Minions worker processes the gbrain job queue (autopilot-cycle,
# embed, backlinks, lint, purge, etc.). It must run persistently so
# submitted jobs don't pile up in "waiting" forever.
exec gbrain jobs work

echo "[gbrain-minions] Worker stopped"
