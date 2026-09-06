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
