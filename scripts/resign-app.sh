#!/bin/bash
set -euo pipefail

APP="$RUNNER_TEMP/export/StandLock.app"
FW="$APP/Contents/Frameworks/Sparkle.framework"

SIGN_FLAGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" == - ]]; then
  SIGN_FLAGS+=(--timestamp=none)
else
  SIGN_FLAGS+=(--timestamp --options runtime)
fi

codesign "${SIGN_FLAGS[@]}" "$FW/Versions/Current/XPCServices/Downloader.xpc"
codesign "${SIGN_FLAGS[@]}" "$FW/Versions/Current/XPCServices/Installer.xpc"
codesign "${SIGN_FLAGS[@]}" "$FW/Versions/Current/Updater.app"
codesign "${SIGN_FLAGS[@]}" "$FW/Versions/Current/Autoupdate"
codesign "${SIGN_FLAGS[@]}" "$FW"
# --force drops the existing entitlements, so pass them again for the app.
codesign "${SIGN_FLAGS[@]}" --entitlements StandLock/StandLock.entitlements "$APP"
