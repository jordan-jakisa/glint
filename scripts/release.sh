#!/bin/zsh
# Builds a signed, notarized Glint DMG for a GitHub release, and fills in the
# Homebrew cask with its version and checksum.
#
# Needs, once (see docs/RELEASING.md):
#   - a "Developer ID Application" certificate in your login keychain
#   - notarytool credentials saved as a keychain profile:
#       xcrun notarytool store-credentials glint-notary --apple-id <you> --team-id <TEAM>
#
# Usage: scripts/release.sh            (profile defaults to glint-notary)
#        NOTARY_PROFILE=other scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

profile="${NOTARY_PROFILE:-glint-notary}"
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
[[ -n "$identity" ]] || { echo "No Developer ID Application certificate found. See docs/RELEASING.md."; exit 1; }
team=$(echo "$identity" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')
version=$(xcodebuild -project Glint.xcodeproj -scheme Glint -showBuildSettings 2>/dev/null | sed -n 's/^ *MARKETING_VERSION = //p' | head -1)
echo "Releasing Glint $version, signed by $identity"

work="${TMPDIR:-/tmp}/glint-release"
rm -rf "$work" && mkdir -p "$work"
archive="$work/Glint.xcarchive"

xcodebuild -project Glint.xcodeproj -scheme Glint -configuration Release -skipPackagePluginValidation \
  -archivePath "$archive" -derivedDataPath "$work/derived" archive \
  CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Manual \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" | grep -E "error:|ARCHIVE" || true

app="$archive/Products/Applications/Glint.app"
[[ -d "$app" ]] || { echo "Archive failed"; exit 1; }
codesign --verify --deep --strict --verbose=2 "$app"

# The disk image: the app and a shortcut to /Applications to drag it onto.
stage="$work/dmg"
mkdir -p "$stage"
ditto "$app" "$stage/Glint.app"
ln -s /Applications "$stage/Applications"
dmg="$work/Glint-$version.dmg"
hdiutil create -volname "Glint" -srcfolder "$stage" -format UDZO -ov "$dmg" >/dev/null
codesign --sign "$identity" --timestamp "$dmg"

echo "Notarizing (this takes a few minutes)"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"

mkdir -p dist
cp "$dmg" dist/
sha=$(shasum -a 256 "dist/Glint-$version.dmg" | cut -d' ' -f1)
sed -e "s/version \".*\"/version \"$version\"/" -e "s/sha256 \".*\"/sha256 \"$sha\"/" \
  packaging/homebrew/glint.rb > dist/glint.rb

echo
echo "Done: dist/Glint-$version.dmg (sha256 $sha)"
echo "Cask with this version and checksum: dist/glint.rb"
echo "Next: docs/RELEASING.md, from \"Publish\"."
