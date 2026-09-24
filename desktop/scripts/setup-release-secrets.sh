#!/bin/bash
# Run interactively on your Mac. Secret values go directly to GitHub, never stdout.
set -euo pipefail
set +x
cd "$(dirname "$0")/../.."
repo=Jayson-Studio/DesignSnippets
gh auth status >/dev/null
printf 'Configure encrypted Actions secrets for %s.\n' "$repo"
printf 'Export only your Developer ID Application certificate and private key as a password-protected .p12 from Keychain Access first.\n'
read -r -p 'Path to the exported .p12: ' certificate
[[ -f "$certificate" ]] || { echo 'Certificate file not found.' >&2; exit 1; }
read -r -s -p 'Password protecting the .p12: ' certificate_password; printf '\n'
[[ -n "$certificate_password" ]] || { echo 'Use a password-protected export.' >&2; exit 1; }
read -r -p 'Apple Account email for notarization: ' apple_id
read -r -p 'Apple Team ID [4U535P94U6]: ' team_id
team_id=${team_id:-4U535P94U6}
read -r -s -p 'Apple app-specific password for notarization: ' apple_password; printf '\n'
[[ -n "$apple_id" && -n "$apple_password" ]] || { echo 'Notarization credentials are required.' >&2; exit 1; }
read -r -p 'Path to the EXISTING sparkle-private-key file (do not generate a new key): ' sparkle_key
[[ -s "$sparkle_key" ]] || { echo 'Existing Sparkle key file not found.' >&2; exit 1; }
base64 -i "$certificate" | gh secret set APPLE_CERTIFICATE_P12_BASE64 --repo "$repo"
printf '%s' "$certificate_password" | gh secret set APPLE_CERTIFICATE_PASSWORD --repo "$repo"
printf '%s' "$apple_id" | gh secret set APPLE_ID --repo "$repo"
printf '%s' "$team_id" | gh secret set APPLE_TEAM_ID --repo "$repo"
printf '%s' "$apple_password" | gh secret set APPLE_APP_SPECIFIC_PASSWORD --repo "$repo"
gh secret set SPARKLE_PRIVATE_KEY --repo "$repo" < "$sparkle_key"
unset certificate_password apple_password
printf '\nSecrets saved. Start the first release with:\n  gh workflow run desktop-release.yml --repo %s --ref main\n' "$repo"
