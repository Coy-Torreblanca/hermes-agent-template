#!/bin/bash
set -e

# Weekly maintenance at Sunday 3 AM UTC
while true; do
  # Calculate seconds until next Sunday 3 AM UTC
  now=$(date +%s)
  
  # Get next Sunday at 3 AM UTC
  # First, get today's date at 3 AM UTC
  today_3am=$(date -d '03:00 UTC' +%s)
  
  # If 3 AM has passed today, start from tomorrow
  if [ $today_3am -le $now ]; then
    # Get tomorrow's date
    tomorrow=$(date -d 'tomorrow 03:00 UTC' +%s)
    target=$tomorrow
  else
    target=$today_3am
  fi
  
  # Find the next Sunday
  target_day=$(date -d @$target +%w)
  days_until_sunday=$((7 - target_day))
  
  if [ $days_until_sunday -eq 0 ]; then
    # Already on Sunday, use this time
    target=$target
  else
    # Add days until Sunday
    target=$((target + (days_until_sunday * 86400)))
  fi
  
  sleep_time=$((target - now))
  
  echo "[gbrain-weekly-loop] Sleeping for $sleep_time seconds until Sunday 3 AM UTC"
  sleep $sleep_time
  
  /app/gbrain_weekly.sh
done
