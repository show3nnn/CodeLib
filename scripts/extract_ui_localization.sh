#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/xcode-build.sh SWIFT_EMIT_LOC_STRINGS=YES
PYTHONDONTWRITEBYTECODE=1 python3 scripts/generate_ui_localization.py --extract
# Validate with Apple's real String Catalog compiler; products remain developer-only.
source scripts/toolchain.sh
mkdir -p .build/localization-ui-check
xcrun xcstringstool compile --output-directory .build/localization-ui-check localization/ui/Localizable.xcstrings
# Exercise real compiled translations with the production plural selector, outside the app bundle.
xcrun swiftc -warnings-as-errors Sources/CodePath/PresentationLocale.swift Sources/CodePath/PluralPresentation.swift \
    scripts/check_ui_catalog_runtime.swift -o .build/localization-ui-check/catalog-runtime-check
.build/localization-ui-check/catalog-runtime-check "$PWD/.build/localization-ui-check/en.lproj"
