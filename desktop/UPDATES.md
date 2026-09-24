# DesignSnippets in-app updates

The app embeds Sparkle 2.10.0, pinned by its release archive's SHA-256 checksum.
A configured build checks for new releases automatically and offers Sparkle's
standard Update & Restart UI. Users can also choose **Check for Updates…** from
the menu bar, panel menu, or Preferences. Download/install remains user-controlled.
Update checks never use the user's GitHub login token and send no system profile.

## Automatic releases on push

`.github/workflows/desktop-release.yml` releases every push to `main`. Feature
branches do not publish. You can also run **Release macOS app** manually from
GitHub Actions on `main`. The workflow uses an ephemeral GitHub-hosted macOS 15
runner; your Mac does not need to stay on.

The workflow checks credentials, runs the desktop tests, allocates the next patch
version from existing GitHub releases (including drafts), and increments the build
number from the current public update feed. For example, 0.3.10 / build 17 becomes
0.3.11 / build 18. An unreadable feed fails the job rather than guessing a version.
There is no version-bump commit or recursive push. Releases are serialized without
interrupting an active notarization. GitHub may coalesce pending pushes; the latest
pending commit includes the earlier changes.

It builds for Apple Silicon and Intel, signs with Developer ID, notarizes and
staples the app, checks Gatekeeper, and verifies the archive's Sparkle signature
against the public key already embedded in installed apps. It uploads the ZIP and
appcast to a draft before publishing it as latest. Failures before publication
leave the previous update available; failed drafts are retained for diagnosis and
never overwritten. After publication it checks that both assets and the latest
feed are publicly downloadable and identical to the generated files. An error in
that final check reports failure but does not roll back an already published release.

### One-time Actions credentials

Run this locally in Terminal (passwords are hidden and sent directly to encrypted
GitHub Actions secrets; do not put them in chat or source control):

```sh
bash desktop/scripts/setup-release-secrets.sh
```

Before running it, open **Keychain Access → My Certificates**, select the existing
**Developer ID Application** certificate and its private key, and export just that
identity as a password-protected `.p12`. Use the existing Apple app-specific
password for notarization (or create one in your Apple Account). Use the existing
`desktop/.secrets/sparkle-private-key` from the original project checkout; do not
rotate it, since installed apps trust its matching public key.

The script configures these repository secrets:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID `.p12`, including private key |
| `APPLE_CERTIFICATE_PASSWORD` | Password protecting that export |
| `APPLE_ID` | Apple Account email for notarization |
| `APPLE_TEAM_ID` | Developer team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | Apple app-specific password for notarization |
| `SPARKLE_PRIVATE_KEY` | Contents of the existing Sparkle signing-key file |

No personal GitHub token is required: publication uses the job's `GITHUB_TOKEN`
with `contents: write`. Signing material is installed in a temporary keychain and
removed in an always-run cleanup step. The runner is then discarded. This follows
[GitHub's certificate setup guidance](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).

Once credentials are configured, rerun a failed initial workflow or trigger:

```sh
gh workflow run desktop-release.yml --repo Jayson-Studio/DesignSnippets --ref main
```

Watch the Actions run, then choose **Check for Updates…** in the installed app.
The existing signed release is the bootstrap for version allocation; this workflow
intentionally does not create a first-ever feed. The manual release procedure below
remains available for recovery. Do not publish manually while automation is running.

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
