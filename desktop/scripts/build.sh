#!/bin/bash
set -euo pipefail
# Read the entire script before starting long-running signing operations. Editing
# the source file during a Keychain prompt must not change an in-flight build.
if [[ "${DESIGNSNIPPETS_BUILD_SNAPSHOT:-0}" != "1" ]]; then
  export DESIGNSNIPPETS_BUILD_SNAPSHOT=1
  exec /bin/bash -c "$(cat "$0")" "$0" "$@"
fi
cd "$(dirname "$0")/../.."
identity="${SEMANTIC_SIGN_IDENTITY:--}"
if [[ "$identity" != "-" ]]; then
  python3 desktop/scripts/sign-app.py --check-consent
fi
# Resume only an explicitly selected, unchanged staged app. No rebuild or re-copy.
if [[ "${1:-}" == "--resume-signing" ]]; then
  [[ "$identity" != "-" && -n "${2:-}" && "$#" == 2 ]] || { echo 'Resume requires a staged app and Developer ID identity.' >&2; exit 1; }
  app="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
  case "$app" in
    "$PWD"/desktop/build/staging.*/DesignSnippets.app) ;;
    *) echo 'Resume requires a staged app from this checkout.' >&2; exit 1 ;;
  esac
  [[ ! -L "$app" ]] || { echo 'Cannot resume a symlinked app.' >&2; exit 1; }
  python3 desktop/scripts/sign-app.py "$app" --identity "$identity"
  destination="$PWD/desktop/build/DesignSnippets.app"
  [[ "$app" != "$destination" ]] || { echo 'Resume requires the staged app, not the published build.' >&2; exit 1; }
  rm -rf "$destination"
  mv "$app" "$destination"
  printf '\nBuilt %s\n' "$destination"
  exit 0
fi
[[ "$#" == 0 ]] || { echo 'Unknown build arguments.' >&2; exit 1; }
python3 desktop/scripts/configure-github.py --check
output="$PWD/desktop/build"
mkdir -p "$output"
staging=$(mktemp -d "$output/staging.XXXXXX")
preserve_staging=0
cleanup() {
  if [[ "$preserve_staging" == 1 ]]; then
    printf '\nSigning paused; staged app retained at: %s\n' "$app" >&2
    printf 'After resolving signing access, resume this exact app with SEMANTIC_RESUME_SIGNING set to that path.\n' >&2
  else
    rm -rf "$staging"
  fi
}
trap cleanup EXIT
app="$staging/DesignSnippets.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$output/module-cache"
cp -R desktop/Resources/Fonts "$app/Contents/Resources/"
cp -R desktop/Resources/DesignSystem "$app/Contents/Resources/"
bash desktop/scripts/fetch-sparkle.sh
sparkle="$output/dependencies/Sparkle-2.10.0"
mkdir -p "$app/Contents/Frameworks"
# Replace the embedded copy, preserving Sparkle's framework symlinks.
rm -rf "$app/Contents/Frameworks/Sparkle.framework"
ditto "$sparkle/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
arch="${SEMANTIC_ARCH:-$(uname -m)}"
architectures=("$arch")
if [[ "$arch" == "universal" ]]; then architectures=(arm64 x86_64); fi
for architecture in "${architectures[@]}"; do
xcrun swiftc -swift-version 5 -O -target "$architecture-apple-macosx14.0" \
  -module-cache-path "$output/module-cache" \
  desktop/Sources/*.swift -o "$output/DesignSnippets-$architecture" \
  -framework AppKit -framework SwiftUI -framework Security -framework ApplicationServices \
  -F "$sparkle" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks
done
if [[ "$arch" == "universal" ]]; then
  lipo -create "$output/DesignSnippets-arm64" "$output/DesignSnippets-x86_64" -output "$app/Contents/MacOS/DesignSnippets"
else
  cp "$output/DesignSnippets-$arch" "$app/Contents/MacOS/DesignSnippets"
fi
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>DesignSnippets</string>
<key>CFBundleDisplayName</key><string>DesignSnippets</string>
<key>CFBundleIdentifier</key><string>app.semantic.desktop</string>
<key>CFBundleIconFile</key><string>DesignSnippets</string>
<key>CFBundleExecutable</key><string>DesignSnippets</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>7</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAccessibilityUsageDescription</key><string>DesignSnippets detects # and inserts your selected design token in compatible apps. It does not store or transmit typed text.</string>
</dict></plist>
PLIST
python3 desktop/scripts/configure-github.py "$app/Contents/Info.plist"
python3 desktop/scripts/configure-updates.py "$app/Contents/Info.plist"
iconset="$output/DesignSnippets.iconset"
mkdir -p "$iconset"
xcrun swift -module-cache-path "$output/module-cache" desktop/scripts/icon.swift "$output/icon.png"
for pixels in 16 32 128 256 512; do
  sips -z "$pixels" "$pixels" "$output/icon.png" --out "$iconset/icon_$pixels"x"$pixels.png" >/dev/null
  double=$((pixels * 2))
  sips -z "$double" "$double" "$output/icon.png" --out "$iconset/icon_$pixels"x"$pixels@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/DesignSnippets.icns"
if [[ "$identity" == "-" ]]; then
  # Development only: allow the vendor-signed Sparkle framework in an ad-hoc app.
  cat > "$output/development.entitlements" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.cs.disable-library-validation</key><true/></dict></plist>
ENTITLEMENTS
  codesign --force --sign - --options runtime --entitlements "$output/development.entitlements" "$app"
else
  preserve_staging=1
  python3 desktop/scripts/sign-app.py "$app" --identity "$identity"
fi
codesign --verify --deep --strict "$app"
# Publish only the completely signed, verified bundle. Never reuse old seals.
rm -rf "$output/DesignSnippets.app"
mv "$app" "$output/DesignSnippets.app"
preserve_staging=0
printf '\nBuilt %s\n' "$output/DesignSnippets.app"
