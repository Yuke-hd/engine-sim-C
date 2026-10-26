#!/bin/bash
# Builds EngineSimTester and installs + launches it on the connected iPhone.
set -euo pipefail
cd "$(dirname "$0")"

# Per-developer settings (see local.env.example); the environment overrides them.
[ -f local.env ] && source local.env
: "${BUNDLE_ID:?set BUNDLE_ID in local.env}"
: "${TEAM:?set TEAM (Apple development team ID) in local.env}"
: "${DEVICE:?set DEVICE (devicectl device UDID) in local.env}"

xcodebuild -project EngineSimTester.xcodeproj -scheme EngineSimTester \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath build -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" build | grep -E "error:|warning: .*EngineSimTester|BUILD" || true

APP=build/Build/Products/Release-iphoneos/EngineSimTester.app
[ -d "$APP" ] || { echo "build failed: $APP missing"; exit 1; }

xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID"
echo "INSTALL DONE"
