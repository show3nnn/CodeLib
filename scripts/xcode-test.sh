#!/bin/bash
source "$(dirname "$0")/toolchain.sh"
xcodebuild -quiet -project CodePath.xcodeproj -scheme CodePath -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$PWD/.build/xcode" -clonedSourcePackagesDirPath "$PWD/.build/packages" \
    -skipPackageUpdates -resultBundlePath "$PWD/.build/xcui-$(date +%Y%m%d-%H%M%S).xcresult" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO test
