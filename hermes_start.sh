#!/bin/bash
set -e

# Ensure we have proper permissions
echo 'Starting Hermes initialization...'
echo "Running as: $(whoami)"
echo "HERMES_HOME: ${HERMES_HOME:-not set}"
echo "GBRAIN_HOME: ${GBRAIN_HOME:-not set}"

# Remove hermes config.
rm -rf /data/.hermes

# Mirror dashboard-ref-only's startup: create every directory hermes expects
# and seed a default config.yaml if the volume is empty. Without these,
# `hermes dashboard` endpoints that hit logs/, sessions/, cron/, etc. can fail
# with opaque errors even though no auth is actually involved.
mkdir -p /data/.hermes/cron /data/.hermes/sessions /data/.hermes/logs \
         /data/.hermes/memories /data/.hermes/skills /data/.hermes/pairing \
         /data/.hermes/hooks /data/.hermes/image_cache /data/.hermes/audio_cache \
         /data/.hermes/workspace

# Resolve variables in config.yaml and write directly to the destination
echo "Copying and processing config.yaml..."
if [ ! -f /app/hermes_setup/config.yaml ]; then
  echo "ERROR: /app/hermes_setup/config.yaml not found!"
  exit 1
fi
envsubst < /app/hermes_setup/config.yaml > /data/.hermes/config.yaml || {
  echo "ERROR: Failed to process config.yaml with envsubst"
  exit 1
}
echo "✓ config.yaml copied to /data/.hermes/config.yaml"

echo "Copying and processing hermes_env..."
if [ ! -f /app/hermes_setup/hermes_env ]; then
  echo "ERROR: /app/hermes_setup/hermes_env not found!"
  exit 1
fi
envsubst < /app/hermes_setup/hermes_env > /data/.hermes/.env || {
  echo "ERROR: Failed to process hermes_env with envsubst"
  exit 1
}
echo "✓ hermes_env copied to /data/.hermes/.env"

# Copy SOUL.md
echo "Copying SOUL.md..."
if [ ! -f /app/hermes_setup/SOUL.md ]; then
  echo "ERROR: /app/hermes_setup/SOUL.md not found!"
  exit 1
fi
cp /app/hermes_setup/SOUL.md /data/.hermes/SOUL.md
echo "✓ SOUL.md copied"

# Copy GBRAIN SystemPrompt.
echo "Copying USER.md (GBRAIN SystemPrompt)..."
if [ ! -f /opt/hermes-agent/skills/gbrain/second-brain/references/resolver.md ]; then
  echo "ERROR: /opt/hermes-agent/skills/gbrain/second-brain/references/resolver.md not found!"
  exit 1
fi
cp /opt/hermes-agent/skills/gbrain/second-brain/references/resolver.md /data/.hermes/memories/USER.md
echo "✓ USER.md copied"

# Redeploy base skills and plugins.
echo "Copying skills and plugins..."
if [ ! -d /opt/hermes-agent/skills/gbrain ]; then
  echo "ERROR: /opt/hermes-agent/skills/gbrain not found!"
  exit 1
fi
cp -r /opt/hermes-agent/skills/gbrain /data/.hermes/skills/gbrain
echo "✓ gbrain skills copied"

if [ ! -d /opt/hermes-agent/skills/coy ]; then
  echo "WARNING: /opt/hermes-agent/skills/coy not found, skipping"
else
  cp -r /opt/hermes-agent/skills/coy /data/.hermes/skills/coy
  echo "✓ coy skills copied"
fi

if [ ! -d /opt/hermes-agent/plugins ]; then
  echo "WARNING: /opt/hermes-agent/plugins not found, skipping"
else
  cp -r /opt/hermes-agent/plugins /data/.hermes/plugins
  echo "✓ plugins copied"
fi

# Verify critical files were created
echo ""
echo "Verifying critical files..."
if [ ! -f /data/.hermes/config.yaml ]; then
  echo "ERROR: config.yaml was not created at /data/.hermes/config.yaml"
  exit 1
fi
echo "✓ config.yaml verified"

if [ ! -f /data/.hermes/.env ]; then
  echo "ERROR: .env was not created at /data/.hermes/.env"
  exit 1
fi
echo "✓ .env verified"

echo ""
echo "File initialization complete!"
echo ""

# Clear any stale gateway PID file left over from the previous container.
# `hermes gateway` writes /data/.hermes/gateway.pid on start but does not
# remove it on SIGTERM. Since /data is a persistent volume, the file
# survives container restarts and causes every subsequent boot to exit with
# "ERROR gateway.run: PID file race lost to another gateway instance".
# No hermes process can be running at this point (we're pre-exec in a fresh
# container), so removing the file unconditionally is safe.
rm -f /data/.hermes/gateway.pid

# Sync cron jobs from declarative config (survives ephemeral redeploys)
echo "Syncing cron jobs..."
python3 /app/hermes_cron/sync.py

exec python /app/server.py
