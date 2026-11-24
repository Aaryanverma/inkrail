#!/usr/bin/env bash
# Assemble the portable Linux archive from a published host and the shared desk.
# Usage: assemble.sh <arch> <host-publish-dir> <output.tar.gz> [extra-notices-dir]
set -euo pipefail
arch=$1 host=$2 output=$3 extra_notices=${4:-}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
resources=$root/Sources/Inkrail/Resources
name=Inkrail-Linux-$arch
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
dest=$stage/$name

case "$arch" in x64) machine="x86-64" ;; arm64) machine="aarch64" ;; *) echo "unknown arch $arch" >&2; exit 2 ;; esac
[[ -x $host/inkrail ]] || { echo "missing $host/inkrail" >&2; exit 1; }
# Refuse a host built for the wrong CPU (ELF e_machine: 0x3e x86-64, 0xb7 aarch64).
e_machine=$(od -An -tx2 -j18 -N2 "$host/inkrail" | tr -d ' ')
[[ $arch == x64 && $e_machine == 003e || $arch == arm64 && $e_machine == 00b7 ]] \
  || { echo "inkrail is not a $machine executable (e_machine=$e_machine)" >&2; exit 1; }

mkdir -p "$dest/ui/assets" "$dest/notices" "$dest/share/applications" "$dest/share/icons/hicolor/512x512/apps"
install -m 755 "$host/inkrail" "$dest/inkrail"
# Both desktop builds ship the same editor, fonts, artwork and recordings.
(cd "$root/packaging/windows" && find ui notices -type f ! -name '.*' -print0 | xargs -0 -I{} install -D -m 644 {} "$dest/{}")
for f in "$resources"/*.png "$resources"/*.wav; do install -m 644 "$f" "$dest/ui/assets/"; done
install -m 644 "$resources/Sound-Credits.txt" "$dest/notices/Sound-Credits.txt"
install -m 644 "$root/LICENSE" "$dest/LICENSE.txt"
[[ -n $extra_notices ]] && cp -r "$extra_notices/." "$dest/notices/"
install -m 644 "$here/inkrail.desktop" "$dest/share/applications/inkrail.desktop"
install -m 644 "$resources/AppIcon.png" "$dest/share/icons/hicolor/512x512/apps/inkrail.png"
install -m 755 "$here/install.sh" "$dest/install.sh"
install -m 644 "$here/START-HERE.txt" "$dest/START-HERE.txt"

(cd "$dest" && find . -type f ! -name files.sha256 -printf '%P\0' | sort -z | xargs -0 sha256sum > files.sha256)
mkdir -p "$(dirname "$output")"
tar -C "$stage" --owner=0 --group=0 --numeric-owner --sort=name -czf "$output" "$name"
echo "Created $output with $(wc -l < "$dest/files.sha256") files ($arch)"
