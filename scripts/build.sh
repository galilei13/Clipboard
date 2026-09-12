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
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Clipboard</string>
<key>CFBundleIdentifier</key><string>local.clipboard.app</string>
<key>CFBundleName</key><string>Clipboard</string>
<key>CFBundleDisplayName</key><string>Clipboard</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - --identifier local.clipboard.app "$bundle"
codesign --verify --strict "$bundle"
printf 'Built %s\n' "$bundle"
