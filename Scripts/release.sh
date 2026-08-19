#!/bin/bash
# Build, sign, notarize and publish a release.
#
#   Scripts/release.sh 1.1
#
# Prerequisites, all one-time:
#   * A "Developer ID Application" certificate in the login keychain.
#   * A notarytool keychain profile named by NOTARY_PROFILE below, created with:
#       xcrun notarytool store-credentials "QuickReminders" \
#         --apple-id <your-apple-id> --team-id <TEAM> --password <app-specific-password>
#     Run that yourself — it stores an app-specific password in your keychain.
#   * The Sparkle EdDSA private key in the login keychain (already present).
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: Scripts/release.sh <version>   e.g. Scripts/release.sh 1.1" >&2
  exit 1
fi

SIGN_IDENTITY="Developer ID Application"
NOTARY_PROFILE="QuickReminders"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.release"
APP_NAME="QuickReminders"
ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"

SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData/QuickReminders-*/SourcePackages/artifacts/sparkle/Sparkle/bin \
  -name generate_appcast -maxdepth 1 2>/dev/null | head -1)"
SPARKLE_BIN="$(dirname "${SPARKLE_BIN:?Sparkle tools not found — build once to resolve packages}")"

echo "==> Generating project"
cd "$REPO_ROOT"
xcodegen generate

echo "==> Building $VERSION"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
xcodebuild -project QuickReminders.xcodeproj -scheme QuickReminders \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR/dd" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual \
  build

APP="$BUILD_DIR/dd/Build/Products/Release/$APP_NAME.app"

# Nested code must be signed before the app that contains it, innermost first,
# or the outer signature seals a bundle whose contents then change.
echo "==> Signing"
find "$APP/Contents/Frameworks" -depth -name "*.framework" -o -depth -name "*.app" -o -depth -name "*.xpc" 2>/dev/null \
  | while read -r nested; do
      codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$nested"
    done
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Notarizing"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
# Staple the app, then re-zip: the ticket has to be inside the archive people download.
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun stapler validate "$APP"

echo "==> Updating appcast"
# generate_appcast signs each archive with the EdDSA key from the keychain and
# rewrites appcast.xml in place.
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/nicblunck/quick-reminder/releases/download/v$VERSION/" \
  -o "$REPO_ROOT/appcast.xml" \
  "$BUILD_DIR"

echo
echo "Built and notarized: $ZIP"
echo
echo "Remaining steps, deliberately manual so nothing is published by accident:"
echo "  gh release create v$VERSION '$ZIP' --title 'v$VERSION' --notes '...'"
echo "  git add appcast.xml && git commit -m 'Release $VERSION' && git push"
echo
echo "Sparkle reads appcast.xml from main, so the release must exist before the push."
