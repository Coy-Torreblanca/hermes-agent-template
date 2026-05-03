#!/bin/bash
set -e

CONFIG="/data/syncthing/config.xml"
FOLDER_PATH="${SYNCTHING_FOLDER_PATH:-/data/syncthing/Sync}"
FOLDER_LABEL="${SYNCTHING_FOLDER_LABEL:-Default Folder}"
DEVICE_ID="${SYNCTHING_DEVICE_ID:-}"

# Create the sync folder early so it exists before Syncthing starts
mkdir -p "$FOLDER_PATH"

# If no device ID is provided, skip config generation
if [ -z "$DEVICE_ID" ]; then
    echo "[syncthing-config] SYNCTHING_DEVICE_ID not set — skipping auto-config; Syncthing will start with defaults."
    exit 0
fi

echo "[syncthing-config] Generating Syncthing config..."
echo "    Folder: $FOLDER_PATH"
echo "    Label:  $FOLDER_LABEL"
echo "    Device: $DEVICE_ID"

cat > "$CONFIG" << XMLEOF
<configuration version="36">
    <folder id="default" label="$FOLDER_LABEL" path="$FOLDER_PATH" type="sendreceive" rescanIntervalS="3600" fsWatcherEnabled="true" fsWatcherDelayS="10" ignorePerms="false" autoNormalize="true">
        <device id="$DEVICE_ID" introducedBy=""></device>
    </folder>
    <device id="$DEVICE_ID" name="remote" compression="metadata" introducer="false" skipIntroductionRemovals="false" introducedBy="">
        <address>dynamic</address>
        <paused>false</paused>
    </device>
    <gui enabled="true" tls="false" debugging="false">
        <address>0.0.0.0:8384</address>
    </gui>
    <options>
        <localAnnounceEnabled>true</localAnnounceEnabled>
        <globalAnnounceEnabled>true</globalAnnounceEnabled>
        <relaysEnabled>true</relaysEnabled>
    </options>
</configuration>
XMLEOF

echo "[syncthing-config] Config written to $CONFIG"
