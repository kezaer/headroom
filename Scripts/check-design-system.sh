#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
exec python3 - <<'PY'
from pathlib import Path

import re
import sys

allow = []
for entry in Path("Scripts/design-system-allowlist.txt").read_text().splitlines():
    if entry and not entry.startswith("#"):
        path, rule, reason = entry.split("|")
        assert reason.strip() and "*" not in path + rule
        allow.append((path, rule))

number = r"-?(?!0(?:\.0+)?\b(?!\.))\d+(?:\.\d+)?"
checks = {
    "font": r"(?:\bFont|\.font\(\s*)\.system\(\s*size:\s*[^,)]+",
    "padding": r"\.padding\(\s*(?:(?:\.\w+|\[[^\]]+\]),\s*)?" + number +
               r"|\bEdgeInsets\([^)]*?\b(?:top|leading|bottom|trailing):\s*" + number,
    "spacing": r"\b(?:spacing|horizontalSpacing|verticalSpacing):\s*" + number,
    "colour": r"\bColor\(\s*(?:red|white):",
    "divider": r"\b(?:LedgerDivider|PDSDivider)\s*\(",
    "native-divider": r"\bDivider\s*\(",
    "help": r"\.help\(",
}
popover = {"UsageBarView", "IdentityRow", "APISpendSectionView", "ProviderCardView",
           "CompactAccountRow", "CopyFeedbackButton", "StatusSentence", "APISpendRow",
           "CardRowAction", "IdentityCapsule", "PlanCapsule", "SkeletonMeter", "MeterGauge"}
# Mask strings and comments together so a URL inside a Swift literal cannot end the line.
tokens = re.compile(r'"""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"|//[^\n]*|/\*[\s\S]*?\*/')
errors = []
for folder in ("Sources/PacemarkApp/UI", "Sources/PacemarkSharedUI"):
    for path in sorted(Path(folder).rglob("*.swift")):
        if path.name == "PDS.swift":
            continue
        code = tokens.sub(lambda m: re.sub(r"[^\n]", " ", m[0]), path.read_text())
        for rule, pattern in checks.items():
            if rule == "help" and "Ledger" not in path.parts and path.stem not in popover and not path.stem.startswith("Popover"):
                continue
            for match in re.finditer(pattern, code):
                if (str(path), rule) in allow:
                    continue
                if (str(path), "scaled-font") in allow and rule == "font" and re.search(r"size:\s*(?:[a-zA-Z]|\d+ \* scale)", match[0]):
                    continue
                n = code.count("\n", 0, match.start()) + 1
                errors.append(f"{path}:{n}: {rule}: {match[0].strip()}")
if errors:
    sys.exit("\n".join(errors))
print("Design system checks passed.")
PY
