#!/usr/bin/env bash
# make.sh: build the iOS app, run it in the simulator against `fakeamp`, and screenshot the main screen per skin.
#
# Usage: Docs/screenshots/make.sh [simulator name]      (default: iPhone 17)
# Needs: xcodegen, a booted-able simulator, nothing else. Starts its own fakeamp on 127.0.0.1:50001 unless one is
# already listening there. The app is launched with UserDefaults arguments (-skinID, -ampHost, ...) so each shot
# shows the wanted skin without touching the simulator's saved settings by hand.
set -euo pipefail
cd "$(dirname "$0")/../.."
SIM="${1:-iPhone 17}"
OUT="Docs/screenshots"
BUNDLE_ID="io.github.islee.hegelremote"

UDID=$(xcrun simctl list devices available | grep -F "$SIM (" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
[ -n "$UDID" ] || { echo "no simulator named '$SIM'" >&2; exit 1; }

if ! nc -z 127.0.0.1 50001 2>/dev/null; then
  swift build --product fakeamp >/dev/null
  .build/debug/fakeamp & FAKE=$!
  trap 'kill $FAKE 2>/dev/null || true' EXIT
  sleep 1
fi

[ "${SKIP_GENERATE:-}" = 1 ] || xcodegen generate >/dev/null
xcodebuild -scheme HegelRemote -destination "id=$UDID" -derivedDataPath .build/DerivedData build CODE_SIGNING_ALLOWED=NO -quiet
APP=$(find .build/DerivedData/Build/Products/Debug-iphonesimulator -maxdepth 1 -name 'HegelRemote.app' | head -1)

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

shoot() { # <skin> <control> <file>
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -skinID "$1" -volumeControl "$2" -ampHost 127.0.0.1 -ampPort 50001 -ampModelID h590 >/dev/null
  sleep 3
  xcrun simctl io "$UDID" screenshot "$OUT/$3" >/dev/null
  echo "wrote $OUT/$3"
}
shoot silver wheel iphone-silver-wheel.png
shoot black wheel iphone-black-wheel.png
shoot oled wheel iphone-oled-wheel.png
shoot silver slider iphone-silver-slider.png
xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
