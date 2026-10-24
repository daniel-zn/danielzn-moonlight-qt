#!/bin/bash
# Compiles the macOS app icon (app/deploy/macos/icon/Artemis.icon, an Icon Composer file) into
# the Assets.car and Artemis.icns that app.pro copies into the bundle. Needs Xcode 26 or later;
# run it after changing the .icon and commit both outputs. actool needs the .icon as an absolute path
# (a relative one resolves against its helper's folder and fails).
set -euo pipefail
cd "$(dirname "$0")/../app/deploy/macos/icon"
out="$(mktemp -d)"
xcrun actool --compile "$out" --platform macosx --minimum-deployment-target 13.0 \
  --app-icon Artemis --output-partial-info-plist "$out/partial.plist" "$PWD/Artemis.icon" >/dev/null
cp "$out/Assets.car" "$out/Artemis.icns" .
rm -rf "$out"
