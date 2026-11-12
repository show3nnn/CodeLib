#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PYTHONDONTWRITEBYTECODE=1
python3 scripts/generate_content.py --check
bash scripts/test.sh -Xswiftc -warnings-as-errors
python3 scripts/verify_content.py
bash scripts/ui-smoke.sh
bash scripts/build.sh
python3 scripts/launch-check.py
