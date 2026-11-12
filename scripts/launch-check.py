#!/usr/bin/env python3
"""Release-bundle launch probe, isolated from real learning data. Not a visual acceptance test."""
import json
import os
from pathlib import Path
import subprocess
import uuid

root = Path(__file__).resolve().parents[1]
run = root / ".build/release-launch" / str(uuid.uuid4())
run.mkdir(parents=True)
app = root / "dist/codelib.app/Contents/MacOS/CodePath"
env = dict(os.environ, CODEPATH_DATA_DIR=str(run / "data"))
process = subprocess.Popen([str(app)], cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    stdout, stderr = process.communicate(timeout=3)
    success = False
except subprocess.TimeoutExpired:
    success = True
    process.terminate()
    stdout, stderr = process.communicate(timeout=10)
report = dict(stayedAliveForThreeSeconds=success, returnCodeAfterTestTermination=process.returncode,
              stdout=stdout, stderr=stderr, visualAcceptance=False)
(run / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(report, ensure_ascii=False, indent=2))
raise SystemExit(0 if success else 1)
