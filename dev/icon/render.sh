#!/bin/bash
# Render AppIcon.svg into the app's asset catalog. Run after editing the SVG.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/../../src/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$out"
uv run --with resvg_py python - "$here/AppIcon.svg" "$out" <<'PY'
import json, sys, resvg_py
svg, out = sys.argv[1], sys.argv[2]
images = []
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = pt * scale
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        png = resvg_py.svg_to_bytes(svg_path=svg, width=px, height=px)
        open(f"{out}/{name}", "wb").write(bytes(png))
        images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x", "filename": name})
json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, open(f"{out}/Contents.json", "w"), indent=2)
PY
