#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --disable-sandbox --product ClipboardChecks
binary_dir="$(swift build --disable-sandbox --show-bin-path)"
"$binary_dir/ClipboardChecks"
