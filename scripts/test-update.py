#!/usr/bin/env python3
"""Exercise Sparkle on disposable bundles; never launch or update the real app.

Requires the official Sparkle 2.9.6 command-line driver built at
.build/UpdateCheck.app, and the signing key already provisioned in Keychain.
"""
import functools
import http.server
import json
import plistlib
import shutil
import subprocess
import tempfile
import threading
from pathlib import Path

root = Path(__file__).resolve().parent.parent
config = json.loads((root / 'Config/release.json').read_text())
cli = root / '.build/UpdateCheck.app/Contents/MacOS/UpdateCheck'
tools = next((root / '.build/artifacts').glob('*/Sparkle/bin'))
assert cli.exists(), 'Build the official sparkle-cli driver as described in RELEASE_PROCESS.md.'
work = Path(tempfile.mkdtemp(prefix='clipboard-update-test-', dir=root / '.build'))
source = root / 'dist/Clipboard.app'
old = work / 'installed/Clipboard.app'
new = work / 'new/Clipboard.app'
feed_dir = work / 'feed'; feed_dir.mkdir()

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(feed_dir)))
threading.Thread(target=server.serve_forever, daemon=True).start()
base = f'http://127.0.0.1:{server.server_port}/'

def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)

def bundle(target, version):
    target.parent.mkdir(exist_ok=True)
    run(['ditto', source, target])
    path = target / 'Contents/Info.plist'
    info = plistlib.loads(path.read_bytes())
    info.update(CFBundleIdentifier='local.clipboard.updatetest', CFBundleVersion=version,
                SUFeedURL=base + 'appcast.xml', NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
    path.write_bytes(plistlib.dumps(info))
    run(['codesign', '--force', '--sign', '-', target])

try:
    bundle(old, '9999'); bundle(new, config['build'])
    archive = feed_dir / 'Clipboard-test.zip'
    run(['ditto', '-c', '-k', '--keepParent', new, archive])
    run([tools / 'generate_appcast', '--account', config['keychainAccount'],
         '--download-url-prefix', base, '--maximum-deltas', '0', feed_dir])
    args = [cli, old, '--feed-url', base + 'appcast.xml', '--verbose']
    run(args + ['--probe'], timeout=90)
    print('PASS: newer signed update discovered', flush=True)
    run(args + ['--check-immediately'], timeout=120)
    installed = plistlib.loads((old / 'Contents/Info.plist').read_bytes())
    assert installed['CFBundleVersion'] == config['build']
    run(['codesign', '--verify', '--deep', '--strict', old])
    print('PASS: signed archive downloaded and installed into disposable app', flush=True)
    no_update = subprocess.run([str(a) for a in args + ['--probe']], timeout=60)
    assert no_update.returncode == 4, no_update.returncode
    print('PASS: current version correctly reports no update', flush=True)
    # Restore the disposable old app, then corrupt a byte without changing file length.
    shutil.rmtree(old); bundle(old, '9999')
    data = bytearray(archive.read_bytes()); data[len(data)//2] ^= 1; archive.write_bytes(data)
    rejected = subprocess.run([str(a) for a in args + ['--check-immediately']], timeout=120)
    assert rejected.returncode != 0
    assert plistlib.loads((old / 'Contents/Info.plist').read_bytes())['CFBundleVersion'] == '9999'
    print('PASS: tampered archive rejected; old app preserved', flush=True)
finally:
    server.shutdown()
    print('Test files:', work, flush=True)
