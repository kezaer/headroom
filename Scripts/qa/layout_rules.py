"""Measure layout from capture-relative Accessibility frames and the paired PNG."""

import json
import re
import struct
import subprocess
import sys
from collections import defaultdict
from pathlib import Path


def table_column(node, centers):
    if node["id"] in ("minus.circle", "ellipsis"):
        return len(centers)
    midpoint = node["x"] + node["w"] / 2
    return min(range(len(centers)), key=lambda index: abs(centers[index] - midpoint))


def check(path, report):
    nodes = report["geometry"]
    for node in nodes:
        if node["role"] == "AXTextField" and not node["title"]:
            node["title"] = node.get("placeholder", "")
        if node["role"] == "AXDateTimeArea" and not node["title"]:
            node["title"] = "Time of day"
    width, height = nodes[0]["w"], nodes[0]["h"]
    measurements = report["measurements"] = []
    violations = report["violations"]

    def record(rule, label, value, passes):
        measurements.append({"rule": rule, "label": label, "value": round(value, 3)})
        if not passes:
            violations.append(f"{rule} {label}: {value:.2f}")

    def right(n):
        return n["x"] + n["w"]

    def bottom(n):
        return n["y"] + n["h"]

    def visible(n):
        if n["y"] < 0 or bottom(n) > height or n["x"] < 0 or right(n) > width:
            return False
        parent = n["parent"]
        while parent >= 0:
            ancestor = nodes[parent]
            if ancestor["role"] == "AXScrollArea" and (
                n["y"] < ancestor["y"] or bottom(n) > bottom(ancestor)
            ):
                return False
            parent = ancestor["parent"]
        return True

    groups = defaultdict(list)
    for i, n in enumerate(nodes):
        groups[n["parent"]].append(i)
    rows = [n for n in nodes if n["role"] == "AXRow"]
    brand = next((n for n in nodes if n["title"].startswith("Pacemark, v")), None)
    if rows and brand:
        gap = rows[0]["y"] - bottom(brand)
        record("B12", "Sidebar header to list (pt)", gap, abs(gap - 12) <= 1)

    for i, card in enumerate(nodes):
        if card["id"] != "pds.card" and not card["id"].startswith("popover.card."):
            continue
        children = [nodes[j] for j in groups[i]]
        items = [n for n in children if n["id"] == "pds.item"]
        header = [
            n
            for n in children
            if items
            and n["y"] < items[0]["y"]
            and n["role"] in ("AXHeading", "AXStaticText", "AXButton", "AXCheckBox", "AXMenuButton")
        ]
        if header and all(visible(n) for n in header) and card["y"] >= 0:
            above = min(n["y"] for n in header) - card["y"]
            below = items[0]["y"] - max(bottom(n) for n in header)
            record(
                "B9",
                header[0]["title"] + " header padding difference (pt)",
                abs(above - below),
                abs(above - below) <= 1,
            )
            record(
                "B9",
                header[0]["title"] + " minimum header padding (pt)",
                min(above, below),
                min(above, below) >= 8,
            )
        edges = []
        for j in groups[i]:
            row = nodes[j]
            form = row["id"] == "pds.row" or any(
                n["id"] == "pds.form.bounds" and n["y"] <= row["y"] and bottom(row) <= bottom(n)
                for n in children
            )
            if form and row["role"] == "AXGroup" and visible(row):
                controls = [
                    nodes[k]
                    for k in groups[j]
                    if nodes[k]["role"]
                    in ("AXButton", "AXCheckBox", "AXRadioGroup", "AXPopUpButton", "AXMenuButton")
                ]
                if controls:
                    trailing = max(controls, key=right)
                    edges.append((trailing["title"], right(trailing)))
        for n in children:
            if visible(n) and n["id"] == "minus.circle" and n["title"].startswith("Remove"):
                edges.append((n["title"], right(n)))
        if len(edges) > 1:
            for title, x in edges:
                delta = max(edge for _, edge in edges) - x
                record("B7", title + " trailing alignment (pt)", delta, delta <= 1)

        for picker in (n for n in nodes if n["role"] == "AXPopUpButton" and n["title"] in ("First tile", "Second tile")):
            if visible(picker) and card["y"] <= picker["y"] < bottom(card):
                expected = (card["w"] - 2 * 12 - 8) / 2
                record("B7", picker["title"] + " column width difference (pt)", abs(picker["w"] - expected),
                       abs(picker["w"] - expected) <= 1)

        heights = defaultdict(list)
        for marker in (n for n in children if n["id"] == "pds.form.bounds" and visible(n)):
            rows_here = [
                j
                for j in groups[i]
                if nodes[j]["role"] == "AXGroup"
                and nodes[j]["y"] >= marker["y"]
                and bottom(nodes[j]) <= bottom(marker)
            ]
            for row_index in rows_here:
                leaves = [nodes[k] for k in groups[row_index]]
                labels = [n for n in leaves if n["role"] == "AXStaticText"]
                if labels:
                    kind = (
                        "stacked controls"
                        if any(n["role"] == "AXDateTimeArea" for n in leaves)
                        else ("form with help" if len(labels) > 1 else "form single line")
                    )
                    heights[kind].append((labels[0]["title"], marker["h"]))
        for item in items:
            if not visible(item):
                continue
            members = [
                n
                for n in children
                if n["role"] in ("AXStaticText", "AXLink", "AXButton", "AXGroup")
                and n["y"] >= item["y"]
                and bottom(n) <= bottom(item)
            ]
            if len(members) == 1:
                n = members[0]
                if n["role"] == "AXStaticText" and n["h"] <= 17 or n["role"] == "AXLink":
                    heights["one line"].append((n["title"], item["h"]))
        for entries in heights.values():
            for title, h in entries:
                delta = max(v for _, v in entries) - h
                record("B10", title + " same-kind row height difference (pt)", delta, delta <= 1)

        # The visible column headings define the table. Group related content
        # (such as the account name and plan) before comparing adjacent columns.
        first = next((n for n in children if n["role"] == "AXStaticText" and n["title"] == "ACCOUNT"), None)
        if first:
            headings = sorted(
                (n for n in children if n["role"] == "AXStaticText" and abs(n["y"] - first["y"]) <= 1),
                key=lambda n: n["x"],
            )
            centers = [n["x"] + n["w"] / 2 for n in headings]

            cells = [
                n
                for n in children
                if visible(n)
                and n["y"] >= bottom(first)
                and n["role"] in ("AXTextField", "AXStaticText", "AXMenuButton", "AXCheckBox", "AXButton")
            ]
            for left in cells:
                neighbor = min(
                    (
                        n
                        for n in cells
                        if n["x"] > left["x"]
                        and table_column(n, centers) > table_column(left, centers)
                        and left["y"] < bottom(n)
                        and bottom(left) > n["y"]
                    ),
                    key=lambda n: n["x"],
                    default=None,
                )
                if neighbor:
                    gap = neighbor["x"] - right(left)
                    record("B11", left["title"] + " to " + neighbor["title"] + " (pt)", gap, gap >= 8)
        fields = [n for n in children if n["role"] == "AXTextField" and visible(n)]
        for menu in (n for n in children if n["role"] == "AXMenuButton" and visible(n)):
            neighbors = [
                n for n in fields if n["x"] >= right(menu) and n["y"] < bottom(menu) and bottom(n) > menu["y"]
            ]
            if neighbors:
                gap = min(n["x"] for n in neighbors) - right(menu)
                record("B11", menu["title"] + " to next field (pt)", gap, gap >= 8)

    # Sample the local control interior, avoiding rounded borders and adjacent chrome.
    # The median represents the substrate; use the stronger light/dark glyph extreme.
    pixels = subprocess.check_output(["magick", str(path), "-colorspace", "sRGB", "-depth", "8", "rgb:-"])
    with open(path, "rb") as png:
        png.seek(16)
        pw, ph = struct.unpack(">II", png.read(8))
    scale = pw / width
    if abs(ph - height * scale) > 1 or len(pixels) != pw * ph * 3:
        raise ValueError("Capture dimensions do not match the measured accessibility window")
    linear = [
        v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in (i / 255 for i in range(256))
    ]
    # Read actual painted words in addition to AX frames. This separates chips,
    # values and text inside compound controls which share one accessibility node.
    helper = Path(__file__).resolve().parents[2] / "Tools/PacemarkQA/.build/debug/PacemarkQA"
    try:
        payload = subprocess.check_output([helper, "words", str(path)], text=True, timeout=5)
    except subprocess.TimeoutExpired:
        payload = subprocess.check_output([helper, "words-fast", str(path)], text=True, timeout=30)
    words = json.loads(payload)
    def color(x, y):
        i = (round(y * scale) * pw + round(x * scale)) * 3
        return pixels[i:i + 3]

    def luminance(rgb):
        return sum(weight * linear[channel] for weight, channel in zip((0.2126, 0.7152, 0.0722), rgb))

    def words_in(node):
        return [word for word in words
                if node["x"] <= (word["x"] + word["w"] / 2) * width <= right(node)
                and node["y"] <= (word["y"] + word["h"] / 2) * height <= bottom(node)]

    pose = Path(path).stem
    for n in nodes:
        if not visible(n):
            continue
        if n["role"] == "AXRadioGroup" and n["title"] == "Active hours":
            controls = [m for m in nodes if m["parent"] == n["parent"] and m["role"] == "AXDateTimeArea"]
            frames = [m for m in nodes if m["id"] == "pds.form.bounds"
                      and m["y"] <= n["y"] and bottom(m) >= bottom(n)]
            if controls and frames:
                frame = min(frames, key=lambda m: m["h"])
                above = n["y"] - frame["y"]
                below = bottom(frame) - max(bottom(m) for m in controls)
                record("B10", f"Active hours padding {above:g} above, {below:g} below (pt)",
                       abs(above - below), abs(above - below) <= 1)
        if n["id"].startswith("warmUp.") and n["role"] == "AXCheckBox" and n["enabled"]:
            cx, cy = n["x"] + n["w"] / 2, n["y"] + n["h"] / 2
            bg = luminance(color(n["x"] - 2, cy)) + 0.05
            sides = []
            for x, y, dx, dy in [(n["x"], cy, 1, 0), (right(n), cy, -1, 0),
                                 (cx, n["y"], 0, 1), (cx, bottom(n), 0, -1)]:
                edge = [luminance(color(x + dx * i / scale, y + dy * i / scale)) + 0.05
                        for i in range(-1, round(3 * scale))]
                sides.append(max(max(v / bg, bg / v) for v in edge))
            ratio = min(sides)
            record("B8", n["id"] + " checkbox outline", ratio, ratio >= 3)
        if n["role"] == "AXDateTimeArea" and n["title"] in ("From", "to"):
            value = "".join(w["text"] for w in words_in(n)).replace(" ", "")
            complete = bool(re.fullmatch(r"[0-9]{1,2}:[0-9]{2}(?:[AaPp][Mm])?", value))
            if pose.startswith("warmUp-twelve-hour"):
                expected = "7:00AM" if n["title"] == "From" else "11:00PM"
                complete = value.upper().lstrip("0") == expected
            record("B6", n["title"] + " painted time " + value, n["w"], complete)
        if n["role"] == "AXButton" and n["title"] in ("What’s used", "What’s left"):
            # The art is above the swatch caption. Its number, percent and unit share a baseline.
            parts = [w for w in words_in(n) if (w["y"] + w["h"] / 2) * height < n["y"] + n["h"] * 0.62]
            ink_height = (max((w["y"] + w["h"] for w in parts), default=0)
                          - min((w["y"] for w in parts), default=0)) * height
            record("B6", n["title"] + " numeric line height (pt)", ink_height,
                   any(any(c.isdigit() for c in w["text"]) for w in parts) and 0 < ink_height <= 16)
        if n["id"] == "pds.table.chip":
            menu = next((m for m in nodes if m["role"] == "AXMenuButton" and m["x"] >= right(n)
                         and m["y"] < bottom(n) and bottom(m) > n["y"]), None)
            if menu:
                # At mid-height, walk from exposed card stock back into the solid capsule.
                cy = n["y"] + n["h"] / 2
                bg = color(right(n) + 2, cy)
                edge = next((right(n) + 1 - i / scale for i in range(round(n["w"] * scale / 2))
                             if max(abs(a-b) for a,b in zip(bg, color(right(n) + 1 - i / scale, cy))) >= 4), None)
                gap = menu["x"] - (edge + 1 / scale) if edge is not None else 0
                record("B11", "Painted capsule to window control (pt)", gap, gap >= 8)

    for prefix, marker in (("warmUp", "Active hours"), ("notifications", "Add reminder")):
        for state in ("enabled", "disabled"):
            if pose.startswith(f"{prefix}-{state}-"):
                present = any(marker.lower() in n["title"].lower() for n in nodes)
                record("Dependent controls", prefix + " " + state, int(present), present == (state == "enabled"))

    visible_nodes = [n for n in nodes if visible(n) and n["title"]]
    painted = []
    for word in words:
        token = word["text"].casefold().strip(".,:;()")
        if len(token) < 2 and not token.isdigit():
            continue
        box = {k: word[k] * (width if k in ("x", "w") else height) for k in ("x", "y", "w", "h")}
        x, y = box["x"] + box["w"] / 2, box["y"] + box["h"] / 2
        containing = [n for n in visible_nodes if n["x"] <= x <= right(n) and n["y"] <= y <= bottom(n)]
        candidates = [
            n
            for n in containing
            if token.replace("%", " percent") in n["title"].casefold()
            or token in str(n.get("value", "")).casefold()
            or token in n.get("placeholder", "").casefold()
        ]
        if not candidates:
            # A compound Link/Button can expose its action instead of its painted text.
            candidates = [
                n
                for n in containing
                if n["role"]
                in ("AXButton", "AXLink", "AXRadioButton", "AXCheckBox", "AXTextField", "AXDateTimeArea")
                or n["id"] == "pds.item"
                or n["role"] == "AXGroup"
                and n["title"].endswith(" account")
            ]
        if candidates:
            owner = min(candidates, key=lambda n: n["w"] * n["h"])
            painted.append(
                dict(box, role="Glyph", title=word["text"], enabled=owner["enabled"], parent=owner["parent"])
            )
    for heading in visible_nodes:
        if heading["title"] not in ("PACE · MODELS", "PACE · MODEL", "PACE · MONTH"):
            continue
        unit = heading["title"].split()[-1]
        observed = [
            word["text"].upper()
            for word in words
            if heading["x"] <= (word["x"] + word["w"] / 2) * width <= right(heading)
            and heading["y"] <= (word["y"] + word["h"] / 2) * height <= bottom(heading)
        ]
        complete = any(unit in word for word in observed)
        record("B6", heading["title"] + " full unit painted", int(complete), complete)
    report["paintedText"] = painted
    for n in nodes + painted:
        role = n["role"]
        if (
            not visible(n)
            or not (n["title"] or role == "AXDateTimeArea" and n.get("value"))
            or role
            not in (
                "Glyph",
                "AXDateTimeArea",
                "AXStaticText",
                "AXHeading",
                "AXLink",
                "AXRadioButton",
                "AXPopUpButton",
                "AXMenuButton",
                "AXButton",
                "AXCheckBox",
                "AXTextField",
            )
        ):
            continue
        # Empty editable fields have no rendered value. Named AX icons and switches
        # expose a spoken action, not a text label within their frame.
        if (
            role == "AXTextField"
            and not (n.get("value") or n.get("placeholder"))
            or role in ("AXButton", "AXMenuButton")
            and n["w"] < 32
        ):
            continue
        if role == "AXCheckBox" and (
            n.get("subrole") == "AXSwitch" or (24 < n["w"] <= 55) or n["w"] <= 24 and n["enabled"]
        ):
            continue
        inset = (
            3 if role in ("AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXButton", "AXTextField") else 0
        )
        samples = []
        for y in range(round((n["y"] + inset) * scale), round((bottom(n) - inset) * scale)):
            for x in range(round((n["x"] + inset) * scale), round((right(n) - inset) * scale)):
                idx = (y * pw + x) * 3
                r, g, b = pixels[idx : idx + 3]
                samples.append(0.2126 * linear[r] + 0.7152 * linear[g] + 0.0722 * linear[b])
        if not samples:
            continue
        samples.sort()
        tail = len(samples) // 500
        substrate = samples
        if role == "Glyph":
            # Fast OCR fits its rectangles tightly around capitals. In those boxes the
            # median can be antialiased ink. Sample the adjacent substrate separately.
            surrounding = []
            for y in (round(n["y"] * scale) - 1, round(bottom(n) * scale)):
                if 0 <= y < ph:
                    for x in range(round(n["x"] * scale), round(right(n) * scale)):
                        idx = (y * pw + x) * 3
                        r, g, b = pixels[idx : idx + 3]
                        surrounding.append(0.2126 * linear[r] + 0.7152 * linear[g] + 0.0722 * linear[b])
            if surrounding:
                substrate = sorted(surrounding)
        bg = substrate[len(substrate) // 2] + 0.05
        ratio = max((samples[-1 - tail] + 0.05) / bg, bg / (samples[tail] + 0.05))
        minimum = 4.5 if n["enabled"] else 3
        record("B8", f"{n['title']} ({role}, {minimum}:1)", ratio, ratio >= minimum)


if __name__ == "__main__":
    data = json.load(sys.stdin)
    check(sys.argv[1], data)
    json.dump(data, sys.stdout, indent=2)
    sys.exit(2 if data["violations"] else 0)
