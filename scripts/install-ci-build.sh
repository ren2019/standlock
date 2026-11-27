#!/bin/bash
set -euo pipefail

usage() {
  echo "usage: scripts/install-ci-build.sh <StandLock.zip> <ssh-host> <marketing-version> <build-number>" >&2
  echo "BACKUP_DIR overrides the default work/backup directory." >&2
}

fail() {
  echo "error: $*" >&2
  exit 1
}

status() {
  printf '%s\n' "$*"
}

if [ "$#" -ne 4 ]; then
  usage
  exit 2
fi

ZIP=$1
SSH_HOST=$2
VERSION=$3
BUILD=$4
BUNDLE_ID=com.yagizdokumaci.standlock
EXPECTED_DISPLAY_NAME=StandLock
TEAM_ID=F475N5N7V6
PLIST_BUDDY=/usr/libexec/PlistBuddy

[ -n "$SSH_HOST" ] || fail "ssh host must not be empty"
[ -n "$VERSION" ] || fail "marketing version must not be empty"
case "$BUILD" in
  ''|*[!0-9]*) fail "build number must be numeric" ;;
esac
[ -f "$ZIP" ] || fail "zip not found: $ZIP"

for tool in codesign ditto file scp shasum spctl ssh zipinfo; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
done
[ -x "$PLIST_BUDDY" ] || fail "PlistBuddy not found"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
ZIP=$(cd -- "$(dirname -- "$ZIP")" && pwd -P)/$(basename -- "$ZIP")

remote_bash() {
  local command="bash -s --"
  local argument
  for argument in "$@"; do
    command="$command $(printf '%q' "$argument")"
  done
  ssh -o BatchMode=yes -- "$SSH_HOST" "$command"
}

LOCAL_TMP=$(mktemp -d "${TMPDIR:-/tmp}/standlock-install.XXXXXX")
REMOTE_TMP=
BACKUP_PARTIAL=
cleanup() {
  rm -rf "$LOCAL_TMP"
  if [ -n "$BACKUP_PARTIAL" ]; then
    rm -f "$BACKUP_PARTIAL"
  fi
  if [ -n "$REMOTE_TMP" ]; then
    ssh -o BatchMode=yes -- "$SSH_HOST" "rm -rf -- $(printf '%q' "$REMOTE_TMP")" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! ARCHIVE_LIST=$(zipinfo -1 "$ZIP" 2>/dev/null); then
  fail "not a readable zip: $ZIP"
fi
ARCHIVE_ROOTS=$(printf '%s\n' "$ARCHIVE_LIST" | awk -F/ 'NF && $1 != "" {print $1}' | LC_ALL=C sort -u)
case "$ARCHIVE_ROOTS" in
  StandLock.app) ;;
  $'StandLock.app\n__MACOSX')
    METADATA_ROOTS=$(printf '%s\n' "$ARCHIVE_LIST" | awk -F/ '$1 == "__MACOSX" && $2 != "" {print $2}' | sort -u)
    [ "$METADATA_ROOTS" = "StandLock.app" ] || fail "zip must contain exactly one top-level StandLock.app"
    ;;
  *) fail "zip must contain exactly one top-level StandLock.app" ;;
esac

EXTRACT_DIR="$LOCAL_TMP/extracted"
mkdir -p "$EXTRACT_DIR"
ditto -x -k "$ZIP" "$EXTRACT_DIR"
APP="$EXTRACT_DIR/StandLock.app"
INFO="$APP/Contents/Info.plist"
[ -d "$APP" ] && [ -f "$INFO" ] || fail "StandLock.app has no readable Info.plist"
[ "$("$PLIST_BUDDY" -c 'Print :CFBundleIdentifier' "$INFO" 2>/dev/null)" = "$BUNDLE_ID" ] || fail "unexpected bundle identifier"
[ "$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$INFO" 2>/dev/null)" = "$VERSION" ] || fail "marketing version does not match the argument"
[ "$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$INFO" 2>/dev/null)" = "$BUILD" ] || fail "build number does not match the argument"
DISPLAY_NAME=$("$PLIST_BUDDY" -c 'Print :CFBundleDisplayName' "$INFO" 2>/dev/null || true)
[ "$DISPLAY_NAME" = "$EXPECTED_DISPLAY_NAME" ] || fail "unexpected display name"
EXECUTABLE_NAME=$("$PLIST_BUDDY" -c 'Print :CFBundleExecutable' "$INFO" 2>/dev/null)
EXECUTABLE="$APP/Contents/MacOS/$EXECUTABLE_NAME"
[ -x "$EXECUTABLE" ] || fail "app executable is missing or not executable"
file -b "$EXECUTABLE" | grep -q 'Mach-O' || fail "app executable is not Mach-O"
if ! CODESIGN_INFO=$(codesign -dvv "$APP" 2>&1); then
  fail "could not read app signature"
fi
printf '%s\n' "$CODESIGN_INFO" | grep -Fqx "Identifier=$BUNDLE_ID" || fail "unexpected signed bundle identifier"
printf '%s\n' "$CODESIGN_INFO" | grep -Fqx "TeamIdentifier=$TEAM_ID" || fail "unexpected signing team"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute "$APP"
ZIP_SHA256=$(shasum -a 256 < "$ZIP" | cut -d ' ' -f 1)
EXECUTABLE_SHA256=$(shasum -a 256 < "$EXECUTABLE" | cut -d ' ' -f 1)
status "Validated signed StandLock.app $VERSION ($BUILD)"

BACKUP_DIR=${BACKUP_DIR:-"$REPO_ROOT/work/backup"}
mkdir -p "$BACKUP_DIR"
if ! REMOTE_INFO=$(remote_bash <<'REMOTE_INFO_EOF'
set -euo pipefail
APP=${STANDLOCK_INSTALL_APP:-/Applications/StandLock.app}
INFO="$APP/Contents/Info.plist"
[ -d "$APP" ] && [ -f "$INFO" ]
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO" 2>/dev/null)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO" 2>/dev/null)
REMOTE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/standlock-install.XXXXXX")
printf '%s\n%s\n%s\n' "$VERSION" "$BUILD" "$REMOTE_TMP"
REMOTE_INFO_EOF
); then
  fail "could not read the installed app or create remote staging"
fi
REMOTE_VERSION=$(printf '%s\n' "$REMOTE_INFO" | sed -n '1p')
REMOTE_BUILD=$(printf '%s\n' "$REMOTE_INFO" | sed -n '2p')
REMOTE_TMP=$(printf '%s\n' "$REMOTE_INFO" | sed -n '3p')
[ -n "$REMOTE_VERSION" ] && [ -n "$REMOTE_TMP" ] || fail "invalid remote install metadata"
case "$REMOTE_BUILD" in
  ''|*[!0-9]*) fail "invalid remote build number" ;;
esac
SAFE_REMOTE_VERSION=${REMOTE_VERSION//[^A-Za-z0-9._-]/_}
BACKUP_PATH="$BACKUP_DIR/StandLock-${SAFE_REMOTE_VERSION}-${REMOTE_BUILD}.zip"

if [ -e "$BACKUP_PATH" ]; then
  [ -s "$BACKUP_PATH" ] || fail "backup exists but is empty: $BACKUP_PATH"
  status "Backup kept: $BACKUP_PATH"
else
  if ! remote_bash "$REMOTE_TMP" <<'REMOTE_BACKUP_EOF'
set -euo pipefail
APP=${STANDLOCK_INSTALL_APP:-/Applications/StandLock.app}
ditto -c -k --keepParent --rsrc --sequesterRsrc "$APP" "$1/StandLock-backup.zip"
REMOTE_BACKUP_EOF
  then
    fail "could not create the remote backup"
  fi
  BACKUP_PARTIAL="$BACKUP_PATH.part.$$"
  if ! scp -o BatchMode=yes -- "$SSH_HOST:$REMOTE_TMP/StandLock-backup.zip" "$BACKUP_PARTIAL"; then
    fail "could not download the remote backup"
  fi
  [ -s "$BACKUP_PARTIAL" ] || fail "downloaded backup is empty"
  mv "$BACKUP_PARTIAL" "$BACKUP_PATH"
  BACKUP_PARTIAL=
  status "Backup saved: $BACKUP_PATH"
fi

if ! scp -o BatchMode=yes -- "$ZIP" "$SSH_HOST:$REMOTE_TMP/StandLock.zip"; then
  fail "could not upload the signed app"
fi
status "Uploaded signed app"

if ! INSTALL_RESULT=$(remote_bash "$VERSION" "$BUILD" "$BUNDLE_ID" "$EXPECTED_DISPLAY_NAME" "$TEAM_ID" "$REMOTE_TMP" \
  "$ZIP_SHA256" "$EXECUTABLE_SHA256" <<'REMOTE_INSTALL_EOF'
set -euo pipefail
EXPECTED_VERSION=$1
EXPECTED_BUILD=$2
EXPECTED_BUNDLE_ID=$3
EXPECTED_DISPLAY_NAME=$4
EXPECTED_TEAM_ID=$5
REMOTE_TMP=$6
EXPECTED_ZIP_SHA256=$7
EXPECTED_EXECUTABLE_SHA256=$8
APP=${STANDLOCK_INSTALL_APP:-/Applications/StandLock.app}
PROCESS_PATTERN='^/Applications/StandLock[.]app/Contents/MacOS/StandLock$'
PLIST_BUDDY=/usr/libexec/PlistBuddy

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

verify_app() {
  local candidate=$1
  local info="$candidate/Contents/Info.plist"
  local codesign_info display_name executable_name executable
  [ -d "$candidate" ] && [ -f "$info" ] || fail "staged app or Info.plist is missing"
  [ "$("$PLIST_BUDDY" -c 'Print :CFBundleIdentifier' "$info" 2>/dev/null)" = "$EXPECTED_BUNDLE_ID" ] || fail "unexpected bundle identifier"
  [ "$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$info" 2>/dev/null)" = "$EXPECTED_VERSION" ] || fail "unexpected marketing version"
  [ "$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$info" 2>/dev/null)" = "$EXPECTED_BUILD" ] || fail "unexpected build number"
  display_name=$("$PLIST_BUDDY" -c 'Print :CFBundleDisplayName' "$info" 2>/dev/null || true)
  [ "$display_name" = "$EXPECTED_DISPLAY_NAME" ] || fail "unexpected display name"
  executable_name=$("$PLIST_BUDDY" -c 'Print :CFBundleExecutable' "$info" 2>/dev/null)
  executable="$candidate/Contents/MacOS/$executable_name"
  [ -x "$executable" ] || fail "app executable is missing or not executable"
  [ "$(shasum -a 256 < "$executable" | cut -d ' ' -f 1)" = "$EXPECTED_EXECUTABLE_SHA256" ] || fail "app executable does not match the CI artifact"
  file -b "$executable" | grep -q 'Mach-O' || fail "app executable is not Mach-O"
  if ! codesign_info=$(codesign -dvv "$candidate" 2>&1); then
    fail "could not read app signature"
  fi
  printf '%s\n' "$codesign_info" | grep -Fqx "Identifier=$EXPECTED_BUNDLE_ID" || fail "unexpected signed bundle identifier"
  printf '%s\n' "$codesign_info" | grep -Fqx "TeamIdentifier=$EXPECTED_TEAM_ID" || fail "unexpected signing team"
  codesign --verify --deep --strict "$candidate" || fail "signature verification failed"
  spctl --assess --type execute "$candidate" || fail "Gatekeeper assessment failed"
}

UNPACK_DIR="$REMOTE_TMP/unpacked"
UNPACKED_APP="$UNPACK_DIR/StandLock.app"
[ "$(shasum -a 256 < "$REMOTE_TMP/StandLock.zip" | cut -d ' ' -f 1)" = "$EXPECTED_ZIP_SHA256" ] || fail "transferred archive does not match the CI artifact"
mkdir -p "$UNPACK_DIR"
ditto -x -k "$REMOTE_TMP/StandLock.zip" "$UNPACK_DIR"
verify_app "$UNPACKED_APP"

STAGING_ROOT=${STANDLOCK_INSTALL_STAGING_ROOT:-/Applications}
STAGING=$(mktemp -d "$STAGING_ROOT/.standlock-install.XXXXXX")
STAGED_APP="$STAGING/StandLock.app"
PREVIOUS_APP="$STAGING/Previous.app"
INSTALL_SUCCEEDED=false
WAS_RUNNING=false
stop_production() {
  if pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
    pkill -TERM -f "$PROCESS_PATTERN" || true
    for _ in {1..50}; do
      pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1 || break
      sleep 0.1
    done
  fi
  ! pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1
}
cleanup_remote() {
  local result=$?
  trap - EXIT
  set +e
  if [ "$INSTALL_SUCCEEDED" != true ]; then
    result=1
    if [ -e "$PREVIOUS_APP" ]; then
      stop_production
      rm -rf "$APP"
      if ! mv "$PREVIOUS_APP" "$APP"; then
        printf 'error: could not restore previous StandLock.app; preserved at %s\n' "$PREVIOUS_APP" >&2
        rm -rf "$UNPACK_DIR"
        exit "$result"
      fi
    fi
    if [ "$WAS_RUNNING" = true ] && ! pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
      open -a "$APP" || printf 'error: could not relaunch the previous StandLock.app\n' >&2
    fi
  fi
  rm -rf "$UNPACK_DIR" "$STAGING"
  exit "$result"
}
trap cleanup_remote EXIT
trap 'exit 1' HUP INT TERM

ditto "$UNPACKED_APP" "$STAGED_APP"
verify_app "$STAGED_APP"
if pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
  WAS_RUNNING=true
fi
stop_production || fail "production StandLock is still running"

mv "$APP" "$PREVIOUS_APP"
mv "$STAGED_APP" "$APP"
verify_app "$APP"

open -a "$APP"
for _ in {1..100}; do
  pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1 && break
  sleep 0.1
done
pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1 || fail "StandLock did not start"
for _ in {1..20}; do
  pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1 || fail "StandLock exited during launch"
  sleep 0.1
done
INFO="$APP/Contents/Info.plist"
INSTALLED_BUNDLE_ID=$("$PLIST_BUDDY" -c 'Print :CFBundleIdentifier' "$INFO")
INSTALLED_VERSION=$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$INFO")
INSTALLED_BUILD=$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$INFO")
[ "$INSTALLED_BUNDLE_ID" = "$EXPECTED_BUNDLE_ID" ] && [ "$INSTALLED_VERSION" = "$EXPECTED_VERSION" ] && [ "$INSTALLED_BUILD" = "$EXPECTED_BUILD" ] || fail "installed version readback did not match"
printf '%s\n%s\n%s\n' "$INSTALLED_BUNDLE_ID" "$INSTALLED_VERSION" "$INSTALLED_BUILD"
INSTALL_SUCCEEDED=true
REMOTE_INSTALL_EOF
); then
  fail "remote installation failed; backup kept at $BACKUP_PATH"
fi
INSTALL_READBACK=$(printf '%s\n' "$INSTALL_RESULT" | tail -n 3)
INSTALLED_BUNDLE_ID=$(printf '%s\n' "$INSTALL_READBACK" | sed -n '1p')
INSTALLED_VERSION=$(printf '%s\n' "$INSTALL_READBACK" | sed -n '2p')
INSTALLED_BUILD=$(printf '%s\n' "$INSTALL_READBACK" | sed -n '3p')
[ "$INSTALLED_BUNDLE_ID" = "$BUNDLE_ID" ] && [ "$INSTALLED_VERSION" = "$VERSION" ] && [ "$INSTALLED_BUILD" = "$BUILD" ] || fail "installed version readback did not match"
status "Running $INSTALLED_BUNDLE_ID $INSTALLED_VERSION ($INSTALLED_BUILD)"
