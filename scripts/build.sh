#!/bin/bash
source "$(dirname "$0")/toolchain.sh"
CONFIGURATION="${CONFIGURATION:-release}"
swift_package build -c "$CONFIGURATION"
BIN="$(swift_package build -c "$CONFIGURATION" --show-bin-path)"
APP="${APP_OUTPUT:-$PWD/dist/codelib.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/CodePath" "$APP/Contents/MacOS/CodePath"
if [ -d "$APP/Contents/MacOS/CodePath_LearningCore.bundle" ]; then
    rm -r "$APP/Contents/MacOS/CodePath_LearningCore.bundle"
fi
# SwiftPM resolves Bundle.module under Bundle.main.resourceURL inside a macOS app.
for bundle in "$BIN"/*.bundle; do
    if [ -d "$bundle" ]; then
        ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
    fi
done
cp packaging/Info.plist "$APP/Contents/Info.plist"
bash scripts/package_execution.sh "$APP"
xcrun swift -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" scripts/generate_icon.swift "$PWD/.build"
xcrun iconutil --convert icns .build/CodePath.iconset --output "$APP/Contents/Resources/CodePath.icns"
if [[ "$CONFIGURATION" == "release" ]]; then
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/check_release_localization.py "$APP"
fi
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Собрано: $APP"
