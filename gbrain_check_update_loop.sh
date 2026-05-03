#!/bin/bash
set -e

# Daily update check at 1 AM UTC
while true; do
  # Calculate seconds until 1 AM UTC
  now=$(date +%s)
  target=$(date -d '01:00 UTC' +%s)
  
  # If target time has passed today, schedule for tomorrow
  if [ $target -le $now ]; then
    target=$((target + 86400))
  fi
  
  sleep_time=$((target - now))
  
  echo "[gbrain-check-update-loop] Sleeping for $sleep_time seconds until 1 AM UTC"
  sleep $sleep_time
  
  /app/gbrain_check_update.sh
done
