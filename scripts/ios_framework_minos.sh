#!/bin/bash
# Xcode build phase (see ios/project.yml): for each framework embedded in
# the app, set MinimumOSVersion in its Info.plist to the minos its binary
# was built for, and sign it again when that changed anything. A plist
# below the binary's minos fails App Store Connect with ITMS-90208.
set -euo pipefail

dir="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
[ -d "$dir" ] || exit 0

for fw in "$dir"/*.framework; do
  [ -d "$fw" ] || continue
  name=$(basename "$fw" .framework)
  bin="$fw/$name"
  plist="$fw/Info.plist"
  [ -f "$bin" ] && [ -f "$plist" ] || continue
  # The highest minos over the binary's architectures.
  minos=$(xcrun vtool -show-build "$bin" 2>/dev/null | awk '$1 == "minos" { print $2 }' | sort -V | tail -1)
  [ -n "$minos" ] || continue
  current=$(/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$plist" 2>/dev/null || true)
  [ "$current" = "$minos" ] && continue
  if [ -n "$current" ]; then
    /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion $minos" "$plist"
  else
    /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string $minos" "$plist"
  fi
  echo "$name: MinimumOSVersion ${current:-unset} -> $minos"
  if [ "${CODE_SIGNING_ALLOWED:-YES}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    # OTHER_CODE_SIGN_FLAGS carries the build keychain on release builds.
    # shellcheck disable=SC2086
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" ${OTHER_CODE_SIGN_FLAGS:-} \
      --preserve-metadata=identifier,flags "$fw"
  fi
done
