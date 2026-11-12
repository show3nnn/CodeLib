#!/bin/bash
source "$(dirname "$0")/toolchain.sh"
xcodebuild -quiet -project CodePath.xcodeproj -scheme CodePath -configuration Release \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$PWD/.build/xcode" \
    -clonedSourcePackagesDirPath "$PWD/.build/packages" -skipPackageUpdates \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
