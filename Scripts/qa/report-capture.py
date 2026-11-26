"""Append measured layout and blurred-pixel differences to a contact sheet."""
import html
import json
from pathlib import Path
import subprocess
import sys

shot = Path(sys.argv[1])
report = json.loads(shot.with_suffix(".check.json").read_text())
baseline = Path.home() / "Library/Application Support/Pacemark/QA/baseline"
reference = baseline / shot.name
notes = list(report["violations"])
if reference.exists():
    diff = shot.with_suffix(".diff.png")
    command = ["magick", "(", str(reference), "-blur", "0x1", ")", "(", str(shot), "-blur", "0x1", ")",
               "-compose", "difference", "-composite", "-colorspace", "gray", "-threshold", "4%",
               "-write", str(diff), "-format", "%[fx:mean]", "info:"]
    score = float(subprocess.check_output(command, text=True))
    shot.with_suffix(".diff.json").write_text(json.dumps({"changedPixelFraction": score}))
    if score > 0:
        notes.append(f"Changed {score:.3%} of pixels")
    diff_link = f'<a href="{diff.name}">Diff</a>'
else:
    notes.append("Missing reference" if baseline.exists() else "First baseline pending")
    diff_link = ""
with shot.with_name("index.html").open("a") as sheet:
    sheet.write(f'<figure><a href="{shot.name}"><img src="{shot.name}"></a><figcaption>{shot.stem} '
                f'<a href="{shot.stem}.check.json">Measurements</a> {diff_link}<ul>' + "".join(f"<li>{html.escape(note)}</li>" for note in notes) + "</ul></figcaption></figure>\n")
sys.exit(bool(report["violations"]))
