#!/usr/bin/env bash
# Install Inkrail for the current user (no root needed):
#   ~/.local/opt/inkrail, ~/.local/bin/inkrail, menu entry and icon.
# Run with --uninstall to remove it again. Your letters are never touched.
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}
opt=$HOME/.local/opt/inkrail
bin=$HOME/.local/bin

if [[ ${1:-} == --uninstall ]]; then
  rm -rf "$opt"
  rm -f "$bin/inkrail" "$data/applications/inkrail.desktop" "$data/icons/hicolor/512x512/apps/inkrail.png"
  echo "Inkrail removed. Letters remain in $data/Inkrail."
  exit 0
fi

if [[ $src != "$opt" ]]; then
  rm -rf "$opt.new" && mkdir -p "$opt.new"
  cp -a "$src/." "$opt.new/"
  rm -rf "$opt" && mv "$opt.new" "$opt"
fi
mkdir -p "$bin" "$data/applications" "$data/icons/hicolor/512x512/apps"
ln -sf "$opt/inkrail" "$bin/inkrail"
sed "s|^Exec=inkrail|Exec=$opt/inkrail|" "$opt/share/applications/inkrail.desktop" > "$data/applications/inkrail.desktop"
cp "$opt/share/icons/hicolor/512x512/apps/inkrail.png" "$data/icons/hicolor/512x512/apps/inkrail.png"
command -v update-desktop-database >/dev/null && update-desktop-database -q "$data/applications" || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$data/icons/hicolor" || true
echo "Inkrail installed. Launch it from your app menu or run: inkrail"
