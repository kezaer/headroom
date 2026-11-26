"""Measure ink and background luminance inside disabled AX text frames."""
import struct
import subprocess


def check(capture, report):
    frames = report["disabledTextFrames"]
    scores = report["disabledTextContrast"] = []
    if not frames:
        return
    with capture.open("rb") as png:
        png.seek(16)
        width, height = struct.unpack(">II", png.read(8))
    pixels = subprocess.check_output(["magick", str(capture), "-colorspace", "sRGB", "-depth", "8", "rgb:-"])
    if len(pixels) != width * height * 3:
        raise ValueError("Unexpected capture raster size")
    linear = [v / 12.92 if v < 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in (i / 255 for i in range(256))]
    for x, y, w, h in frames:
        samples = []
        for row in range(max(0, round(y * height)), min(height, round((y + h) * height))):
            for col in range(max(0, round(x * width)), min(width, round((x + w) * width))):
                index = 3 * (row * width + col)
                r, g, b = pixels[index:index + 3]
                samples.append(0.2126 * linear[r] + 0.7152 * linear[g] + 0.0722 * linear[b])
        if samples:
            samples.sort()
            # Trim the single brightest/darkest percent to limit edge and antialias noise.
            tail = len(samples) // 100
            ratio = (samples[-tail - 1] + 0.05) / (samples[tail] + 0.05)
            scores.append(ratio)
            if ratio < 3:
                report["violations"].append(f"Disabled text contrast {ratio:.2f}:1 at ({x:.3f}, {y:.3f})")
