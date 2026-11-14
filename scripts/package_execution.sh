#!/bin/bash
# Called by both native Xcode and SwiftPM packaging. No runtime downloads in app.
source "$(dirname "$0")/toolchain.sh"
APP="${1:?app bundle required}"
if [[ "$(uname -m)" != arm64 ]]; then
    echo "The execution backend currently supports Apple silicon only." >&2
    exit 1
fi
export PYTHONDONTWRITEBYTECODE=1
python3 scripts/execution_probe/image.py
mkdir -p "$APP/Contents/Helpers" "$APP/Contents/Resources/ExecutionGuest"
xcrun swiftc -parse-as-library -swift-version 6 -warnings-as-errors -O \
    -target arm64-apple-macos26.0 -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" \
    Sources/ExecutionSupport/ExecutionProtocol.swift Sources/ExecutionSupport/ExecutionAssets.swift \
    Sources/ExecutionHelper/Helper.swift -o "$APP/Contents/Helpers/CodelibExecutionHelper"
codesign --force --sign - --options runtime --identifier local.codelib.execution-helper \
    --entitlements scripts/execution_probe/entitlements.plist "$APP/Contents/Helpers/CodelibExecutionHelper"
cp .build/execution-probe/Image .build/execution-probe/initrd.gz "$APP/Contents/Resources/ExecutionGuest/"
cp packaging/ExecutionThirdParty.txt "$APP/Contents/Resources/ExecutionGuest/"
"$APP/Contents/Helpers/CodelibExecutionHelper" --verify-assets "$APP/Contents/Resources/ExecutionGuest"
