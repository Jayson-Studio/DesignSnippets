#!/bin/bash
# Run only on an ephemeral GitHub-hosted macOS runner. Never enable shell tracing.
set -euo pipefail
umask 077
: "${RUNNER_TEMP:?}" "${GITHUB_ENV:?}"
keychain="$RUNNER_TEMP/designsnippets-signing.keychain-db"
certificate="$RUNNER_TEMP/designsnippets-certificate.p12"
key="$RUNNER_TEMP/designsnippets-sparkle-key"
keychain_password=$(openssl rand -hex 32)
printf '::add-mask::%s\n' "$keychain_password"
printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64 --decode > "$certificate"
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$key"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$certificate" -P "$APPLE_CERTIFICATE_PASSWORD" -k "$keychain" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
identity=$(security find-identity -v -p codesigning "$keychain" | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p')
[[ -n "$identity" && "$identity" != *$'\n'* ]] || { echo 'Expected exactly one Developer ID Application identity.' >&2; exit 1; }
xcrun notarytool store-credentials designsnippets-ci --keychain "$keychain" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" >/dev/null
rm -f "$certificate"
{
  printf 'SEMANTIC_SIGN_IDENTITY=%s\n' "$identity"
  printf 'SEMANTIC_NOTARY_PROFILE=designsnippets-ci\n'
  printf 'SEMANTIC_NOTARY_KEYCHAIN=%s\n' "$keychain"
  printf 'SEMANTIC_UPDATE_PRIVATE_KEY_FILE=%s\n' "$key"
} >> "$GITHUB_ENV"
