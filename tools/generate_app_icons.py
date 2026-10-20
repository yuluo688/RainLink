"""Generate native launcher assets from the unchanged Figma brand PNG export.

Install tools/requirements-design.txt, then run this script from any directory.
"""

from __future__ import annotations

import argparse
import io
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design/exports/runtime-assets/brand-1024.png"
ICO_SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    with Image.open(SOURCE) as image:
        if image.size != (1024, 1024):
            raise ValueError("The Figma brand export must be 1024 × 1024.")
        source = image.convert("RGBA")

    targets: dict[Path, tuple[int, bool]] = {}
    for platform in ("ios", "macos"):
        folder = ROOT / f"app/{platform}/Runner/Assets.xcassets/AppIcon.appiconset"
        catalog = json.loads((folder / "Contents.json").read_text("utf-8"))
        for item in catalog["images"]:
            if "filename" not in item:
                continue
            points = float(item["size"].split("x")[0])
            scale_text = item["scale"]
            if not scale_text.endswith("x"):
                raise ValueError("Invalid native icon scale")
            scale = float(scale_text[:-1])
            targets[folder / item["filename"]] = (
                round(points * scale), platform == "ios"
            )

    for density, size in {
        "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192
    }.items():
        path = ROOT / f"app/android/app/src/main/res/mipmap-{density}/ic_launcher.png"
        targets[path] = (size, False)

    targets[ROOT / "app/linux/runner/resources/rainlink.png"] = (512, False)

    for path, (size, opaque) in targets.items():
        output = source.resize((size, size), Image.Resampling.LANCZOS)
        if opaque:
            # iOS applies its own mask and requires opaque App Store artwork.
            background = Image.new("RGBA", output.size, "#1B2B25")
            background.alpha_composite(output)
            output = background.convert("RGB")
        encoded = io.BytesIO()
        output.save(encoded, format="PNG", optimize=True)
        if args.check:
            if not path.is_file():
                raise FileNotFoundError(f"Missing generated launcher asset: {path}")
            if path.read_bytes() != encoded.getvalue():
                raise ValueError(f"Stale generated launcher asset: {path}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(encoded.getvalue())

    ico = ROOT / "app/windows/runner/resources/app_icon.ico"
    encoded = io.BytesIO()
    source.save(encoded, format="ICO", sizes=[(size, size) for size in ICO_SIZES])
    if args.check:
        if ico.read_bytes() != encoded.getvalue():
            raise ValueError("Stale Windows application icon.")
    else:
        ico.write_bytes(encoded.getvalue())
    print(
        f"{'Verified' if args.check else 'Generated'} {len(targets)} PNG assets "
        f"and one ICO ({len(ICO_SIZES)} resolutions) from Figma node 2:16609."
    )


if __name__ == "__main__":
    main()
