#!/usr/bin/env python3
"""Write bundle metadata from the versioned, public release configuration."""
import json
import plistlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent
config = json.loads((root / 'Config/release.json').read_text())
if not config['publicEDKey']:
    raise SystemExit('Set publicEDKey in Config/release.json using Sparkle generate_keys first.')
info = {
    'CFBundleExecutable': 'Clipboard', 'CFBundleIdentifier': 'local.clipboard.app',
    'CFBundleName': 'Clipboard', 'CFBundleDisplayName': 'Clipboard',
    'CFBundlePackageType': 'APPL', 'CFBundleIconFile': 'AppIcon',
    'CFBundleShortVersionString': config['version'], 'CFBundleVersion': config['build'],
    'LSMinimumSystemVersion': '13.0', 'LSUIElement': True,
    'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication',
    'SUFeedURL': config['feedURL'], 'SUPublicEDKey': config['publicEDKey'],
    'SUEnableAutomaticChecks': True, 'SUAutomaticallyUpdate': False,
    'SUAllowsAutomaticUpdates': True, 'SUEnableSystemProfiling': False,
    'SUVerifyUpdateBeforeExtraction': True,
}
with (root / 'dist/Clipboard.app/Contents/Info.plist').open('wb') as file:
    plistlib.dump(info, file)
