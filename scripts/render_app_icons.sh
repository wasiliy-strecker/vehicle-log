#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_icon=assets/branding/fahrzeugakte_icon.svg
convert -background none "$source_icon" -resize 1024x1024 assets/branding/fahrzeugakte_icon_1024.png
for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${spec%:*}"
  size="${spec#*:}"
  convert -background none "$source_icon" -resize "${size}x${size}" "android/app/src/main/res/mipmap-${density}/ic_launcher.png"
done
for size in 192 512; do
  convert -background none "$source_icon" -resize "${size}x${size}" "web/icons/Icon-${size}.png"
  convert -background '#243D53' "$source_icon" -resize "${size}x${size}" -alpha remove "web/icons/Icon-maskable-${size}.png"
done
convert -background none "$source_icon" -resize 32x32 web/favicon.png
for icon in ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png; do
  dimensions="$(identify -format '%wx%h' "$icon")"
  convert -background '#243D53' "$source_icon" -resize "$dimensions" -alpha remove "$icon"
done
