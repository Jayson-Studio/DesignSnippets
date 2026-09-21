#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
version=2.10.0
checksum=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
base="$PWD/desktop/build/dependencies"
archive="$base/Sparkle-$version.tar.xz"
destination="$base/Sparkle-$version"
mkdir -p "$base"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$archive.download"
  mv "$archive.download" "$archive"
fi
actual=$(shasum -a 256 "$archive" | awk '{print $1}')
[[ "$actual" == "$checksum" ]] || { echo 'Sparkle checksum mismatch; refusing to build.' >&2; exit 1; }
if [[ ! -f "$destination/Sparkle.framework/Sparkle" ]]; then
  mkdir -p "$destination"
  tar -xf "$archive" -C "$destination"
fi
