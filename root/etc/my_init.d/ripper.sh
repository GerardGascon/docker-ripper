#!/bin/bash

# The container may be started with any UID/GID.
# Docker provides these through the process credentials.
UID_NOW=$(id -u)
GID_NOW=$(id -g)

echo "Running as UID=${UID_NOW} GID=${GID_NOW}"

# Copy default script
if [[ ! -f /config/ripper.sh ]]; then
    cp /ripper/ripper.sh /config/ripper.sh
fi

# MakeMKV config
export HOME=/config

mkdir -p "$HOME/.MakeMKV"

# Get current registration key
CURRENT_KEY=$(
    grep -oP 'app_Key = "\K[^"]+' \
    "$HOME/.MakeMKV/settings.conf" 2>/dev/null || true
)

# Get beta key
BETA_KEY=$(
    curl --silent --fail \
    'https://forum.makemkv.com/forum/viewtopic.php?f=5&t=1053' |
    grep -oP 'T-[\w\d@]{66}' |
    head -n1 || true
)

# Use supplied key or beta key
if [[ -n "${KEY:-}" ]]; then
    echo "Using MakeMKV key from KEY environment variable. ($KEY)"
else
    KEY="$BETA_KEY"
    echo "No custom key provided. Using MakeMKV beta key. ($KEY)"
fi

if [[ -z "$KEY" ]]; then
    echo "ERROR: Could not obtain a MakeMKV registration key"
    exit 1
fi

# Update settings if necessary
if [[ "$CURRENT_KEY" == "$KEY" ]]; then
    echo "MakeMKV key is already configured."
else
    echo "Updating MakeMKV registration key..."
    printf 'app_Key = "%s"\n' "$KEY" > "$HOME/.MakeMKV/settings.conf"
fi

# Register MakeMKV
echo "Registering MakeMKV..."
makemkvcon reg "$KEY"

echo "MakeMKV registration:"
makemkvcon info | grep -i registration || true

# abcde configuration
if [[ -n "${STORAGE_CD:-}" ]]; then
    echo "Using STORAGE_CD=$STORAGE_CD"
    sed -i \
        "/^OUTPUTDIR=/c\OUTPUTDIR=$STORAGE_CD" \
        /ripper/abcde.conf
else
    echo "STORAGE_CD not set; using default OUTPUTDIR."
fi

# Use custom abcde.conf if provided
if [[ -f /config/abcde.conf ]]; then
    echo "Using /config/abcde.conf"
    cp -f /config/abcde.conf /ripper/abcde.conf
fi

chmod +x /config/ripper.sh

echo "Starting ripper..."
exec /config/ripper.sh
