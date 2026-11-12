#!/bin/bash
# Source from project-root scripts; keep tool caches in the repository.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
export XDG_CACHE_HOME="$PWD/.build/cache"
mkdir -p .build/clang-cache .build/swift-cache .build/cache .build/config .build/security
swift_package() {
    xcrun swift "$1" --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" "${@:2}"
}
