#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/.build/Speech Cleaner.app"
ICON_WORK="$ROOT/.build/AppIcon.iconset"
BASE_ICON="$ROOT/.build/AppIcon-1024.png"

cd "$ROOT"
swift build -c release

rm -rf "$APP" "$ICON_WORK"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICON_WORK"
cp "$ROOT/.build/release/SpeechCleaner" "$APP/Contents/MacOS/SpeechCleaner"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

sips -s format png "$ROOT/Resources/AppIcon.svg" --out "$BASE_ICON" >/dev/null
for spec in "16:icon_16x16.png" "32:icon_16x16@2x.png" "32:icon_32x32.png" "64:icon_32x32@2x.png" "128:icon_128x128.png" "256:icon_128x128@2x.png" "256:icon_256x256.png" "512:icon_256x256@2x.png" "512:icon_512x512.png" "1024:icon_512x512@2x.png"; do
    size="${spec%%:*}"
    name="${spec#*:}"
    sips -z "$size" "$size" "$BASE_ICON" --out "$ICON_WORK/$name" >/dev/null
done
iconutil -c icns "$ICON_WORK" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/NitqTemiz.app"
    rm -rf "/Applications/Speech Cleaner.app"
    ditto "$APP" "/Applications/Speech Cleaner.app"
    codesign --verify --deep --strict "/Applications/Speech Cleaner.app"
    echo "/Applications/Speech Cleaner.app"
else
    echo "$APP"
fi
