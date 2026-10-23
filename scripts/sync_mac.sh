#!/usr/bin/env bash
# Copy the working tree to the MacBook for iOS builds (git-tracked files
# plus new ones, minus build output). Usage: MAC=user@host scripts/sync_mac.sh
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${MAC:?set MAC to the build Mac, as user@host}"
ssh "$HOST" 'mkdir -p ~/src/commutescout-app'
tar --exclude=.git --exclude='*.xcodeproj' --exclude=android/build --exclude=android/.gradle \
    --exclude=android/app/build -cf - . | ssh "$HOST" 'tar -xf - -C ~/src/commutescout-app'
echo "synced to $HOST:~/src/commutescout-app"
