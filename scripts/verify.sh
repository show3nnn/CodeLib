#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PYTHONDONTWRITEBYTECODE=1
python3 scripts/repository_check.py
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/generate_content.py --check
python3 scripts/generate_localization.py --check
python3 scripts/generate_achievement_sound.py --check
bash scripts/test.sh -Xswiftc -warnings-as-errors
python3 scripts/verify_content.py
bash scripts/ui-smoke.sh
bash scripts/build.sh
python3 scripts/launch-check.py
