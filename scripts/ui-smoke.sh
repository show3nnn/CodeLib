#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export APP_OUTPUT="$PWD/.build/ui-smoke/codelib.app"
CONFIGURATION=debug bash scripts/build.sh
# New directory on every run; never reset existing user data.
RUN="$PWD/.build/ui-smoke/run-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN/data" "$RUN/screenshots"
export CODEPATH_DATA_DIR="$RUN/data"
"$APP_OUTPUT/Contents/MacOS/CodePath" --ui-smoke-test "$RUN/screenshots"
"$APP_OUTPUT/Contents/MacOS/CodePath" --ui-smoke-test "$RUN/screenshots" --reopen
echo "UI reports and screenshots: $RUN/screenshots"
