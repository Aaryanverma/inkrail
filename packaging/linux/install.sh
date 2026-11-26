#!/usr/bin/env bash
# Install the Inkrail Linux bundle for the current user and check its runtime.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUNDLE=""
INSTALL_DEPS=0
CHECK_ONLY=0

while (($#)); do
  case "$1" in
    --bundle) BUNDLE="$2"; shift 2 ;;
    --install-deps) INSTALL_DEPS=1; shift ;;
    --check-deps) CHECK_ONLY=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

detect_distro() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID_LIKE:-$ID}" in
      *arch*) echo arch ;;
      *debian*|*ubuntu*) echo debian ;;
      *fedora*|*rhel*) echo fedora ;;
      *) echo "$ID" ;;
    esac
  else
    echo unknown
  fi
}

check_dependencies() {
  python3 - <<'PY'
import sys
try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("WebKit2", "4.1")
    from gi.repository import Gtk, WebKit2  # noqa: F401
except Exception as error:
    print(f"Missing desktop bindings: {error}", file=sys.stderr)
    raise SystemExit(1)
PY
  for command in xdg-open; do
    command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; return 1; }
  done
  echo "All Inkrail runtime dependencies are present."
}

install_dependencies() {
  local distro packages=() install=()
  distro="$(detect_distro)"
  case "$distro" in
    arch) packages=(gtk3 webkit2gtk-4.1 python-gobject gstreamer gst-plugins-base
                    gst-plugins-good xdg-utils) ;;
    debian) packages=(python3-gi gir1.2-gtk-3.0 gir1.2-webkit2-4.1
                      gstreamer1.0-plugins-base gstreamer1.0-plugins-good xdg-utils) ;;
    fedora) packages=(gtk3 webkit2gtk4.1 python3-gobject gstreamer1.0-plugins-base
                      gstreamer1.0-plugins-good xdg-utils) ;;
    *) echo "Install GTK 3, WebKitGTK 4.1 and their Python introspection bindings manually." >&2
       return 1 ;;
  esac
  case "$distro" in
    arch) install=(sudo pacman -S --needed "${packages[@]}") ;;
    debian) install=(sudo apt install "${packages[@]}") ;;
    fedora) install=(sudo dnf install "${packages[@]}") ;;
  esac
  echo "Installing: ${packages[*]}"
  "${install[@]}"
}

if ((CHECK_ONLY)); then
  check_dependencies
  exit $?
fi
if ((INSTALL_DEPS)); then
  install_dependencies
fi
check_dependencies

if [[ -z "$BUNDLE" ]]; then
  BUNDLE="$(find "$ROOT/dist" -maxdepth 1 -type d -name 'Inkrail-Linux-*' 2>/dev/null | head -1 || true)"
fi
[[ -n "$BUNDLE" && -f "$BUNDLE/inkrail" ]] || { echo "No Linux bundle found. Run build-linux.py first." >&2; exit 1; }
BUNDLE="$(cd "$BUNDLE" && pwd)"

DEST="$HOME/.local/share/inkrail"
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" \
         "$HOME/.local/share/icons/hicolor/512x512/apps"
rm -rf "$DEST"
cp -a "$BUNDLE" "$DEST"
ln -sfn "$DEST/inkrail" "$HOME/.local/bin/inkrail"
sed "s|^Exec=inkrail$|Exec=$DEST/inkrail|" "$DEST/share/applications/inkrail.desktop" \
  > "$HOME/.local/share/applications/inkrail.desktop"
cp "$DEST/share/icons/hicolor/512x512/apps/inkrail.png" \
  "$HOME/.local/share/icons/hicolor/512x512/apps/inkrail.png"
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" || true
echo "Inkrail installed to $DEST. Open it from your app launcher or run ~/.local/bin/inkrail."
echo "If ~/.local/bin is not in your PATH, add: export PATH=\"\$HOME/.local/bin:\$PATH\""
