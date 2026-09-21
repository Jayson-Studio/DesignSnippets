#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash desktop/scripts/build.sh
archive_dir=$(mktemp -d "$PWD/desktop/build/package.XXXXXX")
archive="$archive_dir/DesignSnippets.zip"
trap 'rm -rf "$archive_dir"' EXIT
ditto -c -k --sequesterRsrc --keepParent desktop/build/DesignSnippets.app "$archive"
mv "$archive" desktop/build/DesignSnippets-macOS-preview.zip
printf '\nPackaged desktop/build/DesignSnippets-macOS-preview.zip (development preview)\n'
