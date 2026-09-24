#!/bin/zsh
# Builds Hoopa.app (Release) and signs it.
#   ./build.sh                                  # picks the Apple Development certificate in the keychain, ad hoc without one
#   SIGN_IDENTITY="Apple Development: xxx" ./build.sh   # a specific signing identity
set -euo pipefail
cd "$(dirname "$0")"

# In the macOS 26+ SDK SwiftUI's @State and friends are macros, and the macro plugin ships only with Xcode;
# when xcode-select points at the command line tools, switch to Xcode here.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release
APP="build/Hoopa.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Hoopa "$APP/Contents/MacOS/Hoopa"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"    # the interface translations
echo -n "APPL????" > "$APP/Contents/PkgInfo"
# Signing identity: SIGN_IDENTITY from the environment, otherwise the first valid Apple Development certificate in the keychain,
# otherwise ad hoc ("-"). Signed with a real certificate, the Accessibility grant survives rebuilds.
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_IDENTITY" "$APP"
echo "✅ Built $APP (signed with: $SIGN_IDENTITY)"
echo "   Run: open \"$APP\""
