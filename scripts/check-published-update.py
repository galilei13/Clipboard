#!/usr/bin/env python3
"""Read-only Sparkle probe of the app in the latest public GitHub release."""
import json
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
config = json.loads((root / 'Config/release.json').read_text())
work = Path(tempfile.mkdtemp(prefix='published-update-', dir=root / '.build'))
metadata = subprocess.check_output(['curl', '--fail', '--location', '--silent', '--show-error',
    '--max-time', '60', 'https://api.github.com/repos/' + config['repository'] + '/releases/latest'])
release = json.loads(metadata)
asset = next(a for a in release['assets'] if a['name'].endswith('-macOS-arm64.zip'))
archive = work / asset['name']
subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error', '--retry', '2',
    '--max-time', '180', '--output', str(archive), asset['browser_download_url']], check=True)
subprocess.run(['ditto', '-x', '-k', str(archive), str(work)], check=True)
result = subprocess.run([str(root / '.build/UpdateCheck.app/Contents/MacOS/UpdateCheck'),
    str(work / 'Clipboard.app'), '--probe', '--verbose'], timeout=120)
assert result.returncode == 4, 'Expected no update for the latest public release; Sparkle exit ' + str(result.returncode)
print('PASS: Sparkle reached the public feed and correctly found no newer update for ' + release['tag_name'])
