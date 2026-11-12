#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -x dist/codelib.app/Contents/MacOS/CodePath ]; then
    bash scripts/build.sh
fi
# Development runs never create learning data outside the project.
export CODEPATH_DATA_DIR="$PWD/.local-data"
exec dist/codelib.app/Contents/MacOS/CodePath
