#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration" --disable-sandbox
binary_dir="$(swift build -c "$configuration" --show-bin-path --disable-sandbox)"
bundle="$PWD/dist/Clipboard.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/Clipboard" "$bundle/Contents/MacOS/Clipboard"
swift scripts/GenerateIcon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$bundle/Contents/Resources/AppIcon.icns"
cp THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
python3 scripts/configure-bundle.py
sparkle_framework="$(find .build/artifacts -type d -path '*/macos-*/Sparkle.framework' -print -quit)"
if [[ -z "$sparkle_framework" ]]; then
    echo "Sparkle.framework was not found in the resolved package artifacts." >&2
    exit 1
fi
mkdir -p "$bundle/Contents/Frameworks"
ditto "$sparkle_framework" "$bundle/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --identifier local.clipboard.app "$bundle"
codesign --verify --deep --strict "$bundle"
printf 'Built %s\n' "$bundle"
