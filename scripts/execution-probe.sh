#!/bin/bash
# Developer-only. Does not modify the app, global toolchain or user progress.
source "$(dirname "$0")/toolchain.sh"
if [[ "$(uname -m)" != arm64 ]]; then
    echo "This probe currently requires Apple silicon." >&2
    exit 1
fi
export PYTHONDONTWRITEBYTECODE=1
python3 scripts/execution_probe/image.py
xcrun swiftc -parse-as-library -swift-version 6 -warnings-as-errors \
    -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" \
    Sources/ExecutionSupport/ExecutionProtocol.swift Sources/ExecutionSupport/ExecutionAssets.swift \
    Sources/ExecutionHelper/Helper.swift -o .build/execution-probe/helper
codesign --force --sign - --options runtime --identifier local.codelib.execution-helper --entitlements scripts/execution_probe/entitlements.plist \
    .build/execution-probe/helper
codesign --verify --strict .build/execution-probe/helper
python3 scripts/execution_probe/test.py "$@"
