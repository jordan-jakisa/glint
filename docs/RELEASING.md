# Releasing Glint

Glint ships as a signed, notarized DMG on GitHub Releases, plus a Homebrew cask
in a tap. It isn't on the Mac App Store: that needs the App Sandbox, which would
cut Glint off from your git, SSH keys, and shell.

## Once

1. Join the Apple Developer Program, then in Xcode > Settings > Accounts >
   Manage Certificates, add a **Developer ID Application** certificate.
2. Save notarization credentials to your keychain (make an app-specific password
   at appleid.apple.com first):

   ```bash
   xcrun notarytool store-credentials glint-notary --apple-id <your Apple ID> --team-id <TEAM ID>
   ```

3. Create the tap repository `jordan-jakisa/homebrew-tap` with a `Casks/`
   folder.

## Each release

1. Set `MARKETING_VERSION` (and bump `CURRENT_PROJECT_VERSION`) in the project,
   and move the changelog's "unreleased" heading to the version and date.
2. Build, sign, notarize, and staple:

   ```bash
   scripts/release.sh
   ```

   It writes `dist/Glint-<version>.dmg` and `dist/glint.rb`, the cask with the
   new version and checksum.

## Publish

1. Tag and create the release with the DMG:

   ```bash
   git tag v0.1.0 && git push origin v0.1.0
   gh release create v0.1.0 dist/Glint-0.1.0.dmg --title "Glint 0.1.0" --notes-file CHANGELOG.md
   ```

2. Copy `dist/glint.rb` to `Casks/glint.rb` in the tap and push it. Then
   `brew install --cask jordan-jakisa/tap/glint` installs it.
