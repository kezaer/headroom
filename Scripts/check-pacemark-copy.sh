#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import re

tokens = re.compile(r'//[^\n]*|/\*.*?\*/|"""(.*?)"""|"((?:\\.|[^"\\\n])*)"', re.S)
for target in ('PacemarkApp', 'PacemarkCore', 'PacemarkSharedUI'):
    for path in (Path('Sources') / target).rglob('*.swift'):
        source = path.read_text()
        # Placeholder strings can live in provider extensions outside the UI directory.
        for match in re.finditer(r'"(?:sk-|xai-|Add [Ss]ource)[^"\n]*\.\.\.[^"\n]*"', source):
            number = source.count('\n', 0, match.start()) + 1
            raise SystemExit(f'{path}:{number}: use an ellipsis in the placeholder or action label')
        for match in tokens.finditer(source):
            literal = match.group(1) or match.group(2)
            if literal and ('UI' in path.parts or path.name == 'AboutLinks.swift'):
                if re.search(r"\w'\w|\.\.\.", literal):
                    number = source.count('\n', 0, match.start()) + 1
                    raise SystemExit(f'{path}:{number}: use a curly apostrophe or ellipsis in display copy')
import subprocess

credit = "Pacemark by Nikolai Fateev is a GPL-3.0 modified version of Headroom by Kyle Zantos."
allowed = {
    "Sources/PacemarkApp/PacemarkImportNotice.swift": (
        '"com.kylezantos.headroom"', '"Quit Headroom"', '"Imported your settings and accounts from Headroom."',
        '"If Headroom opens at login, its login item stays until you remove it in System Settings."',
        '"Headroom is running. Both apps will read the same accounts."',),
    "Sources/PacemarkApp/UI/Settings/AboutPane.swift": ('"Based on Headroom by Kyle Zantos."',),
    "project.yml": ('"Copyright © 2026 Nikolai Fateev. Based on Headroom by Kyle Zantos. GPL-3.0."',),
    "Pacemark.xcodeproj/project.pbxproj": ('"Copyright © 2026 Nikolai Fateev. Based on Headroom by Kyle Zantos. GPL-3.0."',),
    "Sources/PacemarkCore/Providers/AccountStorage.swift": ('static let sharedSupportFolder = "Headroom"',),
    "Sources/PacemarkCore/Models/AccountIdentity.swift": ('"headroom.identity.v',),
    "Sources/PacemarkCore/Credentials/CredentialModels.swift": (
        '"Headroom OpenAI Admin API Key"', '"Headroom Anthropic Admin API Key"', '"Headroom xAI Management API Key"',),
    "Sources/PacemarkCore/Engine/PacemarkImport.swift": ('"co.zantos.headroom.bench."',),
    "Tests/PacemarkCoreTests/PacemarkImportTests.swift": ('"co.zantos.headroom.bench."',),
}
historical = ("BUGS.md", "docs/solutions/")
result = subprocess.run(["git", "grep", "-inE", "headroom|zantos"], capture_output=True, text=True)
if result.returncode not in (0, 1):
    raise SystemExit(result.stderr)
for record in result.stdout.splitlines():
    path, number, line = record.split(":", 2)
    if path in ("LICENSE", "NOTICE", "Scripts/check-pacemark-copy.sh") or path.startswith(historical):
        continue
    if path == "README.md" and line.startswith(credit) and not re.search(r"headroom|zantos", line[len(credit):], re.I):
        continue
    if path == "Scripts/clean-test-preferences.sh" and re.fullmatch(r"(?:co\.zantos\.headroom\.|headroom\.|HeadroomT3)[\w.-]+", line):
        continue
    for literal in allowed.get(path, ()):
        line = line.replace(literal, "")
    if re.search(r"headroom|zantos", line, re.I):
        raise SystemExit(f"{path}:{number}: unexpected legacy reference")
PY
