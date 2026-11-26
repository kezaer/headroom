"""Check every layout report before marking a live capture pass complete."""
import json
import sys
from pathlib import Path

run = Path(sys.argv[1])
reports = sorted(run.glob("*.check.json"))
failures = []
for path in reports:
    report = json.loads(path.read_text())
    if report["violations"]:
        failures.append(f"{path.name} has {len(report['violations'])} violations")
    if not path.with_name(path.name.replace(".check.json", ".png")).is_file():
        failures.append(f"{path.name} has no paired capture")
if not reports:
    failures.append("No measured captures")
if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(2)
print(f"{len(reports)} measured captures passed")
