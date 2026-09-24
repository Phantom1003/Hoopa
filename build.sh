#!/bin/zsh
# Builds Hoopa.app (Release) and signs it.
#   ./build.sh                                  # picks the Apple Development certificate in the keychain, errors out without one
#   SIGN_IDENTITY="Apple Development: xxx" ./build.sh   # a specific signing identity
set -euo pipefail
cd "$(dirname "$0")"

# In the macOS 26+ SDK SwiftUI's @State and friends are macros, and the macro plugin ships only with Xcode;
# when xcode-select points at the command line tools, switch to Xcode here.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release
# Icons: scripts/icon-source.png makes the app icon Hoopa.icns and the menu bar icon menubar.png / @2x (see scripts/icons.swift).
# Generate first, assemble the app after, so a failed generation leaves no half-built app.
ICONS=$(mktemp -d)
trap 'rm -rf "$ICONS"' EXIT
swift scripts/icons.swift scripts/icon-source.png "$ICONS/Hoopa.iconset" "$ICONS"
iconutil -c icns "$ICONS/Hoopa.iconset" -o "$ICONS/Hoopa.icns"
APP="build/Hoopa.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Hoopa "$APP/Contents/MacOS/Hoopa"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"    # the interface translations
cp "$ICONS/Hoopa.icns" "$ICONS"/menubar*.png "$APP/Contents/Resources/"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
# Signing identity: SIGN_IDENTITY from the environment, otherwise the first valid Apple Development certificate in the keychain.
# No automatic fallback to ad hoc: an ad hoc signature changes with every build and the Accessibility grant is lost. Pass SIGN_IDENTITY=- explicitly for ad hoc.
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  rm -rf "$APP"
  echo "❌ No Apple Development certificate in the keychain (sign in to a developer account under Xcode → Settings → Accounts to create one)." >&2
  exit 1
fi
# Signing needs the private key in the keychain: run this script from Terminal and click "Always Allow" in the keychain prompt.
# Delete the unsigned app when signing fails, so it is not opened by mistake.
if ! codesign --force --sign "$SIGN_IDENTITY" "$APP"; then
  rm -rf "$APP"
  echo "❌ Signing failed ($SIGN_IDENTITY). Run from Terminal and click \"Always Allow\" when the keychain unlocks / prompts." >&2
  exit 1
fi
# The app was rebuilt in place; tell LaunchServices, or Finder and notifications may keep the old icon.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
echo "✅ Built $APP (signed with: $SIGN_IDENTITY)"
echo "   Run: open \"$APP\""
