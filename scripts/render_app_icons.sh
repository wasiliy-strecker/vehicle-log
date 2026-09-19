#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_mark=assets/branding/fahrzeugakte_mark.png
source_icon=assets/branding/fahrzeugakte_icon_1024.png
foreground=android/app/src/main/res/drawable-nodpi/ic_vehicle_foreground.png
mkdir -p "$(dirname "$foreground")"

# The transparent master is rendered into Android's adaptive-icon safe area.
# Keep the large foreground separate from the small legacy launcher bitmaps.
# Ignore near-invisible alpha noise only when measuring the content bounds.
# Preserve the original alpha and antialiasing inside that crop.
content_bounds="$(convert "$source_mark" -alpha extract -threshold 1% -format '%@' info:)"
convert "$source_mark" -crop "$content_bounds" +repage -filter Lanczos -resize 550x550 \
  -gravity center -background none -extent 1080x1080 "$foreground"
convert "$source_mark" -crop "$content_bounds" +repage -filter Lanczos \
  -resize 840x840 -gravity center -background '#243D53' -extent 1024x1024 \
  -alpha remove -alpha off "$source_icon"
for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${spec%:*}"
  size="${spec#*:}"
  convert "$source_icon" -filter Lanczos -resize "${size}x${size}" "android/app/src/main/res/mipmap-${density}/ic_launcher.png"
done
for size in 192 512; do
  convert "$source_icon" -filter Lanczos -resize "${size}x${size}" "web/icons/Icon-${size}.png"
  convert "$foreground" -background '#243D53' -alpha remove -alpha off \
    -filter Lanczos -resize "${size}x${size}" "web/icons/Icon-maskable-${size}.png"
done
convert "$source_icon" -filter Lanczos -resize 32x32 web/favicon.png
for icon in ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png; do
  dimensions="$(identify -format '%wx%h' "$icon")"
  convert "$source_icon" -filter Lanczos -resize "$dimensions" "$icon"
done
