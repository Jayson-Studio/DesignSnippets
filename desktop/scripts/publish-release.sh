#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${SEMANTIC_VERSION:?}" "${SEMANTIC_BUILD_NUMBER:?}" "${GH_REPO:?}"
release_commit="${SEMANTIC_RELEASE_COMMIT:-$(git rev-parse HEAD)}"
git cat-file -e "$release_commit^{commit}"
release="$PWD/desktop/build/releases/$SEMANTIC_VERSION"
archive="$release/DesignSnippets-$SEMANTIC_VERSION-macOS.zip"
feed="$release/appcast.xml"
export SEMANTIC_DOWNLOAD_URL_PREFIX="https://github.com/$GH_REPO/releases/download/v$SEMANTIC_VERSION/"
python3 desktop/scripts/verify-release.py "$archive" "$feed"
cat > "$release/notes.md" <<EOF_NOTES
Signed and notarized universal macOS release (Apple Silicon and Intel).

Use **Check for Updates…** in DesignSnippets, or download the ZIP below.

Source commit: $release_commit
Build: $SEMANTIC_BUILD_NUMBER
EOF_NOTES
# Keep the previous feed live until both assets are attached to the draft.
gh release create "v$SEMANTIC_VERSION" --draft --target "$release_commit" \
  --title "DesignSnippets $SEMANTIC_VERSION" --notes-file "$release/notes.md"
gh release upload "v$SEMANTIC_VERSION" "$archive" "$feed"
gh release edit "v$SEMANTIC_VERSION" --draft=false --latest
# Verify the same public URLs used by signed-out installations.
for asset in "$(basename "$archive")" appcast.xml; do
  curl --fail --location --silent --show-error --retry 5 --retry-all-errors --retry-delay 5 \
    --proto '=https' --proto-redir '=https' "$SEMANTIC_DOWNLOAD_URL_PREFIX$asset" -o "$release/verified-$asset"
  cmp "$release/$asset" "$release/verified-$asset"
done
curl --fail --location --silent --show-error --retry 5 --retry-all-errors --retry-delay 5 \
  --proto '=https' --proto-redir '=https' "https://github.com/$GH_REPO/releases/latest/download/appcast.xml" -o "$release/verified-latest.xml"
cmp "$feed" "$release/verified-latest.xml"
printf 'Published https://github.com/%s/releases/tag/v%s\n' "$GH_REPO" "$SEMANTIC_VERSION"
