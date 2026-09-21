# DesignSnippets for macOS

A native menu bar utility for bringing a GitHub project's semantic names into other apps. This is a separate desktop implementation; the React app remains the earlier browser prototype.

## Open the preview

Requires macOS 14+ and Xcode Command Line Tools. No npm packages are required for the desktop build.

```sh
npm run desktop:build
npm run desktop:open
```

The build produces `desktop/build/DesignSnippets.app`. Open it from Finder or copy it to Applications before granting permissions. Click the **#** icon in the menu bar. There is no Dock icon. Use the menu inside the panel, or right-click the menu bar icon, to quit.

The default build targets your Mac's architecture and uses an ad-hoc development signature. It is suitable for local testing, **not a signed and notarized public download**. Rebuilding an ad-hoc app can require granting Accessibility again. Do not rebuild a running copy.

## Try it before connecting GitHub

1. Open DesignSnippets and click **Explore with sample tokens**.
2. Open **Preferences**. **Use in all compatible apps** is on by default; no per-app selection is needed.
3. Click **Allow Accessibility**. Grant DesignSnippets access in System Settings → Privacy & Security → Accessibility yourself. Return to DesignSnippets; it rechecks permission and starts the picker automatically. If macOS requires it, quit and reopen DesignSnippets.
4. Open a blank TextEdit document, type `Update the border to #border`, and use Up/Down then Return to choose `--border-default`.
5. Suggestions open above the `#` (below if there is insufficient space). Continue typing to filter names; Backspace broadens the results. If caret/glyph bounds are unavailable, the picker appears near the input field and labels that approximate position. It never falls back to the mouse position. Without a selection range, Return copies the token for manual pasting rather than replacing text.
6. The picker replaces `#border` with `--border-default`. Escape dismisses the picker and leaves the typed text unchanged. A click outside or a focus change dismisses it too.
7. `Control + Option + Space` opens the picker without typing `#`. Text typed to filter is replaced with the chosen token.

The picker remembers whether you started or paused it and resumes on launch when Accessibility access is granted. It works across compatible apps by default; Preferences can optionally restrict it to selected apps. It refuses secure fields. Only recognized editable Accessibility text fields are supported; automatic insertion requires a readable caret range. DesignSnippets requests the Electron accessibility tree when an enabled app becomes active. Electron apps and web editors vary in how they expose Accessibility, so **ChatGPT, Cursor, and VS Code are target integrations, not certified compatibility claims**. If a field is unsupported, copy a token from the menu panel. The picker never presses Return in the destination and preserves the clipboard.

## GitHub: one-time developer setup

Create a **GitHub App**, not a traditional OAuth App, at [GitHub App registration](https://github.com/settings/apps/new).

- Set a name and a real homepage URL for your project.
- Enable **Device Flow** in the app's settings.
- Disable **Webhook / Active**; no webhook server is used.
- Grant only repository **Contents: Read-only**. GitHub adds read-only Metadata automatically. No write, organization, or account permissions are needed.
- Copy the public **Client ID** (not App ID) and app slug (`github.com/apps/<slug>`) into DesignSnippets → GitHub App setup.
- Install the GitHub App on **only the selected repositories** you want it to read.

Then click **Connect GitHub** in DesignSnippets, enter the displayed code in the GitHub browser page, and approve the connection yourself. Choose a repository in DesignSnippets, enter its repository-relative token file path, and click **Load design tokens**. For Protegia, keep the prefilled `src/styles/theme.css`. Add one path per line for multi-file systems. If it is missing, use **Manage repository access on GitHub**, install the app on the repository, and refresh the project list.

For distributable builds, the existing GitHub App's **public** Client ID and slug are saved in `desktop/github.json` (`clientID` and `appSlug`). These committed public identifiers are embedded automatically in subsequent builds. Environment variables can override them:

```sh
SEMANTIC_GITHUB_CLIENT_ID=Iv1.your_public_id \
SEMANTIC_GITHUB_APP_SLUG=your-app-slug \
npm run desktop:build
```

The release script rejects missing or malformed configuration before building or signing. Configured builds always use the embedded identifiers and hide developer setup, regardless of saved preview preferences. Only unconfigured development builds permit setup; those values are saved locally under the app's bundle identity and are not a substitute for release configuration.

No client secret, private key, or personal access token is placed in the binary. Device flow authorizes a GitHub App user token with the intersection of the user's access and the installation's permissions. Tokens are held only in process memory and discarded when DesignSnippets quits. Every launch starts signed out; GitHub may reuse your existing browser login during authorization. DesignSnippets never reads or writes Keychain credentials. Expired or revoked sessions require reconnecting; this preview does not implement server-assisted token refresh.

Sources: [GitHub device flow](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app#using-the-device-flow-to-generate-a-user-access-token), [installation repository access](https://docs.github.com/en/rest/apps/installations), [Git trees](https://docs.github.com/en/rest/git/trees).

## What it reads

- CSS custom properties and class selectors in CSS, SCSS, Sass, and Less.
- Nested token/theme/semantic JSON with `value` or `$value` leaves, including inherited `$type`.
- Only explicitly selected files from the repository default branch, read through GitHub’s Contents API at a pinned commit. No repository tree listing or scan is requested.
- Classes and variables retain source paths; same-named declarations in different files remain separate so theme variants aren't silently overwritten.

The parser is intentionally lightweight. It does not compile Sass, evaluate Tailwind/JavaScript configuration, resolve token aliases, compute cascade values, or watch repository changes. Use Refresh to rebuild the active index. Choose up to 20 files, each no larger than 1 MB. The selected paths are saved with the index and reused by Refresh. Use **Edit token files** to change them. Missing, unsupported, unreadable, or empty-definition files show a specific error and leave the previous index unchanged. Existing indices from older versions still load; their first refresh asks you to select files. CSS variables remain `--names`, classes retain their `.prefix`, and JSON token paths use dot notation.

Source files are processed in memory; only extracted token indices are cached under `~/Library/Application Support/Semantic/token-index.json`. GitHub account credentials are session-only and never written to disk or Keychain. Disconnect clears the in-memory session and cached definitions. Existing Keychain items from older builds are no longer accessed; the update does not delete them. Keystrokes are never written to disk or sent over the network. The prototype has no telemetry or AI execution.

## Verification

```sh
npm run desktop:test
npm run desktop:build
```

Tests cover stylesheet parsing, JSON token types and aliases, theme variants, unsafe token names, file exclusion, and mocked GitHub repository pagination, empty access lists, direct-file loading, path validation, cache migration, device-flow, and error responses. These do not replace a live GitHub authorization or a manual cross-app Accessibility test.

Before a public release, test live login/revocation and insertion in each supported application, build both architectures or a universal binary, supply a real application icon and release metadata, sign with an Apple Developer ID certificate, and notarize/staple the app. `SEMANTIC_SIGN_IDENTITY` can select an installed signing identity; the script defaults to an ad-hoc signature. The included package script makes a zip for local sharing, not notarization.

## Design system

The native interface uses **Protegia.sys** from design.protegia.io. The canonical token snapshot and mapping notes are bundled under `Resources/DesignSystem/`; reusable native styles live in `Sources/ProtegiaTheme.swift`. Lato fonts are bundled for offline use, with their license in `Resources/Fonts/OFL.txt`. All native screens and the floating picker share the dark theme. `scripts/render-design.swift` renders isolated UI fixtures without signing in or reading saved workspace data.

The project chooser loads `/user/repos` with the signed-in GitHub App token, including every returned page. It shows repository visibility and default branch and refreshes when the app becomes active after opening repository-access settings. GitHub still controls which private repositories the token can see.

## In-app updates

Sparkle is embedded in the native build. See [UPDATES.md](UPDATES.md) for feed
configuration, signing-key backup, notarization, and the release workflow. Until a
public feed is configured, local builds show updates as unavailable. Do not send
an unconfigured preview as the one-time updater installation.
