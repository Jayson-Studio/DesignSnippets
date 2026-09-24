#!/bin/bash
# Prepare artifacts only. Publishing is a separate, explicit operation.
set -euo pipefail
cd "$(dirname "$0")/../.."
export SEMANTIC_REQUIRE_GITHUB=1
python3 desktop/scripts/configure-github.py --check
: "${SEMANTIC_SIGN_IDENTITY:?Set an installed Developer ID Application signing identity}"
[[ "$SEMANTIC_SIGN_IDENTITY" == "Developer ID Application:"* ]] || { echo 'A Developer ID Application identity is required.' >&2; exit 1; }
: "${SEMANTIC_NOTARY_PROFILE:?Set your notarytool Keychain profile name}"
: "${SEMANTIC_VERSION:?Set the release version}"
export SEMANTIC_DOWNLOAD_URL_PREFIX="${SEMANTIC_DOWNLOAD_URL_PREFIX:-https://github.com/Jayson-Studio/DesignSnippets/releases/download/v$SEMANTIC_VERSION/}"
: "${SEMANTIC_BUILD_NUMBER:?Set a monotonically increasing integer build number}"
[[ "$SEMANTIC_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$SEMANTIC_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid version/build number.' >&2; exit 1; }
python3 - <<'PY'
import os
from urllib.parse import urlsplit
u=urlsplit(os.environ['SEMANTIC_DOWNLOAD_URL_PREFIX'])
assert u.scheme == 'https' and u.hostname and u.username is None and u.password is None and not u.query and not u.fragment, 'Use an HTTPS download directory without credentials/query/fragment'
PY
key="${SEMANTIC_UPDATE_PRIVATE_KEY_FILE:-$PWD/desktop/.secrets/sparkle-private-key}"
[[ -f "$key" ]] || { echo 'Restore the private update-signing key before releasing.' >&2; exit 1; }
export SEMANTIC_REQUIRE_UPDATES=1
export SEMANTIC_ARCH=universal
bash desktop/scripts/build.sh
release="$PWD/desktop/build/releases/$SEMANTIC_VERSION"
mkdir -p "$release"
archive="$release/DesignSnippets-$SEMANTIC_VERSION-macOS.zip"
[[ ! -e "$archive" ]] || { echo 'Release archive already exists; use a new version or explicitly move the old draft.' >&2; exit 1; }
ditto -c -k --sequesterRsrc --keepParent desktop/build/DesignSnippets.app "$release/notarization.zip"
notary_args=(--keychain-profile "$SEMANTIC_NOTARY_PROFILE")
if [[ -n "${SEMANTIC_NOTARY_KEYCHAIN:-}" ]]; then notary_args+=(--keychain "$SEMANTIC_NOTARY_KEYCHAIN"); fi
xcrun notarytool submit "$release/notarization.zip" "${notary_args[@]}" --wait
xcrun stapler staple desktop/build/DesignSnippets.app
xcrun stapler validate desktop/build/DesignSnippets.app
codesign --verify --deep --strict desktop/build/DesignSnippets.app
spctl --assess --type execute desktop/build/DesignSnippets.app
rm "$release/notarization.zip"
ditto -c -k --sequesterRsrc --keepParent desktop/build/DesignSnippets.app "$archive"
desktop/build/dependencies/Sparkle-2.10.0/bin/generate_appcast --ed-key-file "$key" --maximum-deltas 0 --download-url-prefix "${SEMANTIC_DOWNLOAD_URL_PREFIX%/}/" -o "$release/appcast.xml" "$release"
printf '\nPrepared %s and appcast.xml. Upload the ZIP first; publish the feed last.\n' "$archive"
