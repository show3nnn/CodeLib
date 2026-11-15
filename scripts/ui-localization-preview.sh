#!/bin/bash
# Developer-only English draft preview in an isolated debug app and data directory.
source "$(dirname "$0")/toolchain.sh"
export PYTHONDONTWRITEBYTECODE=1
python3 scripts/generate_ui_localization.py --check
PREVIEW="$PWD/.build/localization-preview"
mkdir -p "$PREVIEW/catalog"
xcrun xcstringstool compile --output-directory "$PREVIEW/catalog" localization/ui/Localizable.xcstrings
export APP_OUTPUT="$PREVIEW/codelib.app"
CONFIGURATION=debug bash scripts/build.sh
ditto "$PREVIEW/catalog/en.lproj" "$APP_OUTPUT/Contents/Resources/en.lproj"
ditto "$PREVIEW/catalog/ru.lproj" "$APP_OUTPUT/Contents/Resources/ru.lproj"
codesign --force --sign - "$APP_OUTPUT"
codesign --verify --deep --strict "$APP_OUTPUT"
RUN="$(mktemp -d "$PREVIEW/run.XXXXXXXX")"
mkdir -p "$RUN/data" "$RUN/screenshots"
export CODEPATH_DATA_DIR="$RUN/data"
export CODEPATH_LOCALIZATION_SOURCE="$PWD"
"$APP_OUTPUT/Contents/MacOS/CodePath" --ui-smoke-test "$RUN/screenshots" --localization-preview "$@"
echo "Developer-only localization report and screenshots: $RUN/screenshots"
