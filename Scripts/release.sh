#!/bin/bash
# Build, sign and stage a release.
#
#   Scripts/release.sh 1.1
#
# Distribution is Homebrew-only, and the build is deliberately NOT notarised:
#
#   * Homebrew quarantines what it downloads, so the cask clears the attribute
#     in a postflight. Gatekeeper never assesses the app, and notarisation
#     would buy nothing.
#   * Sparkle fetches updates over URLSession, which does not quarantine
#     either, so self-updates are unaffected by the same reasoning.
#
# The trade is real: a build that arrives any other way — AirDrop, a browser
# download, a USB stick — WILL be refused by Gatekeeper. Homebrew is the
# supported way in, on every machine.
#
# Prerequisites, all one-time:
#   * A "Developer ID Application" certificate in the login keychain.
#   * The Sparkle EdDSA private key in the login keychain (already present).
#   * The tap tapped locally: brew tap nicblunck/tap
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: Scripts/release.sh <version>   e.g. Scripts/release.sh 1.1" >&2
  exit 1
fi

SIGN_IDENTITY="Developer ID Application"
TEAM_ID="U4K77TMBRU"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.release"
APP_NAME="QuickReminders"
# Where `brew tap nicblunck/tap` clones to, so the cask is edited and pushed
# from the same checkout Homebrew reads. Override with TAP_DIR=... if needed.
TAP_DIR="${TAP_DIR:-$(brew --repository nicblunck/tap 2>/dev/null)}"
# generate_appcast treats its argument as a flat directory of update archives,
# and writes delta files and old_updates/ into it. Keep it well away from the
# build tree so it never walks the derived data.
ARCHIVES="$BUILD_DIR/archives"
ZIP="$ARCHIVES/$APP_NAME-$VERSION.zip"

SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData/QuickReminders-*/SourcePackages/artifacts/sparkle/Sparkle/bin \
  -name generate_appcast -maxdepth 1 2>/dev/null | head -1)"
SPARKLE_BIN="$(dirname "${SPARKLE_BIN:?Sparkle tools not found — build once to resolve packages}")"

echo "==> Generating project"
cd "$REPO_ROOT"
xcodegen generate

echo "==> Building $VERSION"
rm -rf "$BUILD_DIR"
mkdir -p "$ARCHIVES"
xcodebuild -project QuickReminders.xcodeproj -scheme QuickReminders \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR/dd" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual \
  build

APP="$BUILD_DIR/dd/Build/Products/Release/$APP_NAME.app"

# Nested code must be signed before the app that contains it, innermost first,
# or the outer signature seals a bundle whose contents then change. Walk all of
# Contents, not just Frameworks: Sparkle ships four bundles there (Updater.app,
# its versioned twin, Downloader.xpc, Installer.xpc) but the widget is an .appex
# under PlugIns, and the build signs it without hardened runtime or a timestamp.
echo "==> Signing"
# Sparkle's own bundles keep the entitlements they were built with.
find "$APP/Contents" -depth \
  \( -name "*.framework" -o -name "*.app" -o -name "*.xpc" \) 2>/dev/null \
  | while read -r nested; do
      codesign --force --options runtime --timestamp \
        --preserve-metadata=entitlements --sign "$SIGN_IDENTITY" "$nested"
    done

# Ours are re-applied from source rather than preserved. Preserving would carry
# over the get-task-allow the build injects, which lets anything attach a
# debugger to a shipped app — the one thing notarisation used to catch here, and
# nothing catches now. Signing from the files also guarantees the widget keeps
# its sandbox and App Group; strip those and it looks, from the desktop, exactly
# like a widget that never loads.
codesign --force --options runtime --timestamp \
  --entitlements "$REPO_ROOT/QuickRemindersWidget/Resources/QuickRemindersWidget.entitlements" \
  --sign "$SIGN_IDENTITY" "$APP/Contents/PlugIns/QuickRemindersWidget.appex"

codesign --force --options runtime --timestamp \
  --entitlements "$REPO_ROOT/QuickReminders/Resources/QuickReminders.entitlements" \
  --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# The signature is timestamped so it stays valid past the certificate's own
# expiry, and Sparkle refuses an update whose signing identity differs from the
# running app's — so this identity must not change between releases.
echo "==> Archiving"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Updating appcast"
# generate_appcast only extends a feed it finds inside the archives directory,
# and that directory is rebuilt from scratch on every run — so seed it with the
# published appcast, or each release would advertise a feed of one lone version.
if [[ -f "$REPO_ROOT/appcast.xml" ]]; then
  cp "$REPO_ROOT/appcast.xml" "$ARCHIVES/"
fi

# It signs each archive with the EdDSA key from the login keychain.
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/nicblunck/quick-reminder/releases/download/v$VERSION/" \
  -o "$REPO_ROOT/appcast.xml" \
  "$ARCHIVES"

echo "==> Rendering cask"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
CASK="$BUILD_DIR/quickreminders.rb"
cat > "$CASK" <<'CASK_EOF'
cask "quickreminders" do
  version "__VERSION__"
  sha256 "__SHA__"

  url "https://github.com/nicblunck/quick-reminder/releases/download/v#{version}/QuickReminders-#{version}.zip"
  name "Quick Reminders"
  desc "Menu bar capture tool for Apple Reminders"
  homepage "https://github.com/nicblunck/quick-reminder"

  # The app updates itself through Sparkle. Without this, Homebrew would keep
  # offering upgrades for a copy Sparkle has already replaced, and the two
  # would fight over the same bundle.
  auto_updates true
  depends_on macos: :tahoe

  app "QuickReminders.app"

  # The build is not notarised. Homebrew quarantines what it downloads and
  # Gatekeeper refuses to launch an unnotarised quarantined app, so clear the
  # attribute here. This is precisely why installing by hand does not work.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/QuickReminders.app"]
  end

  zap trash: [
    "~/Library/Caches/com.nicolasblunck.QuickReminders",
    "~/Library/Preferences/com.nicolasblunck.QuickReminders.plist",
  ]
end
CASK_EOF
sed -i '' "s|__VERSION__|$VERSION|; s|__SHA__|$SHA|" "$CASK"

if [[ -d "$TAP_DIR/Casks" ]]; then
  cp "$CASK" "$TAP_DIR/Casks/quickreminders.rb"
  echo "    wrote $TAP_DIR/Casks/quickreminders.rb"
  TAP_NOTE="  cd '$TAP_DIR' && git add Casks/quickreminders.rb && git commit -m 'quickreminders $VERSION' && git push"
else
  echo "    tap not found at $TAP_DIR — cask left at $CASK"
  TAP_NOTE="  # clone the tap, then copy $CASK into its Casks/ and push"
fi

echo
echo "Built and signed: $ZIP"
echo "sha256: $SHA"
echo
echo "Remaining steps, deliberately manual so nothing is published by accident:"
echo "  gh release create v$VERSION '$ZIP' --title 'v$VERSION' --notes '...'"
echo "  git add appcast.xml && git commit -m 'Release $VERSION' && git push"
echo "$TAP_NOTE"
echo
echo "Create the GitHub release FIRST — both the appcast and the cask point at"
echo "its download URL, and neither is any use until that asset exists."
