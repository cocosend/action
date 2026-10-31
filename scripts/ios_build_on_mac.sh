#!/usr/bin/env bash
# Runs a real Apple-SDK build + integration/UI tests + simulator screenshot.
# This script must execute ON macOS with full Xcode and XcodeGen installed.
# A simulator build is not a signed iPhone IPA or proof of physical-device audio.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'ERROR: macOS is required. This command cannot build native iOS apps on Linux.' >&2
  exit 2
fi
for command in xcrun xcodebuild xcodegen python3 ditto; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ERROR: Missing $command. Install full Xcode / XcodeGen before building." >&2
    exit 3
  fi
done
OUTPUT="${MIXAUTO_APP_BUILD_OUTPUT:-$PWD/ios-build-results}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
DERIVED="$OUTPUT/DerivedData"
XCRESULT="$OUTPUT/MixAuto-Native-Tests.xcresult"
rm -rf "$XCRESULT"  # xcodebuild does not overwrite result bundles
xcodegen generate --spec project.yml
set -o pipefail
xcodebuild -project DJTrackBuilderMixAutoPro.xcodeproj \
  -scheme DJTrackBuilderMixAutoPro -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$OUTPUT/xcodebuild-build.log"
xcrun simctl list devices available -j > "$OUTPUT/available-simulators.json"
SIM_ID=$(python3 - "$OUTPUT/available-simulators.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))['devices']
for runtime, values in r.items():
    for x in values:
        if x.get('isAvailable', True) and 'iPhone' in x['name']:
            print(x['udid']); sys.exit(0)
sys.exit('No iPhone simulator is installed. Download one in Xcode > Settings > Platforms.')
PY
)
if ! xcrun simctl boot "$SIM_ID" 2>"$OUTPUT/simulator-boot.log"; then
  if ! xcrun simctl list devices | grep -E "${SIM_ID}.*Booted" >/dev/null; then
    cat "$OUTPUT/simulator-boot.log" >&2
    exit 4
  fi
fi
xcrun simctl bootstatus "$SIM_ID" -b
xcodebuild -project DJTrackBuilderMixAutoPro.xcodeproj \
  -scheme DJTrackBuilderMixAutoPro -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$DERIVED" -resultBundlePath "$XCRESULT" \
  -parallel-testing-enabled NO -configuration Debug \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$OUTPUT/xcodebuild-test.log"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/DJTrackBuilderMixAutoPro.app"
if [[ ! -d "$APP" ]]; then echo "ERROR: Successful tests but missing .app at $APP" >&2; exit 5; fi
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/MixAuto-iOS-Simulator-Unsigned.zip"
xcrun simctl install "$SIM_ID" "$APP"
xcrun simctl launch "$SIM_ID" com.artss.trackbuilder.mixautopro
sleep 2
xcrun simctl io "$SIM_ID" screenshot "$OUTPUT/MixAuto-Original-Canva-Cockpit.png"
cat <<RESULT
SUCCESS: Apple SDK native build + AudioGraphIntegrationTests + UI smoke.
Simulator app: $OUTPUT/MixAuto-iOS-Simulator-Unsigned.zip
XCTest evidence: $XCRESULT
Simulator screenshot: $OUTPUT/MixAuto-Original-Canva-Cockpit.png
This is NOT a signed IPA, TestFlight invitation or physical iPhone audio QA.
RESULT
