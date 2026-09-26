#!/bin/zsh
# Builds Adit for Release and installs it to /Applications.
#
# Signs with your Apple Development certificate when you have one, so macOS
# sees the same app across updates and "Always Allow" on the Keychain prompt
# sticks. Without one it falls back to ad-hoc signing, which works but asks
# again after every update.
set -euo pipefail
cd "$(dirname "$0")/.."

derived="${TMPDIR:-/tmp}/adit-install-build"
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
signing=()
if [[ -n "$identity" ]]; then
  team=$(security find-certificate -c "$identity" -p | openssl x509 -noout -subject | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')
  echo "Signing with $identity (team $team)"
  signing=(CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Manual)
else
  echo "No Apple Development certificate found; signing ad-hoc"
fi

xcodebuild -project Adit.xcodeproj -scheme Adit -configuration Release \
  -derivedDataPath "$derived" "${signing[@]}" build | grep -E "error:|BUILD" || true

app="$derived/Build/Products/Release/Adit.app"
[[ -d "$app" ]] || { echo "Build failed"; exit 1; }

if pgrep -xq Adit; then
  echo "Quitting the running Adit"
  # A plain quit signal: AppleScript would need Automation permission.
  pkill -x Adit || true
  for _ in {1..20}; do pgrep -xq Adit || break; sleep 0.1; done
fi
rm -rf /Applications/Adit.app
ditto "$app" /Applications/Adit.app
codesign -v /Applications/Adit.app && echo "Installed /Applications/Adit.app"
open /Applications/Adit.app
