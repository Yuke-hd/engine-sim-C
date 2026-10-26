#!/bin/bash
# Builds, signs and installs EngineSimTester without xcodebuild (whose build
# service hangs on this machine). Needs an existing provisioning profile for
# the bundle ID, which Xcode creates on its first -allowProvisioningUpdates run.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)

# Per-developer settings (see local.env.example); the environment overrides them.
[ -f local.env ] && source local.env
: "${BUNDLE_ID:?set BUNDLE_ID in local.env}"
: "${IDENTITY:?set IDENTITY (codesigning identity) in local.env}"
: "${DEVICE:?set DEVICE (devicectl device UDID) in local.env}"
TARGET=arm64-apple-ios17.0
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
OUT=build/manual
# Outside ~/Documents: iCloud's file provider tags bundles there with FinderInfo,
# which codesign rejects.
APP=${TMPDIR:-/tmp}/EngineSimTester-manual/EngineSimTester.app
rm -rf "$APP"
rm -rf "$OUT/obj"; mkdir -p "$OUT/obj" "$OUT/mod" "$APP"

echo "== compiling C++ core"
SOURCES=$(cd "$ROOT" && python3 -c "import re;print('\n'.join(re.findall(r'\"((?:src|swift)/[a-z_0-9]+\.cpp)\"', open('Package.swift').read())))")
SOURCES="$SOURCES
$(cd "$ROOT" && ls dependencies/submodules/simple-2d-constraint-solver/src/*.cpp)"
export ROOT TARGET SDK OUT
echo "$SOURCES" | xargs -P 8 -n 1 bash -c '
    src=$1; obj="$OUT/obj/$(echo "$src" | tr / _).o"
    xcrun clang++ -target $TARGET -isysroot "$SDK" -std=c++17 -O2 \
        -D__forceinline=inline -include string.h -fdelayed-template-parsing \
        -I"$ROOT/include" -I"$ROOT/swift" -I"$ROOT/swift/include" \
        -c "$ROOT/$src" -o "$obj" 2>&1 | grep -E "error" || true
    [ -f "$obj" ] || { echo "failed: $src"; exit 255; }' _

echo "== compiling Swift app"
cat > "$OUT/mod/module.modulemap" <<EOF
module EngineSimCore {
    header "$ROOT/swift/include/EngineSimCore.h"
    export *
}
EOF
SDKROOT="$SDK" xcrun swiftc -target $TARGET -sdk "$SDK" -O -parse-as-library \
    -I "$OUT/mod" EngineSimTester/*.swift "$OUT"/obj/*.o -lc++ \
    -o "$APP/EngineSimTester"

echo "== bundling"
cp -R EngineSimTester/Overrun "$APP/Overrun"
cat > "$APP/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>EngineSimTester</string>
    <key>CFBundleName</key><string>EngineSimTester</string>
    <key>CFBundleDisplayName</key><string>Engine Sim</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
    <key>DTPlatformName</key><string>iphoneos</string>
    <key>MinimumOSVersion</key><string>17.0</string>
    <key>LSRequiresIPhoneOS</key><true/>
    <key>UIDeviceFamily</key><array><integer>1</integer></array>
    <key>UILaunchScreen</key><dict/>
    <key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
</dict>
</plist>
EOF

PROFILE=""
for f in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision; do
    # Capture first: with pipefail, grep -q closing the pipe early fails the test.
    contents=$(security cms -D -i "$f" 2>/dev/null || true)
    if [[ $contents == *".$BUNDLE_ID<"* ]]; then PROFILE=$f; fi
done
[ -n "$PROFILE" ] || { echo "no provisioning profile for $BUNDLE_ID"; exit 1; }
cp "$PROFILE" "$APP/embedded.mobileprovision"
security cms -D -i "$PROFILE" > "$OUT/profile.plist"
/usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$OUT/profile.plist" > "$OUT/entitlements.plist"

echo "== signing"
xattr -cr "$APP"
codesign -f -s "$IDENTITY" --entitlements "$OUT/entitlements.plist" "$APP"

echo "== installing"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" $BUNDLE_ID
echo "INSTALL DONE"
