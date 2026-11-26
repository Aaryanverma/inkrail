#!/usr/bin/env bash
# Build (if needed) and open the Linux writing desk from this source folder.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
BUNDLE="dist/Inkrail-Linux-$(uname -m)"
NEEDS_BUILD=0
if [[ ! -f "$BUNDLE/inkrail" ]]; then
  NEEDS_BUILD=1
else
  # files.sha256 is rewritten at build time, so it is a reliable build stamp.
  if find packaging/linux/inkrail_linux packaging/linux/build-linux.py \
          packaging/windows/ui Sources/Inkrail/Resources docs/assets \
          LICENSE -type f -newer "$BUNDLE/files.sha256" -print -quit | grep -q .; then
    NEEDS_BUILD=1
  fi
fi
if ((NEEDS_BUILD)); then
  python3 packaging/linux/build-linux.py
fi
exec "$BUNDLE/inkrail"
