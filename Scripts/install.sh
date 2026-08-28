#!/bin/bash
# Build and install into /Applications. Run it again to update.
#
#   Scripts/install.sh
#
# Signs with Developer ID but does not notarize. That is fine for a locally
# built app — Gatekeeper only quarantines things that arrive from elsewhere —
# and the stable signature is what matters: TCC keys the Reminders permission
# to the code signature, so an ad-hoc build has to be re-authorised every
# single time, while this one is granted once.
set -euo pipefail

SIGN_IDENTITY="Developer ID Application"
TEAM_ID="U4K77TMBRU"
APP_NAME="QuickReminders"
BUNDLE_ID="com.nicolasblunck.QuickReminders"
DEST="/Applications/$APP_NAME.app"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.release/install"
cd "$REPO_ROOT"

echo "==> Generating project"
xcodegen generate >/dev/null

echo "==> Building"
rm -rf "$BUILD_DIR"
xcodebuild -project QuickReminders.xcodeproj -scheme "$APP_NAME" \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual \
  build >/dev/null

APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

echo "==> Signing"
# Innermost first: signing the app before its nested bundles would seal contents
# that then change. Walk all of Contents rather than just Frameworks — Sparkle's
# bundles live there, but the widget is an .appex under PlugIns.
#
# Sparkle's own bundles keep whatever entitlements they were built with; ours are
# re-applied from source instead of preserved. Preserving would also carry over
# the get-task-allow that the build injects, which has no business in an
# installed copy.
find "$APP/Contents" -depth \
  \( -name "*.framework" -o -name "*.app" -o -name "*.xpc" \) 2>/dev/null \
  | while read -r nested; do
      codesign --force --options runtime --timestamp \
        --preserve-metadata=entitlements --sign "$SIGN_IDENTITY" "$nested"
    done

# Signed with its entitlements, never without: strip them and the widget loses
# its sandbox and App Group, which from the desktop looks exactly like a widget
# that simply never loads.
codesign --force --options runtime --timestamp \
  --entitlements "$REPO_ROOT/QuickRemindersWidget/Resources/QuickRemindersWidget.entitlements" \
  --sign "$SIGN_IDENTITY" "$APP/Contents/PlugIns/QuickRemindersWidget.appex"

codesign --force --options runtime --timestamp \
  --entitlements "$REPO_ROOT/QuickReminders/Resources/QuickReminders.entitlements" \
  --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Installing to $DEST"
if [[ -e "$DEST" ]]; then
  # Only ever replace our own app, never whatever else might sit at that path.
  EXISTING="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$DEST/Contents/Info.plist" 2>/dev/null || echo "")"
  if [[ "$EXISTING" != "$BUNDLE_ID" ]]; then
    echo "Refusing to replace $DEST — its bundle id is '$EXISTING', not '$BUNDLE_ID'." >&2
    exit 1
  fi
fi

osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

rm -rf "$DEST"
cp -R "$APP" "$DEST"

# Remove the build copy. A second bundle with the same id is not harmless:
# LaunchServices may resolve `open -b` to it, and two copies both register the
# global hotkey.
rm -rf "$BUILD_DIR"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DEST/Contents/Info.plist")"
echo
echo "Installed $APP_NAME $VERSION to $DEST"
echo "Signed by: $(codesign -dvv "$DEST" 2>&1 | awk -F'=' '/^Authority/{print $2; exit}')"
echo
echo "Launch it from /Applications, or:  open -b $BUNDLE_ID"
