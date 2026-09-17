#!/usr/bin/env bash
# Build the iOS app on the MacBook. Usage:
#   scripts/ios_build.sh sim        # generate the project and build for the simulator
#   scripts/ios_build.sh run        # install and launch on the booted simulator
#   scripts/ios_build.sh testflight # archive, export, upload to TestFlight
set -euo pipefail
cd "$(dirname "$0")/../ios"
export PATH="/opt/homebrew/bin:$PATH" LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
ASC_KEY_ID="${ASC_KEY_ID:-N9LBMSST5A}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-ff12bb27-b0e6-4510-a862-0e199730f09e}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
DD="$HOME/src/csdrive-dd"
SIM="${SIM:-iPhone 17}"

xcodegen generate --quiet
case "${1:-sim}" in
  sim)
    xcodebuild -project CommuteScoutDrive.xcodeproj -scheme CommuteScoutDrive \
      -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath "$DD" \
      -skipMacroValidation build 2>&1 | tail -20
    ;;
  run)
    xcrun simctl boot "$SIM" 2>/dev/null || true
    xcrun simctl install booted "$DD/Build/Products/Debug-iphonesimulator/CommuteScoutDrive.app"
    xcrun simctl launch booted com.commutescout.drive
    ;;
  testflight)
    BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"
    xcodebuild -project CommuteScoutDrive.xcodeproj -scheme CommuteScoutDrive \
      -destination "generic/platform=iOS" -derivedDataPath "$DD" -skipMacroValidation \
      -archivePath "$DD/CommuteScoutDrive.xcarchive" \
      -allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" \
      -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
      CURRENT_PROJECT_VERSION="$BUILD" archive 2>&1 | tail -15
    cat > "$DD/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>M7D6YHVDNK</string>
  <key>uploadSymbols</key><true/>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
EOF
    rm -rf "$DD/export"
    xcodebuild -exportArchive -archivePath "$DD/CommuteScoutDrive.xcarchive" \
      -exportOptionsPlist "$DD/export.plist" -exportPath "$DD/export" \
      -allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" \
      -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" 2>&1 | tail -8
    xcrun altool --upload-app -f "$DD/export/CommuteScoutDrive.ipa" -t ios \
      --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tail -6
    ;;
esac
