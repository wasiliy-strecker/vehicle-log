#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_mark=assets/branding/fahrzeugakte_mark.svg
source_icon=assets/branding/fahrzeugakte_icon_1024.png
render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT

# Use the same vector paths for native Android and all raster exports.
# The native foreground has no background, shadows or raster scaling.
python3 - "$source_mark" "$render_dir" <<'PY'
import copy
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import cairo
import gi

gi.require_version("Rsvg", "2.0")
from gi.repository import Rsvg

source = ET.parse(sys.argv[1]).getroot()
output = Path(sys.argv[2])
svg_ns = "http://www.w3.org/2000/svg"
android_ns = "http://schemas.android.com/apk/res/android"
ET.register_namespace("", svg_ns)
ET.register_namespace("android", android_ns)
vector = ET.Element("vector", {
    f"{{{android_ns}}}width": "108dp",
    f"{{{android_ns}}}height": "108dp",
    f"{{{android_ns}}}viewportWidth": "108",
    f"{{{android_ns}}}viewportHeight": "108",
})
for path in source:
    if path.tag != f"{{{svg_ns}}}path" or set(path.attrib) != {"fill", "fill-rule", "d"}:
        raise ValueError("The icon source must contain only flat, filled paths")
    ET.SubElement(vector, "path", {
        f"{{{android_ns}}}fillColor": path.attrib["fill"],
        f"{{{android_ns}}}fillType": {"evenodd": "evenOdd", "nonzero": "nonZero"}[path.attrib["fill-rule"]],
        f"{{{android_ns}}}pathData": path.attrib["d"],
    })
ET.indent(vector, space="    ")
Path("android/app/src/main/res/drawable/ic_launcher_foreground.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    + ET.tostring(vector, encoding="unicode") + '\n'
)
for name, view_box in [("icon", "12 12 84 84"), ("maskable", "0 0 108 108")]:
    icon = copy.deepcopy(source)
    icon.set("viewBox", view_box)
    icon.set("width", "1024")
    icon.set("height", "1024")
    icon.insert(0, ET.Element(f"{{{svg_ns}}}rect", {
        "width": "108", "height": "108", "fill": "#243D53",
    }))
    # Rasterize curves at the target size, using librsvg rather than MSVG.
    handle = Rsvg.Handle.new_from_data(ET.tostring(icon))
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 1024, 1024)
    viewport = Rsvg.Rectangle()
    viewport.x = viewport.y = 0
    viewport.width = viewport.height = 1024
    handle.render_document(cairo.Context(surface), viewport)
    surface.write_to_png(str(output / f"{name}.png"))
PY
convert "$render_dir/icon.png" \
  -alpha remove -alpha off "$source_icon"
for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${spec%:*}"
  size="${spec#*:}"
  convert "$source_icon" -filter Lanczos -resize "${size}x${size}" "android/app/src/main/res/mipmap-${density}/ic_launcher.png"
done
for size in 192 512; do
  convert "$source_icon" -filter Lanczos -resize "${size}x${size}" "web/icons/Icon-${size}.png"
  convert "$render_dir/maskable.png" \
    -filter Lanczos -resize "${size}x${size}" "web/icons/Icon-maskable-${size}.png"
done
convert "$source_icon" -filter Lanczos -resize 32x32 web/favicon.png
for icon in ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png; do
  dimensions="$(identify -format '%wx%h' "$icon")"
  convert "$source_icon" -filter Lanczos -resize "$dimensions" "$icon"
done
