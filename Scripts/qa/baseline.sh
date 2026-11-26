#!/bin/bash
set -eu
[[ $# == 2 && $1 == approve ]] || { echo 'Usage: baseline.sh approve <complete-run-directory>' >&2; exit 2; }
exec python3 - "$2" <<'PY'
import json
from pathlib import Path
import shutil
import sys
import tempfile
run = Path(sys.argv[1])
root = Path.home() / "Library/Application Support/Pacemark/QA"
root.mkdir(parents=True, exist_ok=True)
target = root / "baseline"
reports = sorted(run.glob("*.check.json"))
if not (run / "complete").exists() or not reports:
    sys.exit("Approval requires a complete run with passing layout checks")
with tempfile.TemporaryDirectory(dir=root) as staging:
    captures = Path(staging) / "baseline"
    captures.mkdir()
    for file in reports:
        report = json.loads(file.read_text())
        if report["violations"]:
            sys.exit(f"Layout violations in {file.name}")
        shutil.copyfile(run / file.name.replace(".check.json", ".png"), captures / file.name.replace(".check.json", ".png"))
    if target.exists():
        target.rename(Path(staging) / "previous")
    try:
        captures.rename(target)
    except OSError:
        previous = Path(staging) / "previous"
        if previous.exists():
            previous.rename(target)
        raise
print(target)
PY
