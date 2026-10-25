#!/bin/bash
# Compiles the macOS app icon (app/deploy/macos/icon/Artemis.icon, an Icon Composer file, the same
# file as the iPhone app's Artemis/AppIcon.icon) into the Assets.car and Artemis.icns that go into
# the bundle. app.pro runs it on every qmake run, so the bundle always carries the current .icon;
# the outputs aren't committed. Needs Xcode 26 or later.
#   generate-mac-icon.sh <output folder>
# actool needs the .icon as an absolute path (a relative one resolves against its helper's folder
# and fails).
set -euo pipefail
out="${1:?output folder}"
icon="$(cd "$(dirname "$0")/../app/deploy/macos/icon" && pwd)/Artemis.icon"
mkdir -p "$out"
rm -f "$out/Assets.car" "$out/Artemis.icns"
xcrun actool --compile "$out" --platform macosx --minimum-deployment-target 13.0 \
  --app-icon Artemis --output-partial-info-plist "$out/partial.plist" "$icon" >/dev/null
[[ -s "$out/Assets.car" && -s "$out/Artemis.icns" ]] || { echo "actool wrote no icon" >&2; exit 1; }
