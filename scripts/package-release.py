#!/usr/bin/env python3
"""Package a built app, sign its update, and validate the resulting feed."""
import hashlib
import json
import plistlib
import shutil
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parent.parent
config = json.loads((root / 'Config/release.json').read_text())
app = root / 'dist/Clipboard.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleShortVersionString'] == config['version']
assert info['CFBundleVersion'] == config['build']
assert info['SUPublicEDKey'] == config['publicEDKey']
assert info['SUFeedURL'] == config['feedURL']
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
output = root / 'dist' / ('release-' + config['version'])
output.mkdir(exist_ok=True)
archive = output / ('Clipboard-' + config['version'] + '-macOS-arm64.zip')
# Do not append into an existing ZIP when repackaging an unpublished local build.
archive.unlink(missing_ok=True)
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
notes = archive.with_suffix('.md')
shutil.copyfile(root / 'RELEASE_NOTES.md', notes)
tools = next((root / '.build/artifacts').glob('*/Sparkle/bin'))
base = 'https://github.com/' + config['repository'] + '/releases/download/v' + config['version'] + '/'
feed = output / 'appcast.xml'
feed.unlink(missing_ok=True)
subprocess.run([str(tools / 'generate_appcast'), '--account', config['keychainAccount'],
                '--download-url-prefix', base, '--embed-release-notes', '--maximum-deltas', '0',
                '-o', str(feed), str(output)], check=True)
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
item = ET.parse(feed).find('./channel/item')
assert item is not None
assert item.findtext('sparkle:version', namespaces=ns) == config['build']
assert item.findtext('sparkle:shortVersionString', namespaces=ns) == config['version']
enclosure = item.find('enclosure')
assert enclosure.get('url') == base + archive.name
assert int(enclosure.get('length')) == archive.stat().st_size
signature = enclosure.get('{' + ns['sparkle'] + '}edSignature')
assert signature
subprocess.run(['swift', str(root / 'scripts/verify-update.swift'), str(archive), config['publicEDKey'], signature], check=True)
files = [archive, feed, notes]
(output / 'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in files))
print('Release artifacts verified:', output)
