#!/bin/bash
set -e

# Nightly dream cycle at 2 AM UTC
while true; do
  # Calculate seconds until 2 AM UTC
  now=$(date +%s)
  target=$(date -d '02:00 UTC' +%s)
  
  # If target time has passed today, schedule for tomorrow
  if [ $target -le $now ]; then
    target=$((target + 86400))
  fi
  
  sleep_time=$((target - now))
  
  echo "[gbrain-dream-loop] Sleeping for $sleep_time seconds until 2 AM UTC"
  sleep $sleep_time
  
  /app/gbrain_dream.sh
done
