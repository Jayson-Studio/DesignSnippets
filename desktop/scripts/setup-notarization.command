#!/bin/bash
set -euo pipefail
printf 'DesignSnippets notarization setup\nThis saves an Apple app-specific password in your login Keychain for Apple notarization.\nEnter that password only into the secure prompt below, never into chat.\n\n'
read -r -p 'Apple Account email: ' notary_account
xcrun notarytool store-credentials semantic-notary --apple-id "$notary_account" --team-id 4U535P94U6
printf '\nNotarization credentials saved. You can return to DesignSnippets setup.\n'
read -r -p 'Press Return to close. ' finished
