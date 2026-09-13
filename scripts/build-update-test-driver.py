#!/usr/bin/env python3
"""Build a test-only driver from pinned official Sparkle sources."""
import hashlib
import plistlib
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
expected = {'SPUCommandLineDriver.m': '0924b26df77f726afafed2bb149998c4c27813574c0a9e67ddf69cc0419490b1', 'SPUCommandLineUserDriver.m': '7e23c34763c74afbdbb7095cdd02d23343e9d0836e358e9da1099ff198e51600', 'main.m': '6df90a46bc481a76261f1b5c1a3123572f316fa3dc4463ab4269e2f5ecd0051e', 'SPUCommandLineDriver.h': '3f7d8efdd5b1be0e150ecb75795e70b0cd4fadbd1b18818b2dcf7c26f0dd6171', 'SPUCommandLineUserDriver.h': '525cc91b76b7c88d3f0bc476cfdf0df72c50739c31d3ff71e9da9a6bb4773c42'}

source = root / '.build/sparkle-cli-source'
source.mkdir(parents=True, exist_ok=True)
for name, digest in expected.items():
    path = source / name
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        subprocess.run(['curl', '--fail', '--location', '--retry', '2', '--max-time', '120',
                        '--output', str(path), 'https://raw.githubusercontent.com/sparkle-project/Sparkle/2.9.6/sparkle-cli/' + name], check=True)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, name
framework = next((root / '.build/artifacts').glob('*/Sparkle/Sparkle.xcframework/macos-*/Sparkle.framework'))
app = root / '.build/UpdateCheck.app'
(app / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
(app / 'Contents/Frameworks').mkdir(exist_ok=True)
subprocess.run(['clang', '-fobjc-arc', '-DSPU_OBJC_DIRECT_MEMBERS=', '-DSPU_OBJC_DIRECT=',
                '-F', str(framework.parent), '-framework', 'Sparkle', '-framework', 'Cocoa',
                '-Wl,-rpath,@executable_path/../Frameworks',
                *[str(source / name) for name in expected if name.endswith('.m')],
                '-o', str(app / 'Contents/MacOS/UpdateCheck')], check=True)
subprocess.run(['ditto', str(framework), str(app / 'Contents/Frameworks/Sparkle.framework')], check=True)
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(
    CFBundleExecutable='UpdateCheck', CFBundleIdentifier='local.clipboard.updatecheck',
    CFBundleName='UpdateCheck', CFBundlePackageType='APPL', CFBundleVersion='1',
    CFBundleShortVersionString='1.0', LSUIElement=True,
    NSAppTransportSecurity={'NSAllowsLocalNetworking': True})))
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
print('Built test-only update driver:', app)
