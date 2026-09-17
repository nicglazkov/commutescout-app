#!/usr/bin/env bash
# Build the iOS app on the MacBook. Usage:
#   scripts/ios_build.sh sim        # generate the project and build for the simulator
#   scripts/ios_build.sh run        # install and launch on the booted simulator
#   scripts/ios_build.sh testflight # archive, export, upload to TestFlight
#   scripts/ios_build.sh test       # UI tests on the simulator
#   scripts/ios_build.sh test-device # UI tests on the paired iPhone (DEVICE=<udid>, unlocked)
#   scripts/ios_build.sh device     # archive, export Ad Hoc, install on the paired iPhone
#                                   # (DEVICE=<coredevice id>, profile "CommuteScout Drive AdHoc")
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
    # Manual signing with the build keychain that scripts/ios_signing.sh set
    # up: the login keychain is not reachable from a remote shell.
    BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"
    KC="$HOME/Library/Keychains/cs-build.keychain-db"
    PROFILE="CommuteScout Drive AppStore"
    security unlock-keychain -p "$(cat "$HOME/.appstoreconnect/cs-build/keychain.pw")" "$KC"
    xcodebuild -project CommuteScoutDrive.xcodeproj -scheme CommuteScoutDrive       -destination "generic/platform=iOS" -derivedDataPath "$DD" -skipMacroValidation       -archivePath "$DD/CommuteScoutDrive.xcarchive"       OTHER_CODE_SIGN_FLAGS="--keychain $KC"       CURRENT_PROJECT_VERSION="$BUILD" archive 2>&1 | tail -15
    cat > "$DD/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>M7D6YHVDNK</string>
  <key>uploadSymbols</key><true/>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key><dict>
    <key>com.commutescout.drive</key><string>$PROFILE</string>
  </dict>
</dict></plist>
EOF
    rm -rf "$DD/export"
    xcodebuild -exportArchive -archivePath "$DD/CommuteScoutDrive.xcarchive"       -exportOptionsPlist "$DD/export.plist" -exportPath "$DD/export"       OTHER_CODE_SIGN_FLAGS="--keychain $KC" 2>&1 | tail -8
    xcrun altool --upload-app -f "$DD"/export/*.ipa -t ios \
      --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tail -6
    ;;
  test)
    # UI tests on the simulator. ONLY_TESTING narrows the run (comma-separated).
    xcodebuild test -project CommuteScoutDrive.xcodeproj -scheme CommuteScoutDrive       -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath "$DD" -skipMacroValidation       $(for t in ${ONLY_TESTING//,/ }; do printf -- "-only-testing:CommuteScoutDriveUITests/%s " "$t"; done)       2>&1 | tee "$DD/last-sim-test.log" | grep -E "Test Case|passed|failed|error:|\*\* TEST" | tail -60
    ;;
  test-device)
    # XCTest on the phone: Debug builds sign with the Development profiles
    # from asc-setup/devcert.py (see project.yml). The phone must be
    # unlocked. ONLY_TESTING narrows the run, e.g. ONLY_TESTING=DriveUITests/testMarkerTapOpensCard.
    KC="$HOME/Library/Keychains/cs-build.keychain-db"
    DEVICE="${DEVICE:?set DEVICE to the phone UDID from: xcrun xctrace list devices}"
    security unlock-keychain -p "$(cat "$HOME/.appstoreconnect/cs-build/keychain.pw")" "$KC"
    xcodebuild test -project CommuteScoutDrive.xcodeproj -scheme CommuteScoutDrive       -destination "id=$DEVICE" -derivedDataPath "$DD" -skipMacroValidation       -resultBundlePath "$DD/device-tests-$(date +%H%M%S).xcresult"       $(for t in ${ONLY_TESTING//,/ }; do printf -- "-only-testing:CommuteScoutDriveUITests/%s " "$t"; done)       OTHER_CODE_SIGN_FLAGS="--keychain $KC" 2>&1 | tee "$DD/last-device-test.log" | grep -E "Test Case|passed|failed|error:|\*\* TEST" | tail -60
    ;;
  device)
    # Same archive as TestFlight, re-signed on export with the Ad Hoc
    # profile (distribution certificate plus the phone's UDID), then
    # installed over USB or Wi-Fi with devicectl. Minutes, not an hour.
    BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"
    KC="$HOME/Library/Keychains/cs-build.keychain-db"
    DEVICE="${DEVICE:?set DEVICE to the coredevice identifier from: xcrun devicectl list devices}"
    security unlock-keychain -p "$(cat "$HOME/.appstoreconnect/cs-build/keychain.pw")" "$KC"
    xcodebuild -project CommuteScoutDrive.xcodeproj -scheme CommuteScoutDrive \
      -destination "generic/platform=iOS" -derivedDataPath "$DD" -skipMacroValidation \
      -archivePath "$DD/CommuteScoutDrive.xcarchive" \
      OTHER_CODE_SIGN_FLAGS="--keychain $KC" \
      CURRENT_PROJECT_VERSION="$BUILD" archive 2>&1 | tail -15
    cat > "$DD/export-adhoc.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>release-testing</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>M7D6YHVDNK</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key><dict>
    <key>com.commutescout.drive</key><string>CommuteScout Drive AdHoc</string>
  </dict>
</dict></plist>
EOF
    rm -rf "$DD/export-adhoc"
    xcodebuild -exportArchive -archivePath "$DD/CommuteScoutDrive.xcarchive" \
      -exportOptionsPlist "$DD/export-adhoc.plist" -exportPath "$DD/export-adhoc" \
      OTHER_CODE_SIGN_FLAGS="--keychain $KC" 2>&1 | tail -8
    xcrun devicectl device install app --device "$DEVICE" "$DD"/export-adhoc/*.ipa 2>&1 | tail -4
    xcrun devicectl device process launch --terminate-existing --device "$DEVICE" com.commutescout.drive 2>&1 | tail -2
    ;;
esac
