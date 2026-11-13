#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/xcode-build.sh SWIFT_EMIT_LOC_STRINGS=YES
PYTHONDONTWRITEBYTECODE=1 python3 scripts/generate_ui_localization.py --extract
# Validate with Apple's real String Catalog compiler; products remain developer-only.
source scripts/toolchain.sh
mkdir -p .build/localization-ui-check
xcrun xcstringstool compile --output-directory .build/localization-ui-check localization/ui/Localizable.xcstrings
