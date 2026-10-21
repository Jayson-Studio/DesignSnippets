# Project workflow

## Delivering app changes

After changing DesignSnippets, run the relevant checks, commit and push the source,
then publish a signed and notarized release through the built-in Sparkle updater.
This is the preferred way for the user to view updates. Follow `desktop/UPDATES.md`
for version/build allocation, signing, notarization, publication, and verification.
A source push alone does not deliver an app update. Verify the public archive and
the exact latest appcast URL before reporting the update ready.

Do not replace the Applications copy or launch a development build as the normal
handoff. Never rebuild or replace a bundle while that copy is running. Leave the
installed app in place so the user can choose **Check for Updates…** and install.

The app must launch quietly in the menu bar, including after an update. Open the
main panel only when the user requests it.

## Browser preference

For browser actions or user-provided web links, use the visible native in-app
browser (`iab`) and reuse a suitable tab. Use another browser only if requested;
if the native browser is unavailable, explain the blocker before switching.
