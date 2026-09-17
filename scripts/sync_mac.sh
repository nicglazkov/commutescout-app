#!/usr/bin/env bash
# Copy the working tree to the MacBook for iOS builds (git-tracked files
# plus new ones, minus build output). Usage: scripts/sync_mac.sh
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${MAC:-nic@100.87.92.84}"
ssh "$HOST" 'mkdir -p ~/src/commutescout-app'
tar --exclude=.git --exclude='*.xcodeproj' --exclude=android/build --exclude=android/.gradle \
    --exclude=android/app/build -cf - . | ssh "$HOST" 'tar -xf - -C ~/src/commutescout-app'
echo "synced to $HOST:~/src/commutescout-app"
