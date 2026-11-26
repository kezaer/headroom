#!/usr/bin/env node
// Pacemark app-icon generator — the single source of truth for the app icon.
//
// Apple icon assets are square artwork. iOS, iPadOS, and current macOS icon surfaces apply
// their own rounded shape, so the art must be full-bleed instead of baking a second rounded
// tile with transparent padding into the PNGs.
//
// Renders the master SVG at every size required by AppIcon.appiconset via `npx sharp-cli`
// (rasterizes the SVG natively at each target size for crisp small icons), then strips
// the unused alpha channel with `oxipng` so App Store validation sees opaque RGB PNGs.

import { writeFileSync } from "node:fs";
import { execFileSync, spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repo = join(__dirname, "..");
const iconset = join(repo, "Sources/PacemarkApp/Resources/Assets.xcassets/AppIcon.appiconset");
const designDir = join(repo, "design");

const S = 1024; // master canvas

// --- vessel geometry ---------------------------------------------------------------
const cap = { x: 346, y: 202, w: 332, h: 620, rx: 166, sw: 22 };
const inset = 30;
const inX = cap.x + inset, inW = cap.w - inset * 2, r = inW / 2;
const inTop = cap.y + inset, inBot = cap.y + cap.h - inset;
const fill = 0.46;
const liquidTop = inBot - (inBot - inTop) * fill;
const arcStartY = inBot - r;
const liquid = `M${inX} ${liquidTop} H${inX + inW} V${arcStartY} A${r} ${r} 0 0 1 ${inX} ${arcStartY} Z`;

const svg = `<svg width="${S}" height="${S}" viewBox="0 0 ${S} ${S}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0.1" y1="0" x2="0.92" y2="1">
      <stop offset="0" stop-color="#33404f"/>
      <stop offset="0.5" stop-color="#1a2330"/>
      <stop offset="1" stop-color="#0b111a"/>
    </linearGradient>
    <linearGradient id="liquid" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#93ffc6"/>
      <stop offset="0.5" stop-color="#4bdd97"/>
      <stop offset="1" stop-color="#1fac70"/>
    </linearGradient>
    <linearGradient id="topHi" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.16"/>
      <stop offset="0.42" stop-color="#ffffff" stop-opacity="0.02"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="wall" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.98"/>
      <stop offset="0.5" stop-color="#dfe8e6" stop-opacity="0.86"/>
      <stop offset="1" stop-color="#b7c4c2" stop-opacity="0.82"/>
    </linearGradient>
    <radialGradient id="vig" cx="0.5" cy="0.95" r="0.85">
      <stop offset="0.5" stop-color="#000000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0.30"/>
    </radialGradient>
    <filter id="glow" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur stdDeviation="18" result="b"/>
      <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>

  <rect x="0" y="0" width="${S}" height="${S}" fill="url(#bg)"/>
  <rect x="0" y="0" width="${S}" height="${S}" fill="url(#topHi)"/>
  <g filter="url(#glow)"><path d="${liquid}" fill="url(#liquid)"/></g>
  <rect x="${inX}" y="${liquidTop - 7}" width="${inW}" height="13" rx="6.5" fill="#eafff4" opacity="0.42"/>
  <rect x="${cap.x}" y="${cap.y}" width="${cap.w}" height="${cap.h}" rx="${cap.rx}"
        fill="none" stroke="url(#wall)" stroke-width="${cap.sw}"/>
  <rect x="0" y="0" width="${S}" height="${S}" fill="url(#vig)"/>
</svg>`;

const masterPath = join(designDir, "vessel-app-icon.svg");
writeFileSync(masterPath, svg);
console.log("wrote", masterPath);

const sizes = [
  16, 20, 29, 32, 40, 58, 60, 64, 76, 80, 87, 120,
  128, 152, 167, 180, 256, 512, 1024
];
const renderedFiles = [];
for (const px of sizes) {
  const out = join(iconset, `icon_${px}.png`);
  execFileSync("npx", ["--yes", "sharp-cli", "--input", masterPath, "--output", out, "resize", String(px), String(px)],
    { stdio: ["ignore", "ignore", "inherit"] });
  renderedFiles.push(out);
  console.log("rendered", `icon_${px}.png`);
}

// Refreshed 1024 preview alongside the master for the design/ folder.
const previewPath = join(designDir, "vessel-app-icon-1024.png");
execFileSync("npx", ["--yes", "sharp-cli", "--input", masterPath, "--output", previewPath,
  "resize", "1024", "1024"], { stdio: ["ignore", "ignore", "inherit"] });

if (spawnSync("oxipng", ["--version"], { stdio: "ignore" }).status !== 0) {
  console.error("oxipng is required to strip the unused alpha channel. Install with: brew install oxipng");
  process.exit(69);
}

execFileSync("oxipng", ["-o", "2", "--strip", "safe", ...renderedFiles, previewPath],
  { stdio: ["ignore", "ignore", "inherit"] });
console.log("optimized PNGs with oxipng");
console.log("done");
