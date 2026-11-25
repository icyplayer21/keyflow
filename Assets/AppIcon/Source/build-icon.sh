#!/bin/bash
# Rebuilds the Keyflow app icon from source: legend textures, Blender renders,
# 1024 masters, every icon size, the .icns, the asset catalog set and a
# preview sheet. Needs Blender (5.x) in /Applications. Takes a few minutes.
# Usage: Assets/AppIcon/Source/build-icon.sh [samples]
set -euo pipefail
cd "$(dirname "$0")/.."
SAMPLES="${1:-512}"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swiftc -O Source/icontool.swift -o "$WORK/icontool"
swift Source/legend.swift "$WORK"
# The app icon: the key on an aluminium deck, clipped to the macOS icon
# shape. macOS 26 and later put free-form icons on a grey tile of their own,
# so the icon supplies a deliberate one. "symbol" (the ⌘ alone) serves 64 px
# and smaller.
for variant in full symbol; do
    "$BLENDER" -b --factory-startup --python Source/keycap.py -- \
        "$WORK/legend-$variant.png" "$WORK/deck-$variant.png" 2048 "$SAMPLES" 160 deck >/dev/null
done
"$WORK/icontool" squircle "$WORK/deck-full.png" AppIcon-1024.png Source/icon-shape-1024.png
"$WORK/icontool" squircle "$WORK/deck-symbol.png" AppIcon-Small-1024.png Source/icon-shape-1024.png

# The keycap alone on transparency, for marketing and the DMG background.
"$BLENDER" -b --factory-startup --python Source/keycap.py -- \
    "$WORK/legend-full.png" "$WORK/key.png" 2048 "$SAMPLES" 208 key >/dev/null
"$WORK/icontool" crop "$WORK/key.png" Keycap-1024.png 1024 0 0

rm -rf AppIcon.iconset
"$WORK/icontool" iconset AppIcon-1024.png AppIcon-Small-1024.png AppIcon.iconset
iconutil -c icns AppIcon.iconset -o AppIcon.icns

# The same images as an asset catalog icon set, for an Xcode project.
rm -rf AppIcon.appiconset
mkdir AppIcon.appiconset
cp AppIcon.iconset/*.png AppIcon.appiconset/
cat > AppIcon.appiconset/Contents.json <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

"$WORK/icontool" preview AppIcon-1024.png AppIcon-Small-1024.png Preview.png
echo "Icon built: $(pwd)/AppIcon.icns"
