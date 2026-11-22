#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export APP_OUTPUT="$PWD/.build/acceptance/codelib.app"
CONFIGURATION=debug bash scripts/build.sh
# Fresh isolated progress every run: acceptance never touches learner data.
RUN="$(mktemp -d "$PWD/.build/acceptance/run-$(date +%Y%m%d-%H%M%S)-XXXXXX")"
mkdir -p "$RUN/data" "$RUN/screenshots"
export CODEPATH_DATA_DIR="$RUN/data"
"$APP_OUTPUT/Contents/MacOS/CodePath" --acceptance-run "$RUN/screenshots"
echo "Acceptance artifacts: $RUN/screenshots"
echo "Open $RUN/screenshots/SUMMARY.md"
