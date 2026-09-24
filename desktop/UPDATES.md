# DesignSnippets in-app updates

The app embeds Sparkle 2.10.0, pinned by its release archive's SHA-256 checksum.
A configured build checks for new releases automatically and offers Sparkle's
standard Update & Restart UI. Users can also choose **Check for Updates…** from
the menu bar, panel menu, or Preferences. Download/install remains user-controlled.
Update checks never use the user's GitHub login token and send no system profile.

## Release from this Mac

Releases are built and published locally when requested. Pushing source to GitHub
alone does not publish an app update; there is no automatic release workflow and
no need to upload signing credentials to GitHub Actions.

Use the installed Developer ID Application identity, the existing `semantic-notary`
Keychain profile, and the existing Sparkle private-key file. A worktree can point
`SEMANTIC_UPDATE_PRIVATE_KEY_FILE` at the key in the original checkout without
copying it. Never print or commit the key.

Run `npm run desktop:test`, commit and push the source, then prepare a release as
shown below. Choose a new patch version and a build number greater than the current
public appcast. `desktop/scripts/next-release.py` can calculate both from a paginated
GitHub releases JSON array and the current appcast. Do not run simultaneous releases.

After `npm run desktop:release` succeeds, publish with the same version/build
variables still exported:

```sh
export GH_REPO=Jayson-Studio/DesignSnippets
bash desktop/scripts/publish-release.sh
```

The publisher uses the current Git commit (or `SEMANTIC_RELEASE_COMMIT` if explicitly
set), verifies the archive's signature against the public key installed apps trust,
uploads the ZIP and appcast to a draft, then publishes it as latest. It verifies
both public assets and the latest feed after publication. Failures before publishing
leave the previous update live; failures in the final download check do not roll
back an already published release. Versioned artifacts are never overwritten.

Installed users then choose **Check for Updates…**; no manual rebuild or reinstall
is needed for an existing updater-enabled app.

## One-time setup

1. Choose a public HTTPS location for `appcast.xml` and versioned ZIP downloads.
   A **separate public GitHub release repository** can host binaries without
   exposing this source repository. Private GitHub release downloads are not
   supported: the updater must work when the user is signed out of GitHub.
2. Set `feedURL` in `desktop/updates.json`. Its `publicKey` is public and safe to
   commit. Both settings are baked into the app, not entered by end users.
3. The signing seed was generated in `desktop/.secrets/sparkle-private-key` (0600;
   containing directory 0700 and gitignored). Back it up in secure storage. Never
   add it to a release, source control, chat, or build log. Do not regenerate it
   for a new version. `npm run desktop:update-key` reuses the saved key and refuses
   to replace a different configured public key. This is a release-signing key;
   it is unrelated to end-user GitHub login or Keychain access.
4. Install a **Developer ID Application** signing certificate and configure a
   `notarytool` Keychain profile locally. Never send its password or private key
   through chat. These credentials are for building releases, not for end users.
   On this Mac, the Developer ID identity is now installed. Run
   `bash desktop/scripts/setup-notarization.command` in your own Terminal to save
   notarization credentials under the `semantic-notary` profile. The script asks
   for your Apple Account email and securely prompts for an app-specific password.
5. Build, notarize, and publish the initial updater-enabled release using the
   commands below. Existing 0.2.x users need one manual installation of this build.

The configured feed is
`https://github.com/Jayson-Studio/DesignSnippets/releases/latest/download/appcast.xml`.
This repository is public. The feed will be available after the first signed release
and its assets are published; configuration alone does not publish a release.
The internal bundle ID and cache directory remain unchanged so existing settings
and token imports survive the product rename from Semantic to DesignSnippets.

## Prepare a release

Use a **new monotonically increasing build number** for every published version.
Example values below illustrate the workflow; replace the identity, profile, and
hosting URL with the actual configured values.

```sh
export SEMANTIC_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export SEMANTIC_NOTARY_PROFILE='semantic-notary'
export SEMANTIC_VERSION='0.3.0'
export SEMANTIC_BUILD_NUMBER='7'
export SEMANTIC_DOWNLOAD_URL_PREFIX='https://github.com/Jayson-Studio/DesignSnippets/releases/download/v0.3.0/'
npm run desktop:test
npm run desktop:release
```

The release command builds both Apple Silicon and Intel, embeds and signs Sparkle's
helpers inside-out, notarizes and staples the app, verifies Gatekeeper acceptance,
then creates the ZIP and signed update metadata in `desktop/build/releases/0.3.0/`.
It uploads the signed app to Apple for notarization, but does not publish to
GitHub. An existing version's archive is never overwritten. Keep published version URLs immutable.

Upload the versioned ZIP first. Make sure it is downloadable without a login.
Then publish `appcast.xml` at the exact URL baked into the app. Updating that feed
makes the new release available to installed users. The script creates a full
update feed for the current release; deltas are disabled. All supported Macs
receive the same universal archive.

For GitHub hosting, a stable feed can be a repository's
`https://github.com/OWNER/RELEASES-REPO/releases/latest/download/appcast.xml`.
Use a version-specific archive prefix such as
`https://github.com/OWNER/RELEASES-REPO/releases/download/v0.3.0/` when generating
that release. Upload both files to a draft release, verify them, then publish it.
Avoid marking test/older builds as the latest stable release.

CI can supply `SEMANTIC_UPDATE_PRIVATE_KEY_FILE` as a securely provisioned file.
`SEMANTIC_UPDATE_FEED_URL` and `SEMANTIC_UPDATE_PUBLIC_KEY` override public config
at build time. No private key is embedded in the app. Production builds never use
the development-only library-validation entitlement.

## Verification

`desktop:test` covers invalid/missing updater configuration, HTTPS enforcement,
public-key length, signature-before-extraction settings, and Sparkle framework
loading/version comparisons, in addition to the existing application tests.

Before calling the pipeline live, test a real update from an installed older
**signed and notarized** build to the new published build. Confirm Update & Restart,
retained preferences/cache, Accessibility behavior, and failure with an altered
archive. Automated configuration tests do not establish end-to-end installation.

References: [Sparkle setup](https://sparkle-project.org/documentation/),
[programmatic integration](https://sparkle-project.org/documentation/programmatic-setup/),
[publishing updates](https://sparkle-project.org/documentation/publishing/).
