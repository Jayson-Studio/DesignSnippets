#!/bin/bash
set -euo pipefail
# Read the entire script before starting long-running signing operations. Editing
# the source file during a Keychain prompt must not change an in-flight build.
if [[ "${DESIGNSNIPPETS_BUILD_SNAPSHOT:-0}" != "1" ]]; then
  export DESIGNSNIPPETS_BUILD_SNAPSHOT=1
  exec /bin/bash -c "$(cat "$0")" "$0" "$@"
fi
cd "$(dirname "$0")/../.."
python3 desktop/scripts/configure-github.py --check
output="$PWD/desktop/build"
mkdir -p "$output"
staging=$(mktemp -d "$output/staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT
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
identity="${SEMANTIC_SIGN_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
  # Development only: allow the vendor-signed Sparkle framework in an ad-hoc app.
  cat > "$output/development.entitlements" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.cs.disable-library-validation</key><true/></dict></plist>
ENTITLEMENTS
  codesign --force --sign - --options runtime --entitlements "$output/development.entitlements" "$app"
else
  framework="$app/Contents/Frameworks/Sparkle.framework"
  # Sign inside-out and preserve the helper services' original entitlements.
  signing_step=0
  for component in "$framework/Versions/B/XPCServices/Downloader.xpc" "$framework/Versions/B/XPCServices/Installer.xpc" "$framework/Versions/B/Autoupdate" "$framework/Versions/B/Updater.app" "$framework"; do
    signing_step=$((signing_step + 1))
    printf "Signing [%s/6]: %s — approve any macOS Keychain prompt for codesign.\n" "$signing_step" "$(basename "$component")"
    codesign --force --sign "$identity" --options runtime --timestamp --preserve-metadata=entitlements "$component"
  done
  printf "Signing [6/6]: DesignSnippets.app\n"
  codesign --force --sign "$identity" --options runtime --timestamp "$app"
fi
codesign --verify --deep --strict "$app"
# Publish only the completely signed, verified bundle. Never reuse old seals.
rm -rf "$output/DesignSnippets.app"
mv "$app" "$output/DesignSnippets.app"
printf '\nBuilt %s\n' "$output/DesignSnippets.app"
